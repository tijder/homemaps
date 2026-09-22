import io
import struct
import zlib

from homemaps_traffic import osmregels


def _varint(waarde: int) -> bytes:
    uit = bytearray()
    while True:
        byte = waarde & 0x7F
        waarde >>= 7
        if waarde:
            uit.append(byte | 0x80)
        else:
            uit.append(byte)
            return bytes(uit)


def _veld(nummer: int, waarde) -> bytes:
    if isinstance(waarde, int):
        return _varint(nummer << 3) + _varint(waarde)
    return _varint(nummer << 3 | 2) + _varint(len(waarde)) + waarde


def _packed(getallen) -> bytes:
    return b"".join(_varint(g) for g in getallen)


def _blok(soort: bytes, inhoud: bytes, comprimeer=True) -> bytes:
    blob = (
        _veld(2, len(inhoud)) + _veld(3, zlib.compress(inhoud)) if comprimeer else _veld(1, inhoud)
    )
    header = _veld(1, soort) + _veld(3, len(blob))
    return struct.pack(">I", len(header)) + header + blob


def _pbf(ways, comprimeer=True) -> io.BytesIO:
    """Een minimaal PBF-bestand: een header-blok en één blok met [ways] als
    (id, {sleutel: waarde})."""
    teksten = [b""]
    for _, tags in ways:
        for tekst in (*tags, *tags.values()):
            if tekst.encode() not in teksten:
                teksten.append(tekst.encode())
    tabel = b"".join(_veld(1, t) for t in teksten)
    groep = b""
    for way_id, tags in ways:
        sleutels = [teksten.index(k.encode()) for k in tags]
        waarden = [teksten.index(v.encode()) for v in tags.values()]
        way = _veld(1, way_id) + _veld(2, _packed(sleutels)) + _veld(3, _packed(waarden))
        groep += _veld(3, way)
    blok = _veld(1, tabel) + _veld(2, groep)
    kop = _blok(b"OSMHeader", b"", comprimeer)
    # Een blok zonder de tag wordt overgeslagen; hij mag er gewoon staan.
    leeg = _veld(1, _veld(1, b"") + _veld(1, b"highway")) + _veld(2, b"")
    return io.BytesIO(
        kop + _blok(b"OSMData", leeg, comprimeer) + _blok(b"OSMData", blok, comprimeer)
    )


def test_pbf_lezen():
    ways = [
        (
            7014267,
            {
                "highway": "motorway",
                "maxspeed": "100",
                "maxspeed:conditional": "130 @ (19:00-06:00)",
            },
        ),
        (2, {"highway": "primary", "maxspeed": "80"}),
        # Geen weg: telt niet.
        (3, {"railway": "rail", "maxspeed:conditional": "40 @ (22:00-06:00)"}),
        (300000000000, {"highway": "trunk", "maxspeed:conditional": "70 @ wet"}),
    ]
    for comprimeer in (True, False):
        assert osmregels.lees_pbf(_pbf(ways, comprimeer)) == {
            7014267: "130 @ (19:00-06:00)",
            300000000000: "70 @ wet",
        }


def test_snelheid_tijden_alleen_bruikbare_regels():
    ways = [
        (1, {"highway": "motorway", "maxspeed:conditional": "130 @ (19:00-06:00)"}),
        (2, {"highway": "trunk", "maxspeed:conditional": "70 @ wet"}),
    ]
    assert osmregels.snelheid_tijden(_pbf(ways)) == {"1": [(130, 127, [(1140, 360)])]}


def test_regels():
    elke = osmregels.ELKE_DAG
    werkdagen = 0b0011111
    assert osmregels.regels("130 @ (19:00-06:00)") == [(130, elke, [(1140, 360)])]
    assert osmregels.regels("100 @ (06:00-19:00)") == [(100, elke, [(360, 1140)])]
    # Dagen en meerdere vensters, met en zonder haakjes.
    assert osmregels.regels("100 @ (Mo-Fr 06:00-10:00,15:00-19:00)") == [
        (100, werkdagen, [(360, 600), (900, 1140)])
    ]
    assert osmregels.regels("80 @ Sa,Su 7:30-9:00") == [(80, 0b1100000, [(450, 540)])]
    # Meerdere regels binnen de voorwaarde, en "PH off" telt niet.
    assert osmregels.regels("30 @ (Mo-Fr 07:00-09:00; Sa 10:00-12:00; PH off)") == [
        (30, werkdagen, [(420, 540)]),
        (30, 0b0100000, [(600, 720)]),
    ]
    # Twee snelheden; nat weer valt weg.
    assert osmregels.regels("130 @ (19:00-06:00); 70 @ wet") == [(130, elke, [(1140, 360)])]
    # Wat niet van de klok afhangt of niet te lezen is.
    for tekst in (
        "70 @ wet",
        '100 @ Mo-Fr 06:00-10:00,15:00-19:00 "bij grote verkeersdrukte"',
        "none @ (sunrise-sunset)",
        "30 @ (2026 Jul 17-2027 Apr 21)",
        "30 @ school",
        "@ (19:00-06:00)",
        "130",
    ):
        assert osmregels.regels(tekst) == [], tekst
    # Een dagbereik over het weekend heen.
    assert osmregels.regels("50 @ (Fr-Mo 00:00-24:00)")[0][1] == 0b1110001
