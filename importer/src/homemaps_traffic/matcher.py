"""From an NDW line to Valhalla's edge ids, with a cache on disk.

Nearly all travel time segments are only a start and an end point (median 500 m).
That is why they are routed rather than map-matched: the route from start to end
*is* the segment, and the direction of travel follows from the order of the points.
The edges of that route come from trace_attributes (edge_walk on the route shape).

Edge ids change with every tile build. The cache therefore belongs to one tileset
(`tileset_last_modified` from /status) and is thrown away otherwise.
"""

import http.client
import json
import logging
import math
import threading
import urllib.error
import urllib.parse
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from .datex3 import Point

log = logging.getLogger(__name__)

MAX_LOCATIONS = 20


@dataclass(frozen=True)
class Match:
    edges: tuple[tuple[int, float, int], ...]  # (graphid, length in m, way_id)
    length_m: float
    # The route shape per leg, as Valhalla's polyline (six decimals): the line on
    # the map. NDW's own line is usually just start and end.
    shape: tuple[str, ...] = ()

    def to_json(self):
        return {
            "e": [list(edge) for edge in self.edges],
            "l": round(self.length_m, 1),
            "v": list(self.shape),
        }

    @classmethod
    def from_json(cls, data) -> "Match":
        return cls(tuple((e[0], e[1], e[2]) for e in data["e"]), data["l"], tuple(data["v"]))


def haversine(a: Point, b: Point) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * 6371000 * math.asin(math.sqrt(h))


class Valhalla:
    """One persistent connection per thread. With a new connection per request,
    matching 67,000 segments (2 requests each, ~600/s) exhausts the ephemeral
    ports -- every closed connection stays in TIME_WAIT for 60 s -- and then a
    third of the requests fail in waves."""

    def __init__(self, url: str, timeout: float = 30):
        parts = urllib.parse.urlsplit(url)
        self.host, self.port = parts.hostname, parts.port or 80
        self.base = parts.path.rstrip("/")
        self.timeout = timeout
        self._local = threading.local()

    def _request(self, path: str, body: dict | None = None) -> dict:
        data = json.dumps(body).encode() if body is not None else None
        for attempt in (1, 2):
            connection = getattr(self._local, "connection", None)
            if connection is None:
                connection = http.client.HTTPConnection(self.host, self.port, timeout=self.timeout)
                self._local.connection = connection
            try:
                connection.request(
                    "POST" if data is not None else "GET",
                    self.base + path,
                    data,
                    {"Content-Type": "application/json"},
                )
                response = connection.getresponse()
                content = response.read()
            except (OSError, http.client.HTTPException):
                # The server may close an idle connection; retrying once with a
                # fresh one is then not an error.
                connection.close()
                self._local.connection = None
                if attempt == 2:
                    raise
                continue
            if response.status >= 400:
                raise urllib.error.HTTPError(
                    path, response.status, content[:200].decode(), {}, None
                )
            return json.loads(content)
        raise AssertionError("unreachable")

    def tileset(self) -> int:
        return int(self._request("/status").get("tileset_last_modified", 0))

    def match(
        self, points: Iterable[Point], max_detour: float = 1.6, *, covered_only: bool = False
    ) -> Match | None:
        """None if there is no credible route; that is a definitive answer and may
        go into the cache. A temporary error (connection lost, timeout) comes out
        as OSError, so the caller tries again later.

        `max_detour`: a route that is much longer than the line itself is a
        different road (the point landed on the wrong carriageway or a frontage
        road), and then no match is better than a wrong one.

        `covered_only` is for closures: those always close an edge completely,
        even if the line only touches its edge. A line over an exit often starts
        on the main carriageway, just past where the exit branches off in OSM.
        Therefore:
        - an edge at the start or end only counts if the line covers at least
          half of it (see `_covered`);
        - the line itself is map-matched if routing yields no credible route:
          from that point on the main carriageway to the exit it is otherwise a
          detour of kilometres.
        """
        points = _dedupe(points)
        if len(points) < 2:
            return None
        line = sum(haversine(a, b) for a, b in zip(points, points[1:], strict=False))
        try:
            found = self._route(points, line, max_detour)
            if found is None and covered_only:
                found = self._snap(points, line)
        except (KeyError, ValueError) as error:
            log.debug("unexpected response: %s", error)
            return None
        if found is None:
            return None
        match, fractions = found
        if covered_only:
            match = _covered(match, fractions)
        return match

    def _route(
        self, points: list[Point], line: float, max_detour: float
    ) -> tuple[Match, list[float]] | None:
        """The route through the points, with per edge which fraction of it is driven."""
        edges: list[tuple[int, float, int]] = []
        fractions: list[float] = []
        shape: list[str] = []
        length = 0.0
        try:
            # Blocks that overlap each other by one point: Valhalla takes at most 20
            # locations per request. Intermediate points are `break`, not `through`:
            # with `directions_type: none` Valhalla trips over through locations
            # ("leg_shape_index not set for intermediate").
            for start in range(0, len(points) - 1, MAX_LOCATIONS - 1):
                block = points[start : start + MAX_LOCATIONS]
                route = self._request(
                    "/route",
                    {
                        "locations": [{"lat": lat, "lon": lon} for lat, lon in block],
                        "costing": "auto",
                        "units": "kilometers",
                        # The measurement belongs to the road as it lies, not to
                        # the route that happens to be fastest today.
                        "costing_options": {
                            "auto": {"shortest": True, "speed_types": ["freeflow", "constrained"]}
                        },
                        "directions_type": "none",
                    },
                )
                length += route["trip"]["summary"]["length"] * 1000
                if length > line * max_detour + 150:
                    return None
                for leg in route["trip"]["legs"]:
                    shape.append(leg["shape"])
                    trace = self._request(
                        "/trace_attributes",
                        {
                            "encoded_polyline": leg["shape"],
                            "costing": "auto",
                            "shape_match": "walk_or_snap",
                            "filters": {"attributes": TRACE_ATTRIBUTES, "action": "include"},
                        },
                    )
                    _append(edges, fractions, trace["edges"])
        except urllib.error.HTTPError as error:
            # A 4xx is "no route": the point lies outside the tileset or on a
            # road a car cannot use. A 5xx is Valhalla's problem.
            if error.code >= 500:
                raise
            log.debug("no route: %s", error)
            return None
        return (Match(tuple(edges), length, tuple(shape)), fractions) if edges else None

    def _snap(self, points: list[Point], line: float) -> tuple[Match, list[float]] | None:
        """The line itself, map-matched. Only credible if the matched part is
        about as long as the line: where the road lies differently than in OSM
        (work on a new interchange) only a shred of it remains."""
        try:
            trace = self._request(
                "/trace_attributes",
                {
                    "shape": [{"lat": lat, "lon": lon} for lat, lon in points],
                    "costing": "auto",
                    "shape_match": "map_snap",
                    # NDW's line lies on the road; a wide radius picks up the
                    # frontage road or the other carriageway.
                    "trace_options": {"search_radius": 25},
                    "filters": {"attributes": [*TRACE_ATTRIBUTES, "shape"], "action": "include"},
                },
            )
        except urllib.error.HTTPError as error:
            if error.code >= 500:
                raise
            log.debug("no map match: %s", error)
            return None
        edges: list[tuple[int, float, int]] = []
        fractions: list[float] = []
        _append(edges, fractions, trace["edges"])
        length = sum(edge["length"] for edge in trace["edges"]) * 1000
        if not edges or not 0.8 * line - 20 <= length <= 1.25 * line + 20:
            return None
        return Match(tuple(edges), length, (trace["shape"],)), fractions


# `edge.length` is the driven part; the percent_along's (only on the first and
# last edge of a trace) say where on the edge it starts and ends.
TRACE_ATTRIBUTES = [
    "edge.id",
    "edge.length",
    "edge.way_id",
    "edge.source_percent_along",
    "edge.target_percent_along",
]


def _append(edges: list, fractions: list[float], trace: list[dict]) -> None:
    """The edges of a trace after [edges], with in [fractions] which fraction of
    each edge is driven. An edge where two legs connect appears once; its
    fractions add up."""
    for edge in trace:
        new = (int(edge["id"]), edge["length"] * 1000, int(edge.get("way_id", 0)))
        fraction = edge.get("target_percent_along", 1.0) - edge.get("source_percent_along", 0.0)
        if edges and edges[-1][0] == new[0]:
            fractions[-1] += fraction
        else:
            edges.append(new)
            fractions.append(fraction)


def _covered(match: Match, fractions: list[float]) -> Match:
    """Without the edges at the start and end of which the line covers less than
    half. A closure in the middle of a single edge keeps that edge: if nothing
    remains, the edge that is covered the most. For the route planner a few
    metres less does not matter; the closure still blocks the passage."""
    keep = [
        edge
        for i, (edge, fraction) in enumerate(zip(match.edges, fractions, strict=True))
        if 0 < i < len(fractions) - 1 or fraction >= 0.5
    ]
    if not keep:
        keep = [max(zip(match.edges, fractions, strict=True), key=lambda pair: pair[1])[0]]
    return Match(tuple(keep), match.length_m, match.shape)


def _dedupe(points: Iterable[Point]) -> list[Point]:
    """A line made of partial lines repeats every intermediate point (the end of
    one is the start of the next); Valhalla cannot handle two equal locations in
    a row."""
    out: list[Point] = []
    for point in points:
        if not out or out[-1] != point:
            out.append(point)
    return out


class MatchCache:
    """key ("<id>@<version>") -> Match or None (known to be unmatchable).

    `covered_only` is passed on to `Valhalla.match` and is stored in the file: a
    cache that was matched with the other rule is discarded."""

    def __init__(self, path: Path, tileset: int, covered_only: bool = False):
        self.path = path
        self.tileset = tileset
        self.covered_only = covered_only
        self.matches: dict[str, Match | None] = {}
        try:
            data = json.loads(path.read_text())
            if data.get("covered_only", False) != covered_only:
                log.info("%s: different match rule, cache discarded", path.name)
            elif data.get("tileset") == tileset:
                # A match from before the route shape ("v") is dropped and
                # matched again: without a shape it cannot go on the map.
                self.matches = {
                    key: Match.from_json(value) if value else None
                    for key, value in data["matches"].items()
                    if not value or "v" in value
                }
            else:
                log.info(
                    "tileset has changed (%s -> %s): cache discarded", data.get("tileset"), tileset
                )
        except FileNotFoundError:
            pass
        except (ValueError, KeyError) as error:
            log.warning("cache unreadable, starting over: %s", error)

    def save(self) -> None:
        data = {
            "tileset": self.tileset,
            "covered_only": self.covered_only,
            "matches": {
                key: match.to_json() if match else None for key, match in self.matches.items()
            },
        }
        temporary = self.path.with_suffix(".part")
        temporary.write_text(json.dumps(data, separators=(",", ":")))
        temporary.rename(self.path)

    def fill(
        self, valhalla: Valhalla, items: dict[str, tuple[Point, ...]], threads: int = 8
    ) -> int:
        """Matches what is still missing and removes what no longer exists."""
        for key in self.matches.keys() - items.keys():
            del self.matches[key]
        missing = [key for key in items if key not in self.matches]
        if not missing:
            return 0

        def attempt(key: str):
            try:
                return valhalla.match(items[key], covered_only=self.covered_only)
            except (OSError, http.client.HTTPException) as error:
                return error

        temporary = 0
        with ThreadPoolExecutor(threads) as pool:
            results = pool.map(attempt, missing)
            for number, (key, match) in enumerate(zip(missing, results, strict=True), 1):
                if isinstance(match, Exception):
                    # Not in the cache: the next cycle tries again.
                    temporary += 1
                else:
                    self.matches[key] = match
                if number % 5000 == 0:
                    log.info("matched: %d of %d", number, len(missing))
        if temporary:
            log.warning("%d of %d not matched due to a temporary error", temporary, len(missing))
        return len(missing)
