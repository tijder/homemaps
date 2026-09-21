import io
import tarfile

import pytest

from homemaps_traffic import traffictile as tt
from homemaps_traffic.tarindex import TrafficTar


def test_bitlayout_komt_overeen_met_de_cpp_struct():
    # overall 7 | s1 7 | s2 7 | s3 7 | bp1 8 | bp2 8 | c1 6 | c2 6 | c3 6 | inc 1 | spare 1
    waarde = tt._pak_in(
        overall=1,
        speed1=2,
        speed2=3,
        speed3=4,
        breakpoint1=5,
        breakpoint2=6,
        congestion1=7,
        congestion2=8,
        congestion3=9,
        has_incidents=1,
    )
    verwacht = (
        1 | 2 << 7 | 3 << 14 | 4 << 21 | 5 << 28 | 6 << 36 | 7 << 44 | 8 << 50 | 9 << 56 | 1 << 62
    )
    assert waarde == verwacht
    assert tt.pak_uit(waarde)["congestion3"] == 9


def test_snelheid_is_geldig_en_nooit_nul():
    assert tt.pak_uit(tt.snelheid(100))["overall"] == 50
    assert tt.pak_uit(tt.snelheid(100))["breakpoint1"] == 255
    assert tt.is_geldig(tt.snelheid(100))
    # 0,4 km/u is file, geen afsluiting
    assert not tt.is_afgesloten(tt.snelheid(0.4))
    assert tt.pak_uit(tt.snelheid(400))["overall"] == 126


def test_congestie_blijft_onder_de_afsluitwaarde():
    assert tt.pak_uit(tt.snelheid(100, 100))["congestion1"] == 1
    assert tt.pak_uit(tt.snelheid(0.1, 100))["congestion1"] == 62
    assert tt.pak_uit(tt.snelheid(50))["congestion1"] == 0


def test_afgesloten_en_onbekend():
    assert tt.is_afgesloten(tt.afgesloten())
    assert not tt.is_geldig(tt.ONBEKEND)
    assert not tt.is_afgesloten(tt.ONBEKEND)


def test_veld_buiten_bereik():
    with pytest.raises(ValueError):
        tt._pak_in(overall=128)


def test_graphid():
    graphid = 2 | (763140 << 3) | (1234 << 25)
    assert tt.graphid_delen(graphid) == (2, 763140, 1234)
    assert tt.tegel_van(graphid) == 2 | (763140 << 3)
    assert tt.index_van(graphid) == 1234


def _skelet(pad, tegels):
    with tarfile.open(pad, "w") as tar:
        # Net als het echte skelet: een index.bin vooraan, die geen tegel is.
        index = tarfile.TarInfo("index.bin")
        index.size = 112
        tar.addfile(index, io.BytesIO(bytes(range(112))))
        for tile_id, aantal in tegels.items():
            data = tt.HEADER.pack(tile_id, 0, aantal, tt.TILE_VERSION, 0, 0) + bytes(8 * aantal)
            info = tarfile.TarInfo(f"2/000/{tile_id}.gph")
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


def test_tar_bijwerken_en_wissen(tmp_path):
    pad = tmp_path / "traffic.tar"
    tegel_a, tegel_b = 2 | (10 << 3), 2 | (11 << 3)
    _skelet(pad, {tegel_a: 5, tegel_b: 3})
    grootte = pad.stat().st_size

    edge1, edge2 = tegel_a | (4 << 25), tegel_b | (0 << 25)
    buiten = tegel_a | (5 << 25)
    met_tar = TrafficTar(pad)
    assert met_tar.aantal_edges == 8
    ronde = {edge1: tt.snelheid(80), edge2: tt.afgesloten(), buiten: 1}
    assert met_tar.werk_bij(ronde, set()) == (2, 0, 1)
    met_tar.sluit()

    # Opnieuw openen: het staat echt in het bestand, en de tar is nog heel.
    assert pad.stat().st_size == grootte
    with TrafficTar(pad) as tar:
        assert tt.pak_uit(tar.lees(edge1))["overall"] == 40
        assert tt.is_afgesloten(tar.lees(edge2))
        assert tar.lees(tegel_a | (3 << 25)) == tt.ONBEKEND
        # Volgende ronde zonder edge2: die moet terug naar onbekend.
        assert tar.werk_bij({edge1: tt.snelheid(60)}, {edge1, edge2}) == (1, 1, 0)
        assert tar.lees(edge2) == tt.ONBEKEND
        tar.wis_alles()
        assert tar.lees(edge1) == tt.ONBEKEND
    with tarfile.open(pad) as tar:
        assert len(tar.getmembers()) == 3
