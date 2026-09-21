"""Van een NDW-lijn naar Valhalla's edge-id's, met een cache op schijf.

Bijna alle reistijdsegmenten zijn alleen een begin- en eindpunt (mediaan 500 m).
Daarom wordt er niet ge-map-matcht maar gerouteerd: de route van begin naar eind
ís het segment, en de rijrichting volgt vanzelf uit de volgorde van de punten.
De edges van die route komen uit trace_attributes (edge_walk op de routevorm).

Edge-id's veranderen bij elke tile-build. De cache hoort daarom bij één tileset
(`tileset_last_modified` uit /status) en wordt anders weggegooid.
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

from .datex3 import Punt

log = logging.getLogger(__name__)

MAX_LOCATIES = 20


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
    """Eén blijvende verbinding per draad. Met een nieuwe verbinding per verzoek
    raken bij het matchen van 67.000 segmenten (2 verzoeken elk, ~600/s) de
    tijdelijke poorten op -- elke gesloten verbinding blijft 60 s in TIME_WAIT --
    en dan mislukt een derde van de verzoeken in golven."""

    def __init__(self, url: str, timeout: float = 30):
        delen = urllib.parse.urlsplit(url)
        self.host, self.poort = delen.hostname, delen.port or 80
        self.basis = delen.path.rstrip("/")
        self.timeout = timeout
        self._lokaal = threading.local()

    def _vraag(self, pad: str, body: dict | None = None) -> dict:
        data = json.dumps(body).encode() if body is not None else None
        for poging in (1, 2):
            verbinding = getattr(self._lokaal, "verbinding", None)
            if verbinding is None:
                verbinding = http.client.HTTPConnection(self.host, self.poort, timeout=self.timeout)
                self._lokaal.verbinding = verbinding
            try:
                verbinding.request(
                    "POST" if data is not None else "GET",
                    self.basis + pad,
                    data,
                    {"Content-Type": "application/json"},
                )
                antwoord = verbinding.getresponse()
                inhoud = antwoord.read()
            except (OSError, http.client.HTTPException):
                # De server mag een stille verbinding sluiten; één keer opnieuw
                # met een verse is dan geen fout.
                verbinding.close()
                self._lokaal.verbinding = None
                if poging == 2:
                    raise
                continue
            if antwoord.status >= 400:
                raise urllib.error.HTTPError(pad, antwoord.status, inhoud[:200].decode(), {}, None)
            return json.loads(inhoud)
        raise AssertionError("onbereikbaar")

    def tileset(self) -> int:
        return int(self._vraag("/status").get("tileset_last_modified", 0))

    def match(self, punten: Iterable[Punt], max_omweg: float = 1.6) -> Match | None:
        """None als er geen geloofwaardige route is; dat is een definitief antwoord
        en mag in de cache. Een tijdelijke fout (verbinding weg, time-out) komt er
        als OSError uit, zodat de aanroeper het later opnieuw probeert.

        `max_omweg`: een route die veel langer is dan de lijn zelf is een andere
        weg (het punt viel op de verkeerde rijbaan of een parallelweg), en dan is
        geen match beter dan een foute.
        """
        punten = _ontdubbel(punten)
        if len(punten) < 2:
            return None
        lijn = sum(hemelsbreed(a, b) for a, b in zip(punten, punten[1:], strict=False))
        edges: list[tuple[int, float, int]] = []
        lengte = 0.0
        try:
            # Blokken die elkaar één punt overlappen: Valhalla neemt hooguit 20
            # locaties per verzoek. Tussenpunten zijn `break`, niet `through`: met
            # `directions_type: none` struikelt Valhalla over through-locaties
            # ("leg_shape_index not set for intermediate").
            for begin in range(0, len(punten) - 1, MAX_LOCATIES - 1):
                blok = punten[begin : begin + MAX_LOCATIES]
                route = self._vraag(
                    "/route",
                    {
                        "locations": [{"lat": lat, "lon": lon} for lat, lon in blok],
                        "costing": "auto",
                        "units": "kilometers",
                        # De meting hoort bij de weg zoals hij ligt, niet bij de
                        # route die vandaag toevallig het snelst is.
                        "costing_options": {
                            "auto": {"shortest": True, "speed_types": ["freeflow", "constrained"]}
                        },
                        "directions_type": "none",
                    },
                )
                lengte += route["trip"]["summary"]["length"] * 1000
                if lengte > lijn * max_omweg + 150:
                    return None
                for leg in route["trip"]["legs"]:
                    spoor = self._vraag(
                        "/trace_attributes",
                        {
                            "encoded_polyline": leg["shape"],
                            "costing": "auto",
                            "shape_match": "walk_or_snap",
                            "filters": {
                                "attributes": ["edge.id", "edge.length", "edge.way_id"],
                                "action": "include",
                            },
                        },
                    )
                    for edge in spoor["edges"]:
                        nieuw = (
                            int(edge["id"]),
                            edge["length"] * 1000,
                            int(edge.get("way_id", 0)),
                        )
                        if not edges or edges[-1][0] != nieuw[0]:
                            edges.append(nieuw)
        except urllib.error.HTTPError as fout:
            # Een 4xx is "geen route": het punt ligt buiten de tileset of op een
            # weg waar een auto niet komt. Een 5xx is Valhalla's probleem.
            if fout.code >= 500:
                raise
            log.debug("geen match: %s", fout)
            return None
        except (KeyError, ValueError) as fout:
            log.debug("onverwacht antwoord: %s", fout)
            return None
        return Match(tuple(edges), lengte) if edges else None


def _ontdubbel(punten: Iterable[Punt]) -> list[Punt]:
    """Een lijn uit deellijnen herhaalt elk tussenpunt (eind van de ene is begin
    van de volgende); twee gelijke locaties achter elkaar kan Valhalla niet aan."""
    uit: list[Punt] = []
    for punt in punten:
        if not uit or uit[-1] != punt:
            uit.append(punt)
    return uit


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

        def probeer(sleutel: str):
            try:
                return valhalla.match(items[sleutel])
            except (OSError, http.client.HTTPException) as fout:
                return fout

        tijdelijk = 0
        with ThreadPoolExecutor(draden) as pool:
            resultaten = pool.map(probeer, ontbrekend)
            for nummer, (sleutel, match) in enumerate(zip(ontbrekend, resultaten, strict=True), 1):
                if isinstance(match, Exception):
                    # Niet in de cache: de volgende ronde probeert het opnieuw.
                    tijdelijk += 1
                else:
                    self.matches[sleutel] = match
                if nummer % 5000 == 0:
                    log.info("gematcht: %d van %d", nummer, len(ontbrekend))
        if tijdelijk:
            log.warning(
                "%d van %d niet gematcht door een tijdelijke fout", tijdelijk, len(ontbrekend)
            )
        return len(ontbrekend)
