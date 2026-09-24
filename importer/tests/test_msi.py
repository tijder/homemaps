import io
import json
import struct
import zipfile
from pathlib import Path

from homemaps_traffic import maplayer, msi
from homemaps_traffic.datex3 import Bridge
from homemaps_traffic.main import State

FIXTURES = Path(__file__).parent / "fixtures"

# uuid, lat, lon, bearing, road, carriageway, km, lane
SIGNS = [
    ("L3", 52.0, 5.0, 90.0, "A2", "R", "10.000000", 3),
    ("L1", 52.0, 5.0, 90.0, "A2", "R", "10.000000", 1),
    ("L2", 52.0, 5.0, 90.0, "A2", "R", "10.000000", 2),
    ("N1", 52.0, 5.01, 90.0, "A2", "R", "11.000000", 1),
    ("V1", 52.0, 5.3, 90.0, "A2", "R", "30.000000", 1),
    ("X1", 52.1, 5.1, 180.0, "A12", "L", "5.000000", 1),
    ("X2", 52.1, 5.1, 180.0, "A12", "L", "5.000000", 2),
    ("X3", 52.1, 5.1, 180.0, "A12", "L", "5.000000", 3),
]


def _shapefile_zip() -> io.BytesIO:
    """A point shapefile as NDW delivers it (the same fields)."""
    shp = bytearray(100)
    for number, (_, lat, lon, *_rest) in enumerate(SIGNS, 1):
        shp += struct.pack(">II", number, 10) + struct.pack("<idd", 1, lon, lat)
    shp += struct.pack(">II", len(SIGNS) + 1, 2) + struct.pack("<i", 0)  # empty shape
    fields = [("pk_uid", "N", 5), ("uuid", "C", 40), ("road", "C", 10), ("carriagew0", "C", 5)]
    fields += [("lane", "N", 5), ("km", "N", 12), ("bearing", "N", 12)]
    length = 1 + sum(width for *_, width in fields)
    dbf = bytearray(struct.pack("<BBBBIHH", 3, 126, 9, 22, len(SIGNS) + 1, 0, length) + bytes(20))
    for name, field_type, width in fields:
        dbf += name.encode().ljust(11, b"\0") + field_type.encode() + bytes(4) + bytes([width, 0])
        dbf += bytes(14)
    dbf += b"\r"
    struct.pack_into("<H", dbf, 8, len(dbf))
    for number, (uuid, _, _, bearing, road, carriageway, km, lane) in enumerate(SIGNS, 1):
        values = [str(number), uuid, road, carriageway, str(lane), km, str(bearing)]
        dbf += b" " + b"".join(
            v.encode().ljust(width) for v, (*_, width) in zip(values, fields, strict=True)
        )
    dbf += b"*" + bytes(length - 1)  # deleted record for the empty shape
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as archive:
        archive.writestr("MSI/shapes.shp", bytes(shp))
        archive.writestr("MSI/shapes.dbf", bytes(dbf))
    out.seek(0)
    return out


def _gantries():
    with open(FIXTURES / "msi.xml", "rb") as stream:
        displays = msi.read_displays(stream)
    return displays, msi.gantries(msi.read_locations(_shapefile_zip()), displays)


def test_locations_from_the_shapefile():
    locations = msi.read_locations(_shapefile_zip())
    assert set(locations) == {uuid for uuid, *_ in SIGNS}
    assert locations["L1"] == msi.SignLocation(52.0, 5.0, 90.0, "A2", "R", "10.000000", 1)


def test_displays():
    displays, _ = _gantries()
    assert displays == {
        "L1": "80r",  # red ring: mandatory
        "L2": "70",  # without: advisory
        "L3": "<",
        "N1": "",
        "V1": "",
        "X1": "x",
        "X2": "end",
        "X3": "open",
        "ONBEKEND": "x",
    }


def test_gantries_from_left_to_right_with_the_blank_ones_next_to_them():
    _, gantries = _gantries()
    per_km = {(g.road, g.km): g for g in gantries}
    # V1 is blank and lies 20 km further on: it says nothing. N1 is blank but
    # lies just after the gantry with the 80: that is where it ends.
    assert set(per_km) == {("A2", "10.000000"), ("A2", "11.000000"), ("A12", "5.000000")}
    a2 = per_km[("A2", "10.000000")]
    assert a2.lanes == ("80r", "70", "<")
    assert (a2.lat, a2.lon, a2.bearing) == (52.0, 5.0, 90.0)
    assert per_km[("A2", "11.000000")].lanes == ("",)
    assert per_km[("A12", "5.000000")].lanes == ("x", "end", "open")


def test_map_layer_and_assembly():
    _, gantries = _gantries()
    features = maplayer.msi(gantries)
    a2 = next(f for f in features if f["properties"]["lanes"] == ["80r", "70", "<"])
    assert a2["properties"] == {"kind": "msi", "bearing": 90, "lanes": ["80r", "70", "<"]}
    assert a2["geometry"] == {"type": "Point", "coordinates": [5.0, 52.0]}

    state = State()
    state.set_part("msi", features)
    assert state.layer is None  # only once the cycle is there too
    state.set_part("cycle", [{"type": "Feature", "properties": {"kind": "closed"}}])
    assert state.layer is not None
    layer = json.loads(state.layer[0])
    assert sorted(f["properties"]["kind"] for f in layer["features"]) == ["closed"] + ["msi"] * 3
    assert [f["id"] for f in layer["features"]] == [0, 1, 2, 3]


def test_bridges_as_points():
    assert maplayer.bridges([Bridge("B", (53.07374, 5.335099))]) == [
        {
            "type": "Feature",
            "properties": {"kind": "bridge"},
            "geometry": {"type": "Point", "coordinates": [5.3351, 53.07374]},
        }
    ]
