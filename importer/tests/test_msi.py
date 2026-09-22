import io
import json
import struct
import zipfile
from pathlib import Path

from homemaps_traffic import kaartlaag, msi
from homemaps_traffic.datex3 import Brug
from homemaps_traffic.main import Stand

FIXTURES = Path(__file__).parent / "fixtures"

# uuid, lat, lon, koers, weg, rijbaan, km, strook
BORDEN = [
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
    """Een puntenshapefile zoals NDW hem levert (dezelfde velden)."""
    shp = bytearray(100)
    for nummer, (_, lat, lon, *_rest) in enumerate(BORDEN, 1):
        shp += struct.pack(">II", nummer, 10) + struct.pack("<idd", 1, lon, lat)
    shp += struct.pack(">II", len(BORDEN) + 1, 2) + struct.pack("<i", 0)  # lege vorm
    velden = [("pk_uid", "N", 5), ("uuid", "C", 40), ("road", "C", 10), ("carriagew0", "C", 5)]
    velden += [("lane", "N", 5), ("km", "N", 12), ("bearing", "N", 12)]
    lengte = 1 + sum(breedte for *_, breedte in velden)
    dbf = bytearray(struct.pack("<BBBBIHH", 3, 126, 9, 22, len(BORDEN) + 1, 0, lengte) + bytes(20))
    for naam, soort, breedte in velden:
        dbf += naam.encode().ljust(11, b"\0") + soort.encode() + bytes(4) + bytes([breedte, 0])
        dbf += bytes(14)
    dbf += b"\r"
    struct.pack_into("<H", dbf, 8, len(dbf))
    for nummer, (uuid, _, _, koers, weg, rijbaan, km, strook) in enumerate(BORDEN, 1):
        waarden = [str(nummer), uuid, weg, rijbaan, str(strook), km, str(koers)]
        dbf += b" " + b"".join(
            w.encode().ljust(breedte) for w, (*_, breedte) in zip(waarden, velden, strict=True)
        )
    dbf += b"*" + bytes(lengte - 1)  # gewist record bij de lege vorm
    uit = io.BytesIO()
    with zipfile.ZipFile(uit, "w") as archief:
        archief.writestr("MSI/shapes.shp", bytes(shp))
        archief.writestr("MSI/shapes.dbf", bytes(dbf))
    uit.seek(0)
    return uit


def _portalen():
    with open(FIXTURES / "msi.xml", "rb") as stroom:
        beelden = msi.lees_beelden(stroom)
    return beelden, msi.portalen(msi.lees_locaties(_shapefile_zip()), beelden)


def test_plekken_uit_de_shapefile():
    plekken = msi.lees_locaties(_shapefile_zip())
    assert set(plekken) == {uuid for uuid, *_ in BORDEN}
    assert plekken["L1"] == msi.Bordplek(52.0, 5.0, 90.0, "A2", "R", "10.000000", 1)


def test_beelden():
    beelden, _ = _portalen()
    assert beelden == {
        "L1": "80r",  # rode ring: verplicht
        "L2": "70",  # zonder: advies
        "L3": "<",
        "N1": "",
        "V1": "",
        "X1": "x",
        "X2": "einde",
        "X3": "open",
        "ONBEKEND": "x",
    }


def test_portalen_van_links_naar_rechts_met_de_lege_ernaast():
    _, portalen = _portalen()
    per_km = {(p.weg, p.km): p for p in portalen}
    # V1 is leeg en ligt 20 km verder: die zegt niets. N1 is leeg maar ligt
    # vlak na het portaal met de 80: daar houdt die op.
    assert set(per_km) == {("A2", "10.000000"), ("A2", "11.000000"), ("A12", "5.000000")}
    a2 = per_km[("A2", "10.000000")]
    assert a2.stroken == ("80r", "70", "<")
    assert (a2.lat, a2.lon, a2.koers) == (52.0, 5.0, 90.0)
    assert per_km[("A2", "11.000000")].stroken == ("",)
    assert per_km[("A12", "5.000000")].stroken == ("x", "einde", "open")


def test_kaartlaag_en_samenstellen():
    _, portalen = _portalen()
    features = kaartlaag.msi(portalen)
    a2 = next(f for f in features if f["properties"]["stroken"] == ["80r", "70", "<"])
    assert a2["properties"] == {"soort": "msi", "koers": 90, "stroken": ["80r", "70", "<"]}
    assert a2["geometry"] == {"type": "Point", "coordinates": [5.0, 52.0]}

    stand = Stand()
    stand.zet_deel("msi", features)
    assert stand.laag is None  # pas met de ronde erbij
    stand.zet_deel("ronde", [{"type": "Feature", "properties": {"soort": "dicht"}}])
    assert stand.laag is not None
    laag = json.loads(stand.laag[0])
    assert sorted(f["properties"]["soort"] for f in laag["features"]) == ["dicht"] + ["msi"] * 3
    assert [f["id"] for f in laag["features"]] == [0, 1, 2, 3]


def test_bruggen_als_punten():
    assert kaartlaag.bruggen([Brug("B", (53.07374, 5.335099))]) == [
        {
            "type": "Feature",
            "properties": {"soort": "brug"},
            "geometry": {"type": "Point", "coordinates": [5.3351, 53.07374]},
        }
    ]
