import io
import tarfile

import pytest

from homemaps_traffic import traffictile as tt
from homemaps_traffic.tarindex import TrafficTar


def test_bit_layout_matches_the_cpp_struct():
    # overall 7 | s1 7 | s2 7 | s3 7 | bp1 8 | bp2 8 | c1 6 | c2 6 | c3 6 | inc 1 | spare 1
    value = tt._pack(
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
    expected = (
        1 | 2 << 7 | 3 << 14 | 4 << 21 | 5 << 28 | 6 << 36 | 7 << 44 | 8 << 50 | 9 << 56 | 1 << 62
    )
    assert value == expected
    assert tt.unpack(value)["congestion3"] == 9


def test_speed_is_valid_and_never_zero():
    assert tt.unpack(tt.speed(100))["overall"] == 50
    assert tt.unpack(tt.speed(100))["breakpoint1"] == 255
    assert tt.is_valid(tt.speed(100))
    # 0.4 km/h is a jam, not a closure
    assert not tt.is_closed(tt.speed(0.4))
    assert tt.unpack(tt.speed(400))["overall"] == 126


def test_congestion_stays_below_the_closure_value():
    assert tt.unpack(tt.speed(100, 100))["congestion1"] == 1
    assert tt.unpack(tt.speed(0.1, 100))["congestion1"] == 62
    assert tt.unpack(tt.speed(50))["congestion1"] == 0


def test_closed_and_unknown():
    assert tt.is_closed(tt.closed())
    assert not tt.is_valid(tt.UNKNOWN)
    assert not tt.is_closed(tt.UNKNOWN)


def test_field_out_of_range():
    with pytest.raises(ValueError):
        tt._pack(overall=128)


def test_graphid():
    graphid = 2 | (763140 << 3) | (1234 << 25)
    assert tt.graphid_parts(graphid) == (2, 763140, 1234)
    assert tt.tile_of(graphid) == 2 | (763140 << 3)
    assert tt.index_of(graphid) == 1234


def _skeleton(path, tiles):
    with tarfile.open(path, "w") as tar:
        # Just like the real skeleton: an index.bin up front, which is not a tile.
        index = tarfile.TarInfo("index.bin")
        index.size = 112
        tar.addfile(index, io.BytesIO(bytes(range(112))))
        for tile_id, count in tiles.items():
            data = tt.HEADER.pack(tile_id, 0, count, tt.TILE_VERSION, 0, 0) + bytes(8 * count)
            info = tarfile.TarInfo(f"2/000/{tile_id}.gph")
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


def test_tar_update_and_clear(tmp_path):
    path = tmp_path / "traffic.tar"
    tile_a, tile_b = 2 | (10 << 3), 2 | (11 << 3)
    _skeleton(path, {tile_a: 5, tile_b: 3})
    size = path.stat().st_size

    edge1, edge2 = tile_a | (4 << 25), tile_b | (0 << 25)
    outside = tile_a | (5 << 25)
    traffic_tar = TrafficTar(path)
    assert traffic_tar.edge_count == 8
    cycle = {edge1: tt.speed(80), edge2: tt.closed(), outside: 1}
    assert traffic_tar.update(cycle, set()) == (2, 0, 1)
    traffic_tar.close()

    # Reopen: it really is in the file, and the tar is still intact.
    assert path.stat().st_size == size
    with TrafficTar(path) as tar:
        assert tt.unpack(tar.read(edge1))["overall"] == 40
        assert tt.is_closed(tar.read(edge2))
        assert tar.read(tile_a | (3 << 25)) == tt.UNKNOWN
        # Next cycle without edge2: it has to go back to unknown.
        assert tar.update({edge1: tt.speed(60)}, {edge1, edge2}) == (1, 1, 0)
        assert tar.read(edge2) == tt.UNKNOWN
        tar.clear_all()
        assert tar.read(edge1) == tt.UNKNOWN
    with tarfile.open(path) as tar:
        assert len(tar.getmembers()) == 3
