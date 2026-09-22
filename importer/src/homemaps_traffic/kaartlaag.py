"""De verkeerslaag van de app: afsluitingen, werk op de weg en trage stukken, als
één GeoJSON dat elke ronde opnieuw wordt gemaakt.

De app vertaalt de codes zelf (soort, rijbaan, oorzaak): de feed heeft vrijwel
geen vrije tekst, en zo blijft de taal bij de app.
"""

import gzip
import json
from collections.abc import Iterable
from datetime import UTC

from .datex3 import GeplandeAfsluiting, Maatregel, Melding, Punt, Reistijd
from .matcher import Match

# Een stuk is traag onder dit deel van zijn normale snelheid, en file daaronder.
TRAAG = 0.6
FILE = 0.35
# Minder vertraging dan dit is een stoplicht of een bocht, geen file.
MIN_VERTRAGING_S = 20


def decodeer(polyline: str, precisie: float = 1e6) -> list[Punt]:
    """Valhalla's polyline (Google's formaat, zes decimalen) naar (lat, lon)."""
    punten: list[Punt] = []
    index = lat = lon = 0
    while index < len(polyline):
        delta = []
        for _ in range(2):
            verschuiving = waarde = 0
            while True:
                byte = ord(polyline[index]) - 63
                index += 1
                waarde |= (byte & 0x1F) << verschuiving
                verschuiving += 5
                if byte < 0x20:
                    break
            delta.append(~(waarde >> 1) if waarde & 1 else waarde >> 1)
        lat += delta[0]
        lon += delta[1]
        punten.append((lat / precisie, lon / precisie))
    return punten


def _geometrie(lijnen: list[list[Punt]]) -> dict:
    # Vijf decimalen is ruim een meter: genoeg voor een lijn op de kaart.
    coordinaten = [[[round(lon, 5), round(lat, 5)] for lat, lon in lijn] for lijn in lijnen]
    if len(coordinaten) == 1:
        return {"type": "LineString", "coordinates": coordinaten[0]}
    return {"type": "MultiLineString", "coordinates": coordinaten}


def maatregelen(items: Iterable[Maatregel]) -> list[dict]:
    """Afsluitingen ("dicht") en rijstrookafsluitingen ("werk"). Wat alleen voor
    vrachtverkeer geldt, en de zeldzame overige soorten, blijven weg."""
    uit = []
    for maatregel in items:
        if maatregel.sluit_af:
            soort = "dicht"
        elif maatregel.soort == "laneClosures" and not maatregel.alleen_vracht:
            soort = "werk"
        else:
            continue
        eigenschappen = {
            "soort": soort,
            "hele_weg": maatregel.soort == "roadClosed",
            "rijbaan": maatregel.rijbaan,
            "oorzaak": maatregel.oorzaak,
            "tot": maatregel.eind.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
            if maatregel.eind
            else None,
            "stroken_open": maatregel.stroken_open,
        }
        uit.append(
            {
                "type": "Feature",
                "properties": {k: v for k, v in eigenschappen.items() if v is not None},
                "geometry": _geometrie([list(lijn) for lijn in maatregel.lijnen]),
            }
        )
    return uit


def trage_stukken(reistijden: Iterable[Reistijd], matches: dict[str, Match | None]) -> list[dict]:
    """Meetsegmenten die duidelijk langzamer gaan dan normaal, over de weg zoals
    Valhalla hem kent. Zonder normale reistijd valt er niets te vergelijken."""
    uit = []
    for reistijd in reistijden:
        match = matches.get(reistijd.sleutel)
        if not match or not match.vorm or not reistijd.normaal_seconden:
            continue
        deel = reistijd.normaal_seconden / reistijd.seconden
        vertraging = reistijd.seconden - reistijd.normaal_seconden
        if deel >= TRAAG or vertraging < MIN_VERTRAGING_S:
            continue
        uit.append(
            {
                "type": "Feature",
                "properties": {
                    "soort": "file" if deel < FILE else "traag",
                    "vertraging_s": round(vertraging),
                    "kmu": round(match.lengte_m / reistijd.seconden * 3.6),
                },
                "geometry": _geometrie([decodeer(leg) for leg in match.vorm]),
            }
        )
    return uit


def meldingen(items: Iterable[Melding]) -> list[dict]:
    """Ongevallen, pechgevallen en voorwerpen op de weg, als punten."""
    uit = []
    for melding in items:
        eigenschappen = {
            "soort": melding.soort,
            "koers": melding.koers,
            "sinds": melding.sinds.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
            if melding.sinds
            else None,
        }
        lat, lon = melding.punt
        uit.append(
            {
                "type": "Feature",
                "properties": {k: v for k, v in eigenschappen.items() if v is not None},
                "geometry": {"type": "Point", "coordinates": [round(lon, 5), round(lat, 5)]},
            }
        )
    return uit


def _iso(tijd):
    return tijd.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ") if tijd else None


def geplande_afsluitingen(items: Iterable[GeplandeAfsluiting]) -> list[dict]:
    """Voor "later vertrekken": afsluitingen met hun vensters, zodat de app kan
    zien of er op je vertrektijd een op de route ligt."""
    uit = []
    for afsluiting in items:
        eigenschappen = {
            "soort": "gepland",
            "hele_weg": afsluiting.hele_weg,
            "rijbaan": afsluiting.rijbaan,
            "vensters": [[_iso(begin), _iso(eind)] for begin, eind in afsluiting.vensters],
        }
        uit.append(
            {
                "type": "Feature",
                "properties": {k: v for k, v in eigenschappen.items() if v is not None},
                "geometry": _geometrie([list(lijn) for lijn in afsluiting.lijnen]),
            }
        )
    return uit


def geojson(features: list[dict]) -> tuple[bytes, bytes]:
    """De laag, gewoon en gzip: nginx pakt een geproxied antwoord zelf niet in."""
    # Een oplopend id per feature: MapLibre meldt een tik met het id.
    for nummer, feature in enumerate(features):
        feature["id"] = nummer
    ruw = json.dumps(
        {"type": "FeatureCollection", "features": features}, separators=(",", ":")
    ).encode()
    return ruw, gzip.compress(ruw, 6)
