"""The app's traffic layer: closures, road works, slow segments and temporary
maximum speeds, as one GeoJSON that is rebuilt every cycle.

The app translates the codes itself (kind, carriageway, cause): the feed has
hardly any free text, and this way the language stays with the app.
"""

import gzip
import json
from collections.abc import Iterable
from datetime import UTC, datetime

from .datex3 import (
    Bridge,
    Incident,
    Measure,
    PlannedClosure,
    Point,
    TemporarySpeedLimit,
    TravelTime,
)
from .matcher import Match
from .msi import Gantry

# A segment is slow below this fraction of its normal speed, and a jam below that.
SLOW = 0.6
JAM = 0.35
# Less delay than this is a traffic light or a bend, not a jam.
MIN_DELAY_S = 20


def decode(polyline: str, precision: float = 1e6) -> list[Point]:
    """Valhalla's polyline (Google's format, six decimals) to (lat, lon)."""
    points: list[Point] = []
    index = lat = lon = 0
    while index < len(polyline):
        delta = []
        for _ in range(2):
            shift = value = 0
            while True:
                byte = ord(polyline[index]) - 63
                index += 1
                value |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            delta.append(~(value >> 1) if value & 1 else value >> 1)
        lat += delta[0]
        lon += delta[1]
        points.append((lat / precision, lon / precision))
    return points


def _geometry(lines: list[list[Point]]) -> dict:
    # Five decimals is just over a metre: enough for a line on the map.
    coordinates = [[[round(lon, 5), round(lat, 5)] for lat, lon in line] for line in lines]
    if len(coordinates) == 1:
        return {"type": "LineString", "coordinates": coordinates[0]}
    return {"type": "MultiLineString", "coordinates": coordinates}


def measures(items: Iterable[Measure]) -> list[dict]:
    """Closures ("closed") and lane closures ("roadworks"). Whatever applies to
    trucks only, and the rare other types, are left out."""
    out = []
    for measure in items:
        if measure.closes:
            kind = "closed"
        elif measure.management_type == "laneClosures" and not measure.trucks_only:
            kind = "roadworks"
        else:
            continue
        properties = {
            "kind": kind,
            "whole_road": measure.management_type == "roadClosed",
            "carriageway": measure.carriageway,
            "cause": measure.cause,
            "until": measure.end.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
            if measure.end
            else None,
            "lanes_open": measure.lanes_open,
        }
        out.append(
            {
                "type": "Feature",
                "properties": {k: v for k, v in properties.items() if v is not None},
                "geometry": _geometry([list(line) for line in measure.lines]),
            }
        )
    return out


def slow_segments(
    travel_times: Iterable[TravelTime], matches: dict[str, Match | None]
) -> list[dict]:
    """Measurement segments that are clearly slower than normal, over the road as
    Valhalla knows it. Without a normal travel time there is nothing to compare."""
    out = []
    for travel_time in travel_times:
        match = matches.get(travel_time.key)
        if not match or not match.shape or not travel_time.normal_seconds:
            continue
        fraction = travel_time.normal_seconds / travel_time.seconds
        delay = travel_time.seconds - travel_time.normal_seconds
        if fraction >= SLOW or delay < MIN_DELAY_S:
            continue
        out.append(
            {
                "type": "Feature",
                "properties": {
                    "kind": "jam" if fraction < JAM else "slow",
                    "delay_s": round(delay),
                    "kph": round(match.length_m / travel_time.seconds * 3.6),
                },
                "geometry": _geometry([decode(leg) for leg in match.shape]),
            }
        )
    return out


def incidents(items: Iterable[Incident]) -> list[dict]:
    """Accidents, breakdowns and objects on the road, as points."""
    out = []
    for incident in items:
        properties = {
            "kind": incident.kind,
            "bearing": incident.bearing,
            "since": incident.since.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
            if incident.since
            else None,
        }
        lat, lon = incident.point
        out.append(
            {
                "type": "Feature",
                "properties": {k: v for k, v in properties.items() if v is not None},
                "geometry": {"type": "Point", "coordinates": [round(lon, 5), round(lat, 5)]},
            }
        )
    return out


def speed_limits(items: Iterable[tuple[TemporarySpeedLimit, Match]], now: datetime) -> list[dict]:
    """Temporary maximum speeds over the road as Valhalla knows it, in the
    direction of travel: the app lays them onto the route while driving. Not on
    the map."""
    out = []
    for limit, match in items:
        if not match.shape:
            continue
        # The end of the window we are in right now.
        until = next(
            (end for start, end in limit.windows if start <= now and (end is None or now <= end)),
            None,
        )
        properties = {
            "kind": "speed_limit",
            "kph": limit.kph,
            "cause": limit.cause,
            "until": _iso(until),
        }
        out.append(
            {
                "type": "Feature",
                "properties": {k: v for k, v in properties.items() if v is not None},
                "geometry": _geometry([decode(leg) for leg in match.shape]),
            }
        )
    return out


def _point(lat: float, lon: float) -> dict:
    return {"type": "Point", "coordinates": [round(lon, 5), round(lat, 5)]}


def msi(gantries: Iterable[Gantry]) -> list[dict]:
    """MSI signs per gantry, with the direction of travel and per lane (from left
    to right) what they show. For while driving, not on the map."""
    return [
        {
            "type": "Feature",
            "properties": {
                "kind": "msi",
                "bearing": round(gantry.bearing),
                "lanes": list(gantry.lanes),
            },
            "geometry": _point(gantry.lat, gantry.lon),
        }
        for gantry in gantries
    ]


def bridges(items: Iterable[Bridge]) -> list[dict]:
    """Bridges that are open right now. For the warning while driving."""
    return [
        {"type": "Feature", "properties": {"kind": "bridge"}, "geometry": _point(*bridge.point)}
        for bridge in items
    ]


def _iso(time):
    return time.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ") if time else None


def planned_closures(items: Iterable[PlannedClosure]) -> list[dict]:
    """For "leave later": closures with their windows, so the app can see whether
    one is on the route at your departure time."""
    out = []
    for closure in items:
        properties = {
            "kind": "planned",
            "whole_road": closure.whole_road,
            "carriageway": closure.carriageway,
            "windows": [[_iso(start), _iso(end)] for start, end in closure.windows],
        }
        out.append(
            {
                "type": "Feature",
                "properties": {k: v for k, v in properties.items() if v is not None},
                "geometry": _geometry([list(line) for line in closure.lines]),
            }
        )
    return out


def geojson(features: list[dict]) -> tuple[bytes, bytes]:
    """The layer, plain and gzip: nginx does not compress a proxied response itself."""
    # An ascending id per feature: MapLibre reports a tap with the id.
    for number, feature in enumerate(features):
        feature["id"] = number
    return compress({"type": "FeatureCollection", "features": features})


def compress(content) -> tuple[bytes, bytes]:
    """JSON, plain and gzip."""
    raw = json.dumps(content, separators=(",", ":")).encode()
    return raw, gzip.compress(raw, 6)
