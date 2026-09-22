import gzip
import json
from datetime import UTC, datetime

from homemaps_traffic import kaartlaag
from homemaps_traffic.datex3 import Maatregel, Reistijd, TijdelijkeSnelheid
from homemaps_traffic.matcher import Match


def _maatregel(soort, vracht=False):
    return Maatregel(
        "M",
        "1",
        soort,
        (((52.0, 5.0), (52.1, 5.1)), ((52.1, 5.1), (52.2, 5.2))),
        vracht,
        "exitSlipRoad",
        "roadMaintenance",
        datetime(2026, 10, 22, 18, 0, tzinfo=UTC),
        None,
    )


def test_maatregelen_dicht_en_werk():
    features = kaartlaag.maatregelen(
        [
            _maatregel("carriagewayClosures"),
            _maatregel("laneClosures"),
            _maatregel("carriagewayClosures", vracht=True),
            _maatregel("useOfSpecifiedLanesOrCarriagewaysAllowed"),
        ]
    )
    assert [f["properties"]["soort"] for f in features] == ["dicht", "werk"]
    dicht = features[0]
    assert dicht["properties"] == {
        "soort": "dicht",
        "hele_weg": False,
        "rijbaan": "exitSlipRoad",
        "oorzaak": "roadMaintenance",
        "tot": "2026-10-22T18:00:00Z",
    }
    # Twee posLists blijven twee lijnen, in GeoJSON-volgorde (lon, lat).
    assert dicht["geometry"]["type"] == "MultiLineString"
    assert dicht["geometry"]["coordinates"][0] == [[5.0, 52.0], [5.1, 52.1]]


def test_decodeer_zes_decimalen():
    # Utrecht -> Amsterdam, zoals Valhalla hem codeert (ook in de app-test).
    punten = kaartlaag.decodeer("wsjjbBovqwH_qfP~s~L")
    assert punten == [(52.0907, 5.1214), (52.3731, 4.8922)]


def test_alleen_duidelijk_trage_stukken():
    vorm = ("wsjjbBovqwH_qfP~s~L",)
    matches = {f"{naam}@1": Match(((1, 1000.0, 1),), 1000.0, vorm) for naam in "ABCDE"}
    matches["F@1"] = Match(((1, 1000.0, 1),), 1000.0)  # uit een oude cache: geen vorm
    features = kaartlaag.trage_stukken(
        [
            Reistijd("A", "1", 180.0, 36.0),  # 20 km/u waar 100 normaal is: file
            Reistijd("B", "1", 72.0, 36.0),  # half zo snel: traag
            Reistijd("C", "1", 40.0, 36.0),  # vrijwel normaal
            Reistijd("D", "1", 30.0, 12.0),  # traag, maar 18 s: een stoplicht
            Reistijd("E", "1", 180.0, None),  # geen normale reistijd
            Reistijd("F", "1", 180.0, 36.0),
        ],
        matches,
    )
    assert [f["properties"] for f in features] == [
        {"soort": "file", "vertraging_s": 144, "kmu": 20},
        {"soort": "traag", "vertraging_s": 36, "kmu": 50},
    ]


def test_geojson_met_ids_en_gzip():
    ruw, ingepakt = kaartlaag.geojson(kaartlaag.maatregelen([_maatregel("roadClosed")]))
    assert gzip.decompress(ingepakt) == ruw
    data = json.loads(ruw)
    assert data["type"] == "FeatureCollection"
    assert data["features"][0]["id"] == 0
    assert data["features"][0]["properties"]["hele_weg"] is True


def test_meldingen_als_punten():
    from homemaps_traffic.datex3 import Melding

    features = kaartlaag.meldingen(
        [Melding("A", "ongeval", (52.1, 5.1), 141.0, datetime(2026, 9, 22, 14, tzinfo=UTC))]
    )
    assert features == [
        {
            "type": "Feature",
            "properties": {"soort": "ongeval", "koers": 141.0, "sinds": "2026-09-22T14:00:00Z"},
            "geometry": {"type": "Point", "coordinates": [5.1, 52.1]},
        }
    ]


def test_tijdelijke_snelheden_over_de_routevorm():
    nu = datetime(2026, 9, 22, 12, 0, tzinfo=UTC)
    vorm = ("wsjjbBovqwH_qfP~s~L",)
    snelheid = TijdelijkeSnelheid(
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
    features = kaartlaag.snelheden(
        [(snelheid, Match(((1, 1000.0, 1),), 1000.0, vorm)), (snelheid, Match((), 0.0))],
        nu,
    )
    # Zonder vorm (oude cache) kan hij niet op de route: weg.
    assert len(features) == 1
    assert features[0]["properties"] == {
        "soort": "snelheid",
        "kmu": 30,
        "oorzaak": "roadMaintenance",
        # Het eind van het venster van nu, niet van het eerste.
        "tot": "2026-09-30T14:00:00Z",
    }
    # De routevorm, niet NDW's eigen lijn.
    assert features[0]["geometry"]["coordinates"] == [[5.1214, 52.0907], [4.8922, 52.3731]]
