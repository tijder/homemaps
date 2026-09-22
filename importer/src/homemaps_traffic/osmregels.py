"""Maximumsnelheden die van het tijdstip afhangen, uit het OSM-bestand van de
tileset: `maxspeed:conditional` ("130 @ (19:00-06:00)" op de meeste snelwegen).
Valhalla leest die tag niet; de app past de regels onderweg zelf toe, per
OSM-way (die Valhalla wel meegeeft).

Het PBF-bestand is 1,4 GB. Een eigen lezer, zonder libosmium: alleen de blokken
waarin de tag voorkomt worden ontleed (in Nederland 5%), de rest wordt na het
uitpakken meteen overgeslagen. Zo duurt het ~20 s met ~20 MB geheugen.
"""

import re
import struct
import zlib
from collections.abc import Iterator
from typing import BinaryIO

SLEUTEL = b"maxspeed:conditional"

# Dagen als bitmasker: ma=1, di=2, ..., zo=64.
DAGEN = {"Mo": 0, "Tu": 1, "We": 2, "Th": 3, "Fr": 4, "Sa": 5, "Su": 6}
ELKE_DAG = 0b1111111

# (km/u, dagen, [(van, tot), ...]) met van/tot in minuten na middernacht; van > tot
# loopt over middernacht door.
Regel = tuple[int, int, list[tuple[int, int]]]


def _varint(data: bytes, i: int) -> tuple[int, int]:
    uit = schuif = 0
    while True:
        byte = data[i]
        i += 1
        uit |= (byte & 0x7F) << schuif
        if byte < 0x80:
            return uit, i
        schuif += 7


def _velden(data: bytes) -> Iterator[tuple[int, int | bytes]]:
    """De velden van een protobuf-bericht: (nummer, waarde)."""
    i, eind = 0, len(data)
    while i < eind:
        sleutel, i = _varint(data, i)
        soort = sleutel & 7
        if soort == 0:
            waarde, i = _varint(data, i)
        elif soort == 2:
            lengte, i = _varint(data, i)
            waarde = data[i : i + lengte]
            i += lengte
        elif soort == 1:
            waarde, i = data[i : i + 8], i + 8
        elif soort == 5:
            waarde, i = data[i : i + 4], i + 4
        else:
            raise ValueError(f"onbekend protobuf-type {soort}")
        yield sleutel >> 3, waarde


def _packed(data: bytes) -> list[int]:
    uit, i = [], 0
    while i < len(data):
        waarde, i = _varint(data, i)
        uit.append(waarde)
    return uit


def lees_pbf(stroom: BinaryIO, sleutel: bytes = SLEUTEL) -> dict[int, str]:
    """way-id -> waarde van [sleutel], voor ways met een `highway`-tag."""
    uit: dict[int, str] = {}
    while kop := stroom.read(4):
        (lengte,) = struct.unpack(">I", kop)
        header = dict(_velden(stroom.read(lengte)))
        blob = dict(_velden(stroom.read(header[3])))
        if header.get(1) != b"OSMData":
            continue
        if 3 in blob:
            data = zlib.decompress(blob[3])
        elif 1 in blob:
            data = blob[1]
        else:
            raise ValueError("alleen zlib of ongecomprimeerd wordt ondersteund")
        # Het snelle filter: staat de sleutel niet in het blok, dan geen enkele
        # way erin met die tag.
        if sleutel not in data:
            continue
        teksten: list[bytes] = []
        groepen: list[bytes] = []
        for nummer, waarde in _velden(data):
            if nummer == 1:
                teksten = [tekst for veld, tekst in _velden(waarde) if veld == 1]
            elif nummer == 2:
                groepen.append(waarde)
        if sleutel not in teksten or b"highway" not in teksten:
            continue
        index, weg = teksten.index(sleutel), teksten.index(b"highway")
        for groep in groepen:
            for nummer, way in _velden(groep):
                if nummer != 3:  # alleen ways
                    continue
                velden = dict(_velden(way))
                sleutels = _packed(velden.get(2, b""))
                if index in sleutels and weg in sleutels:
                    waarden = _packed(velden.get(3, b""))
                    uit[velden[1]] = teksten[waarden[sleutels.index(index)]].decode()
    return uit


def _tot_haakjes(tekst: str, teken: str) -> list[str]:
    """Splitst op [teken], maar niet binnen haakjes."""
    delen, diepte, begin = [], 0, 0
    for i, t in enumerate(tekst):
        diepte += t == "("
        diepte -= t == ")"
        if t == teken and diepte == 0:
            delen.append(tekst[begin:i])
            begin = i + 1
    delen.append(tekst[begin:])
    return [deel.strip() for deel in delen if deel.strip()]


def _minuten(tijd: str) -> int | None:
    uur, _, minuut = tijd.partition(":")
    if not (uur.isdigit() and minuut.isdigit()):
        return None
    waarde = int(uur) * 60 + int(minuut)
    return waarde if 0 <= waarde <= 24 * 60 else None


def _dagen(tekst: str) -> int | None:
    masker = 0
    for deel in tekst.split(","):
        van, _, tot = deel.partition("-")
        if van not in DAGEN or (tot and tot not in DAGEN):
            return None
        a, b = DAGEN[van], DAGEN[tot or van]
        for dag in range(7):
            if (a <= b and a <= dag <= b) or (a > b and (dag >= a or dag <= b)):
                masker |= 1 << dag
    return masker


def _voorwaarde(tekst: str) -> list[tuple[int, list[tuple[int, int]]]] | None:
    """Een tijdvoorwaarde ("Mo-Fr 06:00-10:00,15:00-19:00; Sa 08:00-12:00") als
    [(dagen, vensters)]. None als er iets in staat dat hier niet te weten is:
    `wet`, `sunrise`, vrije tekst, een datum."""
    tekst = tekst.strip()
    if tekst.startswith("(") and tekst.endswith(")"):
        tekst = tekst[1:-1]
    uit = []
    for regel in _tot_haakjes(tekst, ";"):
        if regel == "PH off":  # feestdagen niet: dan geldt hij gewoon wel
            continue
        stukken = regel.split()
        dagen, tijden = ELKE_DAG, None
        if len(stukken) == 2:
            dagen, tijden = _dagen(stukken[0]), stukken[1]
        elif len(stukken) == 1 and re.match(r"^\d", stukken[0]):
            tijden = stukken[0]
        elif len(stukken) == 1:
            dagen, tijden = _dagen(stukken[0]), "00:00-24:00"
        if dagen is None or tijden is None:
            return None
        vensters = []
        for venster in tijden.split(","):
            van, _, tot = venster.partition("-")
            a, b = _minuten(van), _minuten(tot)
            if a is None or b is None:
                return None
            vensters.append((a, b))
        uit.append((dagen, vensters))
    return uit or None


def regels(waarde: str) -> list[Regel]:
    """`maxspeed:conditional` als regels die de app kan toepassen. Wat niet van
    het tijdstip afhangt (`70 @ wet`) of niet te lezen is, valt weg."""
    uit: list[Regel] = []
    for deel in _tot_haakjes(waarde, ";"):
        snelheid, apestaart, voorwaarde = deel.partition("@")
        snelheid = snelheid.strip()
        if not apestaart or not snelheid.isdigit():
            continue
        tijden = _voorwaarde(voorwaarde)
        if tijden is None:
            continue
        uit.extend((int(snelheid), dagen, vensters) for dagen, vensters in tijden)
    return uit


def snelheid_tijden(stroom: BinaryIO) -> dict[str, list[Regel]]:
    """way-id (als tekst, voor JSON) -> regels; alleen ways met iets bruikbaars."""
    uit = {}
    for way, waarde in lees_pbf(stroom).items():
        if gevonden := regels(waarde):
            uit[str(way)] = gevonden
    return uit
