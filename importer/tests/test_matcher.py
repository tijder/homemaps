import json
import urllib.error

import pytest

from homemaps_traffic.matcher import Match, MatchCache, Valhalla, _bedekt, _ontdubbel


class NepValhalla(Valhalla):
    def __init__(self, antwoorden):
        super().__init__("http://nep")
        self.antwoorden = antwoorden
        self.verzoeken = []

    def _vraag(self, pad, body=None):
        self.verzoeken.append((pad, body))
        antwoord = self.antwoorden(pad, body)
        if isinstance(antwoord, Exception):
            raise antwoord
        return antwoord


def _route(km):
    return {"trip": {"summary": {"length": km}, "legs": [{"shape": "x"}]}}


def _spoor(*ids):
    return {"edges": [{"id": i, "length": 0.1, "way_id": 7} for i in ids]}


def test_match_en_omweg():
    valhalla = NepValhalla(lambda pad, _: _route(1.2) if pad == "/route" else _spoor(1, 2, 2, 3))
    match = valhalla.match([(52.0, 5.0), (52.0, 5.0146)])  # ~1 km hemelsbreed
    assert [edge[0] for edge in match.edges] == [1, 2, 3]  # dubbele edge samengevoegd
    assert match.lengte_m == pytest.approx(1200)

    omweg = NepValhalla(lambda pad, _: _route(5.0) if pad == "/route" else _spoor(1))
    assert omweg.match([(52.0, 5.0), (52.0, 5.0146)]) is None


def test_lange_lijn_gaat_in_blokken_van_twintig():
    valhalla = NepValhalla(lambda pad, _: _route(0.5) if pad == "/route" else _spoor(1))
    valhalla.match([(52.0 + i * 0.001, 5.0) for i in range(45)])
    routes = [body for pad, body in valhalla.verzoeken if pad == "/route"]
    assert [len(body["locations"]) for body in routes] == [20, 20, 7]
    # Elk blok begint waar het vorige eindigde.
    assert routes[1]["locations"][0] == routes[0]["locations"][-1]


def test_afrit_die_op_de_hoofdrijbaan_begint():
    """Het eerste punt ligt net voorbij waar de afrit afbuigt: routeren geeft een
    omweg. De map-match pakt het randje hoofdrijbaan (A) en de afrit (B); alleen
    de afrit gaat dicht."""
    lijn = [(52.0, 5.0), (52.0, 5.001), (52.0, 5.0084)]  # ~570 m

    def antwoorden(pad, body):
        if pad == "/route":
            return _route(29.5)
        assert body["shape_match"] == "map_snap"
        return {
            "edges": [
                {"id": 1, "length": 0.03, "way_id": 6, "source_percent_along": 0.9},
                {"id": 2, "length": 0.54, "way_id": 7},
            ],
            "shape": "vorm",
        }

    valhalla = NepValhalla(antwoorden)
    assert valhalla.match(lijn) is None  # zonder alleen_bedekt: geen terugval
    match = valhalla.match(lijn, alleen_bedekt=True)
    assert [edge[0] for edge in match.edges] == [2]
    assert match.vorm == ("vorm",)


def test_map_match_die_maar_een_flard_vindt_telt_niet():
    def antwoorden(pad, _):
        if pad == "/route":
            return _route(29.5)
        return {"edges": [{"id": 1, "length": 0.05, "way_id": 7}], "shape": "v"}

    assert NepValhalla(antwoorden).match([(52.0, 5.0), (52.0, 5.0146)], alleen_bedekt=True) is None


def test_bedekt():
    def match(n):
        return Match(tuple((i, 10.0, 7) for i in range(n)), 0.0)

    ids = lambda m: [edge[0] for edge in m.edges]  # noqa: E731
    # Randjes eraf, het midden blijft altijd.
    assert ids(_bedekt(match(4), [0.1, 1.0, 1.0, 0.49])) == [1, 2]
    assert ids(_bedekt(match(3), [0.5, 0.2, 0.6])) == [0, 1, 2]
    # Kort werk midden op één edge: die blijft.
    assert ids(_bedekt(match(1), [0.3])) == [0]
    # Twee randjes: de grootste blijft.
    assert ids(_bedekt(match(2), [0.2, 0.4])) == [1]


def test_bedekking_telt_op_over_een_leggrens():
    """Twee punten op dezelfde edge: de legs raken elkaar midden op edge 1, die
    daardoor voor 0,2 + 0,5 bedekt is en blijft; los geteld
    zou edge 2 (0,3) het winnen."""

    def antwoorden(pad, body):
        if pad == "/route":
            return _route(0.3)
        if body["encoded_polyline"] == "x":
            antwoorden.leg += 1
        if antwoorden.leg == 1:
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

    antwoorden.leg = 0
    punten = [(52.0 + i * 0.001, 5.0) for i in range(21)]  # twee blokken
    match = NepValhalla(antwoorden).match(punten, alleen_bedekt=True)
    assert [edge[0] for edge in match.edges] == [1]


def test_ontdubbel():
    assert _ontdubbel([(1, 1), (2, 2), (2, 2), (3, 3)]) == [(1, 1), (2, 2), (3, 3)]


def test_geen_route_is_definitief_maar_een_weggevallen_verbinding_niet(tmp_path):
    fout400 = urllib.error.HTTPError("u", 400, "geen route", {}, None)

    def antwoorden(pad, body):
        lat = body["locations"][0]["lat"] if pad == "/route" else None
        if lat == 1.0:
            return fout400
        if lat == 2.0:
            return ConnectionResetError()
        return _route(0.1) if pad == "/route" else _spoor(9)

    cache = MatchCache(tmp_path / "c.json", tileset=5)
    items = {
        "a": ((1.0, 1.0), (1.0, 1.001)),
        "b": ((2.0, 1.0), (2.0, 1.001)),
        "c": ((3.0, 1.0), (3.0, 1.001)),
    }
    cache.vul_aan(NepValhalla(antwoorden), items, draden=2)
    assert cache.matches["a"] is None  # bekend onmatchbaar
    assert "b" not in cache.matches  # volgende ronde opnieuw
    assert isinstance(cache.matches["c"], Match)

    cache.bewaar()
    assert MatchCache(tmp_path / "c.json", tileset=5).matches.keys() == {"a", "c"}
    # Een andere tileset: alles vervalt.
    assert MatchCache(tmp_path / "c.json", tileset=6).matches == {}
    # Een andere matchregel ook.
    assert MatchCache(tmp_path / "c.json", tileset=5, alleen_bedekt=True).matches == {}


def test_match_van_voor_de_routevorm_wordt_opnieuw_gematcht(tmp_path):
    pad = tmp_path / "c.json"
    oud = {"e": [[1, 100.0, 7]], "l": 100.0}
    pad.write_text(json.dumps({"tileset": 5, "matches": {"oud": oud, "geen": None}}))
    # "geen" blijft bekend onmatchbaar; "oud" moet terug naar Valhalla.
    assert MatchCache(pad, tileset=5).matches == {"geen": None}
    nieuw = Match(((1, 100.0, 7),), 100.0, ("abc",))
    assert Match.uit_json(nieuw.naar_json()) == nieuw
