"""Het binaire formaat van Valhalla's live verkeer (valhalla/baldr/traffictile.h).

Een verkeerstegel is een TrafficTileHeader van 32 bytes gevolgd door één
TrafficSpeed van 8 bytes per directed edge, in de volgorde van de routing-tegel.
Het commentaar in de C++-header noemt "24 bytes" en "2 bytes"; dat is verouderd,
de static_asserts daaronder zeggen 4 x uint64 en 1 x uint64.
"""

import struct
from dataclasses import dataclass

HEADER = struct.Struct("<QQIIII")
RECORD = struct.Struct("<Q")
HEADER_SIZE = HEADER.size
RECORD_SIZE = RECORD.size
assert HEADER_SIZE == 32 and RECORD_SIZE == 8

# Gelijk aan VALHALLA_VERSION_MAJOR. Bij een andere waarde in de header negeert
# Valhalla de héle tegel, zonder melding.
TILE_VERSION = 3

UNKNOWN_SPEED_RAW = 127
MAX_SPEED_KPH = (UNKNOWN_SPEED_RAW - 1) * 2
MAX_CONGESTION = 63

# "Geen gegevens": breakpoint1 == 0 maakt speed_valid() onwaar. Dit is ook wat
# valhalla_build_extract --with-traffic in het skelet zet.
ONBEKEND = 0

# De bitvelden van TrafficSpeed, van laag naar hoog: (naam, breedte).
_VELDEN = (
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
assert sum(breedte for _, breedte in _VELDEN) == 64


@dataclass(frozen=True)
class Header:
    tile_id: int
    last_update: int
    directed_edge_count: int
    version: int

    @classmethod
    def lees(cls, data) -> "Header":
        tile_id, last_update, aantal, versie, _, _ = HEADER.unpack_from(data)
        return cls(tile_id, last_update, aantal, versie)


def _pak_in(**velden: int) -> int:
    waarde, schuif = 0, 0
    for naam, breedte in _VELDEN:
        veld = velden.get(naam, 0)
        if not 0 <= veld < (1 << breedte):
            raise ValueError(f"{naam}={veld} past niet in {breedte} bits")
        waarde |= veld << schuif
        schuif += breedte
    return waarde


def pak_uit(waarde: int) -> dict[str, int]:
    velden, schuif = {}, 0
    for naam, breedte in _VELDEN:
        velden[naam] = (waarde >> schuif) & ((1 << breedte) - 1)
        schuif += breedte
    return velden


def _congestie(kph: float, vrij_kph: float | None) -> int:
    """1 (vrij) tot 62 (staat stil). 63 is bewust onbereikbaar: dat leest Valhalla
    als een afsluiting van het deelsegment."""
    if not vrij_kph or vrij_kph <= 0:
        return 0
    verhouding = max(0.0, min(1.0, kph / vrij_kph))
    return max(1, min(MAX_CONGESTION - 1, round(1 + (1 - verhouding) * (MAX_CONGESTION - 2))))


def snelheid(kph: float, vrij_kph: float | None = None) -> int:
    """Eén live snelheid voor de hele edge.

    De resolutie is 2 km/u. Een rijdende meting wordt nooit naar 0 afgerond, want
    0 betekent "afgesloten" en dat is iets anders dan "file".
    """
    ruw = max(1, min(MAX_SPEED_KPH // 2, round(kph / 2)))
    return _pak_in(
        overall=ruw,
        speed1=ruw,
        breakpoint1=255,
        congestion1=_congestie(kph, vrij_kph),
    )


def afgesloten() -> int:
    """breakpoint1 != 0 met snelheid 0: TrafficSpeed::closed()."""
    return _pak_in(overall=0, speed1=0, breakpoint1=255, congestion1=MAX_CONGESTION)


def is_afgesloten(waarde: int) -> bool:
    velden = pak_uit(waarde)
    return velden["breakpoint1"] != 0 and velden["overall"] == 0


def is_geldig(waarde: int) -> bool:
    velden = pak_uit(waarde)
    return velden["breakpoint1"] != 0 and velden["overall"] != UNKNOWN_SPEED_RAW


# GraphId: 3 bits hiërarchieniveau, 22 bits tegel, 21 bits index binnen de tegel.
def graphid_delen(graphid: int) -> tuple[int, int, int]:
    return graphid & 0x7, (graphid >> 3) & 0x3FFFFF, (graphid >> 25) & 0x1FFFFF


def tegel_van(graphid: int) -> int:
    """De GraphId van de tegel zelf (index 0): de sleutel in de verkeersheader."""
    return graphid & 0x1FFFFFF


def index_van(graphid: int) -> int:
    return (graphid >> 25) & 0x1FFFFF
