import json
import urllib.error

import pytest

from homemaps_traffic.matcher import Match, MatchCache, Valhalla, _covered, _dedupe


class FakeValhalla(Valhalla):
    def __init__(self, responses):
        super().__init__("http://fake")
        self.responses = responses
        self.requests = []

    def _request(self, path, body=None):
        self.requests.append((path, body))
        response = self.responses(path, body)
        if isinstance(response, Exception):
            raise response
        return response


def _route(km):
    return {"trip": {"summary": {"length": km}, "legs": [{"shape": "x"}]}}


def _trace(*ids):
    return {"edges": [{"id": i, "length": 0.1, "way_id": 7} for i in ids]}


def test_match_and_detour():
    valhalla = FakeValhalla(lambda path, _: _route(1.2) if path == "/route" else _trace(1, 2, 2, 3))
    match = valhalla.match([(52.0, 5.0), (52.0, 5.0146)])  # ~1 km as the crow flies
    assert [edge[0] for edge in match.edges] == [1, 2, 3]  # duplicate edge merged
    assert match.length_m == pytest.approx(1200)

    detour = FakeValhalla(lambda path, _: _route(5.0) if path == "/route" else _trace(1))
    assert detour.match([(52.0, 5.0), (52.0, 5.0146)]) is None


def test_long_line_goes_in_blocks_of_twenty():
    valhalla = FakeValhalla(lambda path, _: _route(0.5) if path == "/route" else _trace(1))
    valhalla.match([(52.0 + i * 0.001, 5.0) for i in range(45)])
    routes = [body for path, body in valhalla.requests if path == "/route"]
    assert [len(body["locations"]) for body in routes] == [20, 20, 7]
    # Every block starts where the previous one ended.
    assert routes[1]["locations"][0] == routes[0]["locations"][-1]


def test_exit_that_starts_on_the_main_carriageway():
    """The first point lies just past where the exit branches off: routing yields a
    detour. The map match picks up the edge of the main carriageway (A) and the
    exit (B); only the exit is closed."""
    line = [(52.0, 5.0), (52.0, 5.001), (52.0, 5.0084)]  # ~570 m

    def responses(path, body):
        if path == "/route":
            return _route(29.5)
        assert body["shape_match"] == "map_snap"
        return {
            "edges": [
                {"id": 1, "length": 0.03, "way_id": 6, "source_percent_along": 0.9},
                {"id": 2, "length": 0.54, "way_id": 7},
            ],
            "shape": "shape",
        }

    valhalla = FakeValhalla(responses)
    assert valhalla.match(line) is None  # without covered_only: no fallback
    match = valhalla.match(line, covered_only=True)
    assert [edge[0] for edge in match.edges] == [2]
    assert match.shape == ("shape",)


def test_map_match_that_only_finds_a_shred_does_not_count():
    def responses(path, _):
        if path == "/route":
            return _route(29.5)
        return {"edges": [{"id": 1, "length": 0.05, "way_id": 7}], "shape": "v"}

    assert FakeValhalla(responses).match([(52.0, 5.0), (52.0, 5.0146)], covered_only=True) is None


def test_covered():
    def match(n):
        return Match(tuple((i, 10.0, 7) for i in range(n)), 0.0)

    ids = lambda m: [edge[0] for edge in m.edges]  # noqa: E731
    # Edges trimmed off, the middle always stays.
    assert ids(_covered(match(4), [0.1, 1.0, 1.0, 0.49])) == [1, 2]
    assert ids(_covered(match(3), [0.5, 0.2, 0.6])) == [0, 1, 2]
    # Short work in the middle of a single edge: that edge stays.
    assert ids(_covered(match(1), [0.3])) == [0]
    # Two edge bits: the largest stays.
    assert ids(_covered(match(2), [0.2, 0.4])) == [1]


def test_coverage_adds_up_across_a_leg_boundary():
    """Two points on the same edge: the legs meet in the middle of edge 1, which
    is therefore covered for 0.2 + 0.5 and stays; counted separately
    edge 2 (0.3) would win."""

    def responses(path, body):
        if path == "/route":
            return _route(0.3)
        if body["encoded_polyline"] == "x":
            responses.leg += 1
        if responses.leg == 1:
            return {
                "edges": [
                    {
                        "id": 1,
                        "length": 0.02,
                        "source_percent_along": 0.3,
                        "target_percent_along": 0.5,
                    }
                ]
            }
        return {
            "edges": [
                {"id": 1, "length": 0.05, "source_percent_along": 0.5},
                {"id": 2, "length": 0.03, "target_percent_along": 0.3},
            ]
        }

    responses.leg = 0
    points = [(52.0 + i * 0.001, 5.0) for i in range(21)]  # two blocks
    match = FakeValhalla(responses).match(points, covered_only=True)
    assert [edge[0] for edge in match.edges] == [1]


def test_dedupe():
    assert _dedupe([(1, 1), (2, 2), (2, 2), (3, 3)]) == [(1, 1), (2, 2), (3, 3)]


def test_no_route_is_definitive_but_a_dropped_connection_is_not(tmp_path):
    error400 = urllib.error.HTTPError("u", 400, "no route", {}, None)

    def responses(path, body):
        lat = body["locations"][0]["lat"] if path == "/route" else None
        if lat == 1.0:
            return error400
        if lat == 2.0:
            return ConnectionResetError()
        return _route(0.1) if path == "/route" else _trace(9)

    cache = MatchCache(tmp_path / "c.json", tileset=5)
    items = {
        "a": ((1.0, 1.0), (1.0, 1.001)),
        "b": ((2.0, 1.0), (2.0, 1.001)),
        "c": ((3.0, 1.0), (3.0, 1.001)),
    }
    cache.fill(FakeValhalla(responses), items, threads=2)
    assert cache.matches["a"] is None  # known to be unmatchable
    assert "b" not in cache.matches  # again next cycle
    assert isinstance(cache.matches["c"], Match)

    cache.save()
    assert MatchCache(tmp_path / "c.json", tileset=5).matches.keys() == {"a", "c"}
    # A different tileset: everything is discarded.
    assert MatchCache(tmp_path / "c.json", tileset=6).matches == {}
    # A different match rule too.
    assert MatchCache(tmp_path / "c.json", tileset=5, covered_only=True).matches == {}


def test_match_from_before_the_route_shape_is_matched_again(tmp_path):
    path = tmp_path / "c.json"
    old = {"e": [[1, 100.0, 7]], "l": 100.0}
    path.write_text(json.dumps({"tileset": 5, "matches": {"old": old, "none": None}}))
    # "none" stays known to be unmatchable; "old" has to go back to Valhalla.
    assert MatchCache(path, tileset=5).matches == {"none": None}
    new = Match(((1, 100.0, 7),), 100.0, ("abc",))
    assert Match.from_json(new.to_json()) == new
