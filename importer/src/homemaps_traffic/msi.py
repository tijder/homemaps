"""Matrixborden (MSI) boven de snelweg: wat ze nu tonen, per portaal.

Twee NDW-bestanden: `Matrixsignaalinformatie.xml.gz` (elke minuut: per bord wat
erop staat, en weg/rijbaan/strook/hectometer) en `ndw_msi_shapefiles_latest.zip`
(per bord een punt en de rijrichting). Borden met dezelfde weg, rijbaan en km
vormen een portaal. Strook 1 is de linker: de pijl "naar rechts invoegen" staat
in de feed op de laagste strooknummers, "naar links" op de hoogste.

Een snelheid is alleen verplicht in een rode ring; zonder is het een advies.
"""

import struct
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from typing import BinaryIO
from xml.etree.ElementTree import Element

from .datex3 import _eerste, _naam, _records, _tekst


@dataclass(frozen=True)
class Bordplek:
    lat: float
    lon: float
    koers: float
    weg: str
    rijbaan: str
    km: str
    strook: int


@dataclass(frozen=True)
class Portaal:
    weg: str
    rijbaan: str
    km: str
    lat: float
    lon: float
    koers: float
    stroken: tuple[str, ...]  # van links naar rechts; zie `code`


def _dbf(data: bytes) -> list[dict[str, str]]:
    """Een dBase-tabel (de attributen van een shapefile)."""
    aantal, kop, lengte = struct.unpack("<IHH", data[4:12])
    velden, i = [], 32
    while data[i] != 0x0D:
        velden.append((data[i : i + 11].split(b"\0")[0].decode(), data[i + 16]))
        i += 32
    uit = []
    for r in range(aantal):
        record = data[kop + r * lengte : kop + (r + 1) * lengte]
        if record[:1] == b"*":  # gewist
            uit.append({})
            continue
        waarden, positie = {}, 1
        for naam, breedte in velden:
            waarden[naam] = record[positie : positie + breedte].decode("latin-1").strip()
            positie += breedte
        uit.append(waarden)
    return uit


def _punten(data: bytes) -> list[tuple[float, float] | None]:
    """De punten uit een .shp, als (lon, lat); None voor een lege vorm."""
    uit, i = [], 100
    while i + 8 <= len(data):
        _, lengte = struct.unpack(">II", data[i : i + 8])
        (soort,) = struct.unpack("<i", data[i + 8 : i + 12])
        uit.append(struct.unpack("<dd", data[i + 12 : i + 28]) if soort == 1 else None)
        i += 8 + lengte * 2
    return uit


def lees_locaties(zip_bestand: BinaryIO) -> dict[str, Bordplek]:
    """uuid -> waar het bord hangt, uit NDW's shapefile-zip."""
    with zipfile.ZipFile(zip_bestand) as archief:
        namen = archief.namelist()
        shp = next(n for n in namen if n.lower().endswith(".shp"))
        dbf = next(n for n in namen if n.lower().endswith(".dbf"))
        punten, records = _punten(archief.read(shp)), _dbf(archief.read(dbf))
    uit = {}
    for punt, record in zip(punten, records, strict=False):
        if punt is None or not record.get("uuid"):
            continue
        try:
            uit[record["uuid"]] = Bordplek(
                punt[1],
                punt[0],
                float(record["bearing"]),
                record["road"],
                record["carriagew0"],
                record["km"],
                int(float(record["lane"])),
            )
        except (KeyError, ValueError):
            continue
    return uit


def code(display: Element) -> str:
    """Wat een bord toont, kort: "70" (advies), "70r" (verplicht, rode ring),
    "x" (rijstrook dicht), "<" / ">" (invoegen naar links/rechts), "open"
    (groene pijl), "einde" (einde beperkingen), "" (leeg)."""
    for kind in display:
        soort = _naam(kind)
        if soort == "speedlimit" and (kind.text or "").strip().isdigit():
            return kind.text.strip() + ("r" if kind.attrib.get("red_ring") == "true" else "")
        if soort == "lane_closed":
            return "x"
        if soort == "lane_closed_ahead":
            if _eerste(kind, "merge_left") is not None:
                return "<"
            if _eerste(kind, "merge_right") is not None:
                return ">"
            return "x"
        if soort == "lane_open":
            return "open"
        if soort == "restriction_end":
            return "einde"
    return ""


def lees_beelden(stroom: BinaryIO) -> dict[str, str]:
    """uuid -> wat het bord nu toont (zie `code`)."""
    uit = {}
    for event in _records(stroom, "event"):
        display, bord = _eerste(event, "display"), _eerste(event, "sign_id")
        uuid = _tekst(bord, "uuid") if bord is not None else None
        if display is not None and uuid:
            uit[uuid] = code(display)
    return uit


def portalen(
    locaties: dict[str, Bordplek], beelden: dict[str, str], rand_km: float = 3.0
) -> list[Portaal]:
    """De portalen waar iets op staat, plus de lege binnen [rand_km] daarvan op
    dezelfde weg en rijbaan: een snelheid boven de weg geldt tot het volgende
    portaal, en is dat leeg, dan houdt hij daar op. De rest (de meeste) blijft
    weg."""
    per_portaal: dict[tuple[str, str, str], list[tuple[Bordplek, str]]] = defaultdict(list)
    for uuid, beeld in beelden.items():
        plek = locaties.get(uuid)
        if plek:
            per_portaal[(plek.weg, plek.rijbaan, plek.km)].append((plek, beeld))
    bezet: dict[tuple[str, str], list[float]] = defaultdict(list)
    for (weg, rijbaan, km), borden in per_portaal.items():
        if any(beeld for _, beeld in borden):
            bezet[(weg, rijbaan)].append(_km(km))
    uit = []
    for (weg, rijbaan, km), borden in per_portaal.items():
        if not any(beeld for _, beeld in borden) and not any(
            abs(_km(km) - ander) <= rand_km for ander in bezet[(weg, rijbaan)]
        ):
            continue
        borden.sort(key=lambda bord: bord[0].strook)
        eerste = borden[0][0]
        uit.append(
            Portaal(
                weg,
                rijbaan,
                km,
                eerste.lat,
                eerste.lon,
                eerste.koers,
                tuple(beeld for _, beeld in borden),
            )
        )
    return uit


def _km(tekst: str) -> float:
    try:
        return float(tekst)
    except ValueError:
        return float("nan")
