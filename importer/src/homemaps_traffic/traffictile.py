"""The binary format of Valhalla's live traffic (valhalla/baldr/traffictile.h).

A traffic tile is a 32-byte TrafficTileHeader followed by one 8-byte
TrafficSpeed per directed edge, in the order of the routing tile. The comment
in the C++ header says "24 bytes" and "2 bytes"; that is outdated, the
static_asserts below it say 4 x uint64 and 1 x uint64.
"""

import struct
from dataclasses import dataclass

HEADER = struct.Struct("<QQIIII")
RECORD = struct.Struct("<Q")
HEADER_SIZE = HEADER.size
RECORD_SIZE = RECORD.size
assert HEADER_SIZE == 32 and RECORD_SIZE == 8

# Equal to VALHALLA_VERSION_MAJOR. With a different value in the header Valhalla
# ignores the *entire* tile, silently.
TILE_VERSION = 3

UNKNOWN_SPEED_RAW = 127
MAX_SPEED_KPH = (UNKNOWN_SPEED_RAW - 1) * 2
MAX_CONGESTION = 63

# "No data": breakpoint1 == 0 makes speed_valid() false. This is also what
# valhalla_build_extract --with-traffic puts in the skeleton.
UNKNOWN = 0

# The bit fields of TrafficSpeed, from low to high: (name, width).
_FIELDS = (
    ("overall", 7),
    ("speed1", 7),
    ("speed2", 7),
    ("speed3", 7),
    ("breakpoint1", 8),
    ("breakpoint2", 8),
    ("congestion1", 6),
    ("congestion2", 6),
    ("congestion3", 6),
    ("has_incidents", 1),
    ("spare", 1),
)
assert sum(width for _, width in _FIELDS) == 64


@dataclass(frozen=True)
class Header:
    tile_id: int
    last_update: int
    directed_edge_count: int
    version: int

    @classmethod
    def read(cls, data) -> "Header":
        tile_id, last_update, count, version, _, _ = HEADER.unpack_from(data)
        return cls(tile_id, last_update, count, version)


def _pack(**fields: int) -> int:
    value, shift = 0, 0
    for name, width in _FIELDS:
        field = fields.get(name, 0)
        if not 0 <= field < (1 << width):
            raise ValueError(f"{name}={field} does not fit in {width} bits")
        value |= field << shift
        shift += width
    return value


def unpack(value: int) -> dict[str, int]:
    fields, shift = {}, 0
    for name, width in _FIELDS:
        fields[name] = (value >> shift) & ((1 << width) - 1)
        shift += width
    return fields


def _congestion(kph: float, freeflow_kph: float | None) -> int:
    """1 (free) to 62 (standstill). 63 is deliberately unreachable: Valhalla reads
    that as a closure of the sub-segment."""
    if not freeflow_kph or freeflow_kph <= 0:
        return 0
    ratio = max(0.0, min(1.0, kph / freeflow_kph))
    return max(1, min(MAX_CONGESTION - 1, round(1 + (1 - ratio) * (MAX_CONGESTION - 2))))


def speed(kph: float, freeflow_kph: float | None = None) -> int:
    """One live speed for the whole edge.

    The resolution is 2 km/h. A moving measurement is never rounded to 0, because
    0 means "closed" and that is something else than "jam".
    """
    raw = max(1, min(MAX_SPEED_KPH // 2, round(kph / 2)))
    return _pack(
        overall=raw,
        speed1=raw,
        breakpoint1=255,
        congestion1=_congestion(kph, freeflow_kph),
    )


def closed() -> int:
    """breakpoint1 != 0 with speed 0: TrafficSpeed::closed()."""
    return _pack(overall=0, speed1=0, breakpoint1=255, congestion1=MAX_CONGESTION)


def is_closed(value: int) -> bool:
    fields = unpack(value)
    return fields["breakpoint1"] != 0 and fields["overall"] == 0


def is_valid(value: int) -> bool:
    fields = unpack(value)
    return fields["breakpoint1"] != 0 and fields["overall"] != UNKNOWN_SPEED_RAW


# GraphId: 3 bits hierarchy level, 22 bits tile, 21 bits index within the tile.
def graphid_parts(graphid: int) -> tuple[int, int, int]:
    return graphid & 0x7, (graphid >> 3) & 0x3FFFFF, (graphid >> 25) & 0x1FFFFF


def tile_of(graphid: int) -> int:
    """The GraphId of the tile itself (index 0): the key in the traffic header."""
    return graphid & 0x1FFFFFF


def index_of(graphid: int) -> int:
    return (graphid >> 25) & 0x1FFFFF
