"""Van een NDW-lijn naar Valhalla's edge-id's, met een cache op schijf.

Bijna alle reistijdsegmenten zijn alleen een begin- en eindpunt (mediaan 500 m).
Daarom wordt er niet ge-map-matcht maar gerouteerd: de route van begin naar eind
ís het segment, en de rijrichting volgt vanzelf uit de volgorde van de punten.
De edges van die route komen uit trace_attributes (edge_walk op de routevorm).

Edge-id's veranderen bij elke tile-build. De cache hoort daarom bij één tileset
(`tileset_last_modified` uit /status) en wordt anders weggegooid.
"""

import json
import logging
import math
import urllib.error
import urllib.request
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from .datex3 import Punt

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class Match:
    edges: tuple[tuple[int, float, int], ...]  # (graphid, lengte in m, way_id)
    lengte_m: float

    def naar_json(self):
        return {"e": [list(edge) for edge in self.edges], "l": round(self.lengte_m, 1)}

    @classmethod
    def uit_json(cls, data) -> "Match":
        return cls(tuple((e[0], e[1], e[2]) for e in data["e"]), data["l"])


def hemelsbreed(a: Punt, b: Punt) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * 6371000 * math.asin(math.sqrt(h))


class Valhalla:
    def __init__(self, url: str, timeout: float = 30):
        self.url = url.rstrip("/")
        self.timeout = timeout

    def _vraag(self, pad: str, body: dict | None = None) -> dict:
        data = json.dumps(body).encode() if body is not None else None
        verzoek = urllib.request.Request(self.url + pad, data, {"Content-Type": "application/json"})
        with urllib.request.urlopen(verzoek, timeout=self.timeout) as antwoord:
            return json.load(antwoord)

    def tileset(self) -> int:
        return int(self._vraag("/status").get("tileset_last_modified", 0))

    def match(self, punten: Iterable[Punt], max_omweg: float = 1.6) -> Match | None:
        """None als er geen geloofwaardige route is.

        `max_omweg`: een route die veel langer is dan de lijn zelf is een andere
        weg (het punt viel op de verkeerde rijbaan of een parallelweg), en dan is
        geen match beter dan een foute.
        """
        punten = list(punten)
        lijn = sum(hemelsbreed(a, b) for a, b in zip(punten, punten[1:], strict=False))
        locaties = [{"lat": lat, "lon": lon, "type": "through"} for lat, lon in punten]
        locaties[0]["type"] = locaties[-1]["type"] = "break"
        try:
            route = self._vraag(
                "/route",
                {
                    "locations": locaties,
                    "costing": "auto",
                    "units": "kilometers",
                    # De meting hoort bij de weg zoals hij ligt, niet bij de route
                    # die vandaag toevallig het snelst is.
                    "costing_options": {
                        "auto": {"shortest": True, "speed_types": ["freeflow", "constrained"]}
                    },
                    "directions_type": "none",
                },
            )
            lengte = route["trip"]["summary"]["length"] * 1000
            if lengte > lijn * max_omweg + 150:
                return None
            edges: list[tuple[int, float, int]] = []
            for leg in route["trip"]["legs"]:
                spoor = self._vraag(
                    "/trace_attributes",
                    {
                        "encoded_polyline": leg["shape"],
                        "costing": "auto",
                        "shape_match": "edge_walk",
                        "filters": {
                            "attributes": ["edge.id", "edge.length", "edge.way_id"],
                            "action": "include",
                        },
                    },
                )
                for edge in spoor["edges"]:
                    nieuw = (int(edge["id"]), edge["length"] * 1000, int(edge.get("way_id", 0)))
                    if not edges or edges[-1][0] != nieuw[0]:
                        edges.append(nieuw)
        except (urllib.error.URLError, KeyError, ValueError, TimeoutError) as fout:
            # Een 400 is hier gewoon "geen route": het punt ligt buiten de tileset
            # of op een weg waar een auto niet mag komen.
            log.debug("geen match: %s", fout)
            return None
        return Match(tuple(edges), lengte) if edges else None


class MatchCache:
    """sleutel ("<id>@<versie>") -> Match of None (bekend onmatchbaar)."""

    def __init__(self, pad: Path, tileset: int):
        self.pad = pad
        self.tileset = tileset
        self.matches: dict[str, Match | None] = {}
        try:
            data = json.loads(pad.read_text())
            if data.get("tileset") == tileset:
                self.matches = {
                    sleutel: Match.uit_json(waarde) if waarde else None
                    for sleutel, waarde in data["matches"].items()
                }
            else:
                log.info(
                    "tileset is gewijzigd (%s -> %s): cache vervalt", data.get("tileset"), tileset
                )
        except FileNotFoundError:
            pass
        except (ValueError, KeyError) as fout:
            log.warning("cache onleesbaar, begin opnieuw: %s", fout)

    def bewaar(self) -> None:
        data = {
            "tileset": self.tileset,
            "matches": {
                sleutel: match.naar_json() if match else None
                for sleutel, match in self.matches.items()
            },
        }
        tijdelijk = self.pad.with_suffix(".deel")
        tijdelijk.write_text(json.dumps(data, separators=(",", ":")))
        tijdelijk.rename(self.pad)

    def vul_aan(
        self, valhalla: Valhalla, items: dict[str, tuple[Punt, ...]], draden: int = 8
    ) -> int:
        """Matcht wat nog ontbreekt en ruimt op wat niet meer bestaat."""
        for sleutel in self.matches.keys() - items.keys():
            del self.matches[sleutel]
        ontbrekend = [sleutel for sleutel in items if sleutel not in self.matches]
        if not ontbrekend:
            return 0
        with ThreadPoolExecutor(draden) as pool:
            resultaten = pool.map(lambda sleutel: valhalla.match(items[sleutel]), ontbrekend)
            for nummer, (sleutel, match) in enumerate(zip(ontbrekend, resultaten, strict=True), 1):
                self.matches[sleutel] = match
                if nummer % 5000 == 0:
                    log.info("gematcht: %d van %d", nummer, len(ontbrekend))
        return len(ontbrekend)
