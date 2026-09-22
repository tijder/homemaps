from datetime import UTC, datetime

from homemaps_traffic import traffictile as tt
from homemaps_traffic.datex3 import Afsluiting, Reistijd, TijdelijkeSnelheid
from homemaps_traffic.main import bereken_afsluitingen, bereken_snelheden, leg_snelheden
from homemaps_traffic.matcher import Match


def test_snelheid_uit_lengte_en_reistijd():
    matches = {"A@1": Match(((100, 600.0, 1), (101, 400.0, 1)), 1000.0)}
    records = bereken_snelheden([Reistijd("A", "1", 72.0, 36.0)], matches)
    # 1000 m in 72 s = 50 km/u; normaal 100 km/u.
    assert set(records) == {100, 101}
    velden = tt.pak_uit(records[100])
    assert velden["overall"] == 25 and velden["breakpoint1"] == 255
    assert 25 < velden["congestion1"] < 40


def test_gedeelde_edge_weegt_naar_lengte():
    matches = {
        "A@1": Match(((100, 900.0, 1),), 900.0),
        "B@1": Match(((100, 100.0, 1),), 100.0),
    }
    records = bereken_snelheden(
        [Reistijd("A", "1", 900 / (100 / 3.6), None), Reistijd("B", "1", 100 / (20 / 3.6), None)],
        matches,
    )
    # Harmonisch: 1000 m in (32,4 + 18) s = 71 km/u -- geen 60 (rekenkundig).
    assert tt.pak_uit(records[100])["overall"] * 2 in (70, 72)


def test_onbekende_en_onmogelijke_metingen_vallen_af():
    matches = {"A@1": Match(((100, 1000.0, 1),), 1000.0), "B@1": None}
    records = bereken_snelheden(
        [
            Reistijd("A", "1", 5.0, None),
            Reistijd("B", "1", 60.0, None),
            Reistijd("C", "9", 60.0, None),
        ],
        matches,
    )
    assert records == {}  # A is 720 km/u, B is onmatchbaar, C staat niet in de cache


def test_afsluiting_neemt_tegenrichting_alleen_mee_op_dezelfde_way():
    matches = {
        "X@1": Match(((1, 100.0, 50), (2, 100.0, 51)), 200.0),
        "X@1#terug": Match(((3, 100.0, 51), (4, 100.0, 99)), 200.0),
    }
    dicht = bereken_afsluitingen([Afsluiting("X", "1", ((0, 0), (1, 1)), False)], matches)
    assert set(dicht) == {1, 2, 3}  # 4 ligt op een eigen rijbaan (way 99)
    assert all(tt.is_afgesloten(waarde) for waarde in dicht.values())
    hele_weg = bereken_afsluitingen([Afsluiting("X", "1", ((0, 0), (1, 1)), True)], matches)
    assert set(hele_weg) == {1, 2, 3, 4}


def test_tijdelijke_snelheid_neemt_tegenrichting_alleen_mee_op_dezelfde_way():
    begin = datetime(2026, 9, 1, tzinfo=UTC)
    snelheid = TijdelijkeSnelheid("W", "1", 30, (((0, 0), (1, 1)),), None, ((begin, None),))
    anders = TijdelijkeSnelheid("G", "1", 70, (((0, 0), (1, 1)),), None, ((begin, None),))
    matches = {
        # Eén rijbaan: terug over dezelfde way.
        "W@1": Match(((1, 100.0, 50), (2, 100.0, 51)), 200.0, ("a",)),
        "W@1#terug": Match(((3, 100.0, 51), (4, 100.0, 50)), 200.0, ("b",)),
        # Gescheiden rijbanen: terug deels over een eigen way.
        "G@1": Match(((5, 100.0, 60),), 100.0, ("c",)),
        "G@1#terug": Match(((6, 100.0, 60), (7, 100.0, 99)), 200.0, ("d",)),
    }
    gelegd = leg_snelheden([snelheid, anders], matches)
    assert [(s.id, m.vorm) for s, m in gelegd] == [
        ("W", ("a",)),
        ("W", ("b",)),
        ("G", ("c",)),
    ]
    # Niet gematcht: valt weg.
    assert leg_snelheden([snelheid], {"W@1": None}) == []
