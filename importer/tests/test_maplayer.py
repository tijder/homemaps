import gzip
import json
from datetime import UTC, datetime

from homemaps_traffic import maplayer
from homemaps_traffic.datex3 import Measure, TemporarySpeedLimit, TravelTime
from homemaps_traffic.matcher import Match


def _measure(management_type, trucks=False):
    return Measure(
        "M",
        "1",
        management_type,
        (((52.0, 5.0), (52.1, 5.1)), ((52.1, 5.1), (52.2, 5.2))),
        trucks,
        "exitSlipRoad",
        "roadMaintenance",
        datetime(2026, 10, 22, 18, 0, tzinfo=UTC),
        None,
    )


def test_measures_closed_and_roadworks():
    features = maplayer.measures(
        [
            _measure("carriagewayClosures"),
            _measure("laneClosures"),
            _measure("carriagewayClosures", trucks=True),
            _measure("useOfSpecifiedLanesOrCarriagewaysAllowed"),
        ]
    )
    assert [f["properties"]["kind"] for f in features] == ["closed", "roadworks"]
    closed = features[0]
    assert closed["properties"] == {
        "kind": "closed",
        "whole_road": False,
        "carriageway": "exitSlipRoad",
        "cause": "roadMaintenance",
        "until": "2026-10-22T18:00:00Z",
    }
    # Two posLists stay two lines, in GeoJSON order (lon, lat).
    assert closed["geometry"]["type"] == "MultiLineString"
    assert closed["geometry"]["coordinates"][0] == [[5.0, 52.0], [5.1, 52.1]]


def test_decode_six_decimals():
    # Utrecht -> Amsterdam, as Valhalla encodes it (also in the app test).
    points = maplayer.decode("wsjjbBovqwH_qfP~s~L")
    assert points == [(52.0907, 5.1214), (52.3731, 4.8922)]


def test_only_clearly_slow_segments():
    shape = ("wsjjbBovqwH_qfP~s~L",)
    matches = {f"{name}@1": Match(((1, 1000.0, 1),), 1000.0, shape) for name in "ABCDE"}
    matches["F@1"] = Match(((1, 1000.0, 1),), 1000.0)  # from an old cache: no shape
    features = maplayer.slow_segments(
        [
            TravelTime("A", "1", 180.0, 36.0),  # 20 km/h where 100 is normal: jam
            TravelTime("B", "1", 72.0, 36.0),  # half as fast: slow
            TravelTime("C", "1", 40.0, 36.0),  # nearly normal
            TravelTime("D", "1", 30.0, 12.0),  # slow, but 18 s: a traffic light
            TravelTime("E", "1", 180.0, None),  # no normal travel time
            TravelTime("F", "1", 180.0, 36.0),
        ],
        matches,
    )
    assert [f["properties"] for f in features] == [
        {"kind": "jam", "delay_s": 144, "kph": 20},
        {"kind": "slow", "delay_s": 36, "kph": 50},
    ]


def test_geojson_with_ids_and_gzip():
    raw, compressed = maplayer.geojson(maplayer.measures([_measure("roadClosed")]))
    assert gzip.decompress(compressed) == raw
    data = json.loads(raw)
    assert data["type"] == "FeatureCollection"
    assert data["features"][0]["id"] == 0
    assert data["features"][0]["properties"]["whole_road"] is True


def test_incidents_as_points():
    from homemaps_traffic.datex3 import Incident

    features = maplayer.incidents(
        [Incident("A", "accident", (52.1, 5.1), 141.0, datetime(2026, 9, 22, 14, tzinfo=UTC))]
    )
    assert features == [
        {
            "type": "Feature",
            "properties": {"kind": "accident", "bearing": 141.0, "since": "2026-09-22T14:00:00Z"},
            "geometry": {"type": "Point", "coordinates": [5.1, 52.1]},
        }
    ]


def test_temporary_speed_limits_over_the_route_shape():
    now = datetime(2026, 9, 22, 12, 0, tzinfo=UTC)
    shape = ("wsjjbBovqwH_qfP~s~L",)
    limit = TemporarySpeedLimit(
        "W",
        "1",
        30,
        (((52.0, 5.0), (52.1, 5.1)),),
        "roadMaintenance",
        (
            (datetime(2026, 9, 1, tzinfo=UTC), datetime(2026, 9, 10, tzinfo=UTC)),
            (datetime(2026, 9, 20, tzinfo=UTC), datetime(2026, 9, 30, 14, tzinfo=UTC)),
        ),
    )
    features = maplayer.speed_limits(
        [(limit, Match(((1, 1000.0, 1),), 1000.0, shape)), (limit, Match((), 0.0))],
        now,
    )
    # Without a shape (old cache) it cannot go on the route: dropped.
    assert len(features) == 1
    assert features[0]["properties"] == {
        "kind": "speed_limit",
        "kph": 30,
        "cause": "roadMaintenance",
        # The end of the current window, not of the first one.
        "until": "2026-09-30T14:00:00Z",
    }
    # The route shape, not NDW's own line.
    assert features[0]["geometry"]["coordinates"] == [[5.1214, 52.0907], [4.8922, 52.3731]]
