from datetime import UTC, datetime

from homemaps_traffic import traffictile as tt
from homemaps_traffic.datex3 import Closure, TemporarySpeedLimit, TravelTime
from homemaps_traffic.main import compute_closures, compute_speeds, place_speed_limits
from homemaps_traffic.matcher import Match


def test_speed_from_length_and_travel_time():
    matches = {"A@1": Match(((100, 600.0, 1), (101, 400.0, 1)), 1000.0)}
    records = compute_speeds([TravelTime("A", "1", 72.0, 36.0)], matches)
    # 1000 m in 72 s = 50 km/h; normally 100 km/h.
    assert set(records) == {100, 101}
    fields = tt.unpack(records[100])
    assert fields["overall"] == 25 and fields["breakpoint1"] == 255
    assert 25 < fields["congestion1"] < 40


def test_shared_edge_weighs_by_length():
    matches = {
        "A@1": Match(((100, 900.0, 1),), 900.0),
        "B@1": Match(((100, 100.0, 1),), 100.0),
    }
    records = compute_speeds(
        [
            TravelTime("A", "1", 900 / (100 / 3.6), None),
            TravelTime("B", "1", 100 / (20 / 3.6), None),
        ],
        matches,
    )
    # Harmonic: 1000 m in (32.4 + 18) s = 71 km/h -- not 60 (arithmetic).
    assert tt.unpack(records[100])["overall"] * 2 in (70, 72)


def test_unknown_and_impossible_measurements_are_dropped():
    matches = {"A@1": Match(((100, 1000.0, 1),), 1000.0), "B@1": None}
    records = compute_speeds(
        [
            TravelTime("A", "1", 5.0, None),
            TravelTime("B", "1", 60.0, None),
            TravelTime("C", "9", 60.0, None),
        ],
        matches,
    )
    assert records == {}  # A is 720 km/h, B is unmatchable, C is not in the cache


def test_closure_includes_opposite_direction_only_on_the_same_way():
    matches = {
        "X@1": Match(((1, 100.0, 50), (2, 100.0, 51)), 200.0),
        "X@1#reverse": Match(((3, 100.0, 51), (4, 100.0, 99)), 200.0),
    }
    closed = compute_closures([Closure("X", "1", ((0, 0), (1, 1)), False)], matches)
    assert set(closed) == {1, 2, 3}  # 4 lies on its own carriageway (way 99)
    assert all(tt.is_closed(value) for value in closed.values())
    whole_road = compute_closures([Closure("X", "1", ((0, 0), (1, 1)), True)], matches)
    assert set(whole_road) == {1, 2, 3, 4}


def test_temporary_speed_limit_includes_opposite_direction_only_on_the_same_way():
    start = datetime(2026, 9, 1, tzinfo=UTC)
    limit = TemporarySpeedLimit("W", "1", 30, (((0, 0), (1, 1)),), None, ((start, None),))
    other = TemporarySpeedLimit("G", "1", 70, (((0, 0), (1, 1)),), None, ((start, None),))
    matches = {
        # Single carriageway: back over the same way.
        "W@1": Match(((1, 100.0, 50), (2, 100.0, 51)), 200.0, ("a",)),
        "W@1#reverse": Match(((3, 100.0, 51), (4, 100.0, 50)), 200.0, ("b",)),
        # Dual carriageways: back partly over a way of its own.
        "G@1": Match(((5, 100.0, 60),), 100.0, ("c",)),
        "G@1#reverse": Match(((6, 100.0, 60), (7, 100.0, 99)), 200.0, ("d",)),
    }
    placed = place_speed_limits([limit, other], matches)
    assert [(s.id, m.shape) for s, m in placed] == [
        ("W", ("a",)),
        ("W", ("b",)),
        ("G", ("c",)),
    ]
    # Not matched: dropped.
    assert place_speed_limits([limit], {"W@1": None}) == []
