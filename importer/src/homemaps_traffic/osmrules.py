"""Maximum speeds that depend on the time of day, from the tileset's OSM file:
`maxspeed:conditional` ("130 @ (19:00-06:00)" on most motorways).
Valhalla does not read that tag; the app applies the rules itself while driving,
per OSM way (which Valhalla does pass along).

The PBF file is 1.4 GB. A reader of our own, without libosmium: only the blocks
that contain the tag are parsed (5% in the Netherlands), the rest is skipped
right after decompressing. That takes ~20 s with ~20 MB of memory.
"""

import re
import struct
import zlib
from collections.abc import Iterator
from typing import BinaryIO

KEY = b"maxspeed:conditional"

# Days as a bitmask: Mo=1, Tu=2, ..., Su=64.
DAYS = {"Mo": 0, "Tu": 1, "We": 2, "Th": 3, "Fr": 4, "Sa": 5, "Su": 6}
EVERY_DAY = 0b1111111

# (km/h, days, [(from, to), ...]) with from/to in minutes after midnight; from > to
# runs past midnight.
Rule = tuple[int, int, list[tuple[int, int]]]


def _varint(data: bytes, i: int) -> tuple[int, int]:
    out = shift = 0
    while True:
        byte = data[i]
        i += 1
        out |= (byte & 0x7F) << shift
        if byte < 0x80:
            return out, i
        shift += 7


def _fields(data: bytes) -> Iterator[tuple[int, int | bytes]]:
    """The fields of a protobuf message: (number, value)."""
    i, end = 0, len(data)
    while i < end:
        key, i = _varint(data, i)
        wire_type = key & 7
        if wire_type == 0:
            value, i = _varint(data, i)
        elif wire_type == 2:
            length, i = _varint(data, i)
            value = data[i : i + length]
            i += length
        elif wire_type == 1:
            value, i = data[i : i + 8], i + 8
        elif wire_type == 5:
            value, i = data[i : i + 4], i + 4
        else:
            raise ValueError(f"unknown protobuf type {wire_type}")
        yield key >> 3, value


def _packed(data: bytes) -> list[int]:
    out, i = [], 0
    while i < len(data):
        value, i = _varint(data, i)
        out.append(value)
    return out


def read_pbf(stream: BinaryIO, key: bytes = KEY) -> dict[int, str]:
    """way id -> value of [key], for ways with a `highway` tag."""
    out: dict[int, str] = {}
    while head := stream.read(4):
        (length,) = struct.unpack(">I", head)
        header = dict(_fields(stream.read(length)))
        blob = dict(_fields(stream.read(header[3])))
        if header.get(1) != b"OSMData":
            continue
        if 3 in blob:
            data = zlib.decompress(blob[3])
        elif 1 in blob:
            data = blob[1]
        else:
            raise ValueError("only zlib or uncompressed is supported")
        # The fast filter: if the key is not in the block, no way in it has
        # that tag.
        if key not in data:
            continue
        strings: list[bytes] = []
        groups: list[bytes] = []
        for number, value in _fields(data):
            if number == 1:
                strings = [string for field, string in _fields(value) if field == 1]
            elif number == 2:
                groups.append(value)
        if key not in strings or b"highway" not in strings:
            continue
        index, highway = strings.index(key), strings.index(b"highway")
        for group in groups:
            for number, way in _fields(group):
                if number != 3:  # ways only
                    continue
                fields = dict(_fields(way))
                keys = _packed(fields.get(2, b""))
                if index in keys and highway in keys:
                    values = _packed(fields.get(3, b""))
                    out[fields[1]] = strings[values[keys.index(index)]].decode()
    return out


def _split_outside_parens(text: str, separator: str) -> list[str]:
    """Splits on [separator], but not inside parentheses."""
    parts, depth, start = [], 0, 0
    for i, char in enumerate(text):
        depth += char == "("
        depth -= char == ")"
        if char == separator and depth == 0:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return [part.strip() for part in parts if part.strip()]


def _minutes(time: str) -> int | None:
    hour, _, minute = time.partition(":")
    if not (hour.isdigit() and minute.isdigit()):
        return None
    value = int(hour) * 60 + int(minute)
    return value if 0 <= value <= 24 * 60 else None


def _days(text: str) -> int | None:
    mask = 0
    for part in text.split(","):
        first, _, last = part.partition("-")
        if first not in DAYS or (last and last not in DAYS):
            return None
        a, b = DAYS[first], DAYS[last or first]
        for day in range(7):
            if (a <= b and a <= day <= b) or (a > b and (day >= a or day <= b)):
                mask |= 1 << day
    return mask


def _condition(text: str) -> list[tuple[int, list[tuple[int, int]]]] | None:
    """A time condition ("Mo-Fr 06:00-10:00,15:00-19:00; Sa 08:00-12:00") as
    [(days, windows)]. None if it contains something that cannot be known here:
    `wet`, `sunrise`, free text, a date."""
    text = text.strip()
    if text.startswith("(") and text.endswith(")"):
        text = text[1:-1]
    out = []
    for rule in _split_outside_parens(text, ";"):
        if rule == "PH off":  # not on public holidays: then it simply does apply
            continue
        pieces = rule.split()
        days, times = EVERY_DAY, None
        if len(pieces) == 2:
            days, times = _days(pieces[0]), pieces[1]
        elif len(pieces) == 1 and re.match(r"^\d", pieces[0]):
            times = pieces[0]
        elif len(pieces) == 1:
            days, times = _days(pieces[0]), "00:00-24:00"
        if days is None or times is None:
            return None
        windows = []
        for window in times.split(","):
            start, _, end = window.partition("-")
            a, b = _minutes(start), _minutes(end)
            if a is None or b is None:
                return None
            windows.append((a, b))
        out.append((days, windows))
    return out or None


def rules(value: str) -> list[Rule]:
    """`maxspeed:conditional` as rules the app can apply. Whatever does not
    depend on the time of day (`70 @ wet`) or cannot be read is dropped."""
    out: list[Rule] = []
    for part in _split_outside_parens(value, ";"):
        speed, at_sign, condition = part.partition("@")
        speed = speed.strip()
        if not at_sign or not speed.isdigit():
            continue
        times = _condition(condition)
        if times is None:
            continue
        out.extend((int(speed), days, windows) for days, windows in times)
    return out


def conditional_speeds(stream: BinaryIO) -> dict[str, list[Rule]]:
    """way id (as text, for JSON) -> rules; only ways with something usable."""
    out = {}
    for way, value in read_pbf(stream).items():
        if found := rules(value):
            out[str(way)] = found
    return out
