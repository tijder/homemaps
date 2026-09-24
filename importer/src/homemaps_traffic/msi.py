"""MSI signs (matrix signs) above the motorway: what they show right now, per gantry.

Two NDW files: `Matrixsignaalinformatie.xml.gz` (every minute: per sign what it
shows, and road/carriageway/lane/hectometre) and `ndw_msi_shapefiles_latest.zip`
(per sign a point and the direction of travel). Signs with the same road,
carriageway and km form a gantry. Lane 1 is the leftmost: the "merge right"
arrow is on the lowest lane numbers in the feed, "merge left" on the highest.

A speed is only mandatory in a red ring; without one it is advisory.
"""

import struct
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from typing import BinaryIO
from xml.etree.ElementTree import Element

from .datex3 import _first, _name, _records, _text


@dataclass(frozen=True)
class SignLocation:
    lat: float
    lon: float
    bearing: float
    road: str
    carriageway: str
    km: str
    lane: int


@dataclass(frozen=True)
class Gantry:
    road: str
    carriageway: str
    km: str
    lat: float
    lon: float
    bearing: float
    lanes: tuple[str, ...]  # from left to right; see `code`


def _dbf(data: bytes) -> list[dict[str, str]]:
    """A dBase table (the attributes of a shapefile)."""
    count, header_size, record_size = struct.unpack("<IHH", data[4:12])
    fields, i = [], 32
    while data[i] != 0x0D:
        fields.append((data[i : i + 11].split(b"\0")[0].decode(), data[i + 16]))
        i += 32
    out = []
    for r in range(count):
        record = data[header_size + r * record_size : header_size + (r + 1) * record_size]
        if record[:1] == b"*":  # deleted
            out.append({})
            continue
        values, position = {}, 1
        for name, width in fields:
            values[name] = record[position : position + width].decode("latin-1").strip()
            position += width
        out.append(values)
    return out


def _points(data: bytes) -> list[tuple[float, float] | None]:
    """The points from a .shp, as (lon, lat); None for an empty shape."""
    out, i = [], 100
    while i + 8 <= len(data):
        _, length = struct.unpack(">II", data[i : i + 8])
        (shape_type,) = struct.unpack("<i", data[i + 8 : i + 12])
        out.append(struct.unpack("<dd", data[i + 12 : i + 28]) if shape_type == 1 else None)
        i += 8 + length * 2
    return out


def read_locations(zip_file: BinaryIO) -> dict[str, SignLocation]:
    """uuid -> where the sign hangs, from NDW's shapefile zip."""
    with zipfile.ZipFile(zip_file) as archive:
        names = archive.namelist()
        shp = next(n for n in names if n.lower().endswith(".shp"))
        dbf = next(n for n in names if n.lower().endswith(".dbf"))
        points, records = _points(archive.read(shp)), _dbf(archive.read(dbf))
    out = {}
    for point, record in zip(points, records, strict=False):
        if point is None or not record.get("uuid"):
            continue
        try:
            out[record["uuid"]] = SignLocation(
                point[1],
                point[0],
                float(record["bearing"]),
                record["road"],
                record["carriagew0"],
                record["km"],
                int(float(record["lane"])),
            )
        except (KeyError, ValueError):
            continue
    return out


def code(display: Element) -> str:
    """What a sign shows, in short: "70" (advisory), "70r" (mandatory, red ring),
    "x" (lane closed), "<" / ">" (merge left/right), "open" (green arrow),
    "end" (end of restrictions), "" (blank)."""
    for child in display:
        kind = _name(child)
        if kind == "speedlimit" and (child.text or "").strip().isdigit():
            return child.text.strip() + ("r" if child.attrib.get("red_ring") == "true" else "")
        if kind == "lane_closed":
            return "x"
        if kind == "lane_closed_ahead":
            if _first(child, "merge_left") is not None:
                return "<"
            if _first(child, "merge_right") is not None:
                return ">"
            return "x"
        if kind == "lane_open":
            return "open"
        if kind == "restriction_end":
            return "end"
    return ""


def read_displays(stream: BinaryIO) -> dict[str, str]:
    """uuid -> what the sign shows right now (see `code`)."""
    out = {}
    for event in _records(stream, "event"):
        display, sign = _first(event, "display"), _first(event, "sign_id")
        uuid = _text(sign, "uuid") if sign is not None else None
        if display is not None and uuid:
            out[uuid] = code(display)
    return out


def gantries(
    locations: dict[str, SignLocation], displays: dict[str, str], margin_km: float = 3.0
) -> list[Gantry]:
    """The gantries that show something, plus the blank ones within [margin_km]
    of them on the same road and carriageway: a speed above the road applies
    until the next gantry, and if that one is blank, it ends there. The rest
    (most of them) is left out."""
    per_gantry: dict[tuple[str, str, str], list[tuple[SignLocation, str]]] = defaultdict(list)
    for uuid, display in displays.items():
        location = locations.get(uuid)
        if location:
            per_gantry[(location.road, location.carriageway, location.km)].append(
                (location, display)
            )
    occupied: dict[tuple[str, str], list[float]] = defaultdict(list)
    for (road, carriageway, km), signs in per_gantry.items():
        if any(display for _, display in signs):
            occupied[(road, carriageway)].append(_km(km))
    out = []
    for (road, carriageway, km), signs in per_gantry.items():
        if not any(display for _, display in signs) and not any(
            abs(_km(km) - other) <= margin_km for other in occupied[(road, carriageway)]
        ):
            continue
        signs.sort(key=lambda sign: sign[0].lane)
        first = signs[0][0]
        out.append(
            Gantry(
                road,
                carriageway,
                km,
                first.lat,
                first.lon,
                first.bearing,
                tuple(display for _, display in signs),
            )
        )
    return out


def _km(text: str) -> float:
    try:
        return float(text)
    except ValueError:
        return float("nan")
