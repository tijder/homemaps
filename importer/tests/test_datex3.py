from datetime import UTC, datetime
from pathlib import Path

from homemaps_traffic import datex3

FIXTURES = Path(__file__).parent / "fixtures"


def test_meetlocaties():
    with open(FIXTURES / "meetlocaties.xml", "rb") as stroom:
        locaties = list(datex3.lees_meetlocaties(stroom))
    assert [locatie.sleutel for locatie in locaties] == ["SITE_A@27", "SITE_B@3"]
    assert locaties[0].punten == ((52.389347, 4.818521), (52.389328, 4.794803))
    # Twee deellijnen worden één reeks punten, in volgorde.
    assert len(locaties[1].punten) == 4


def test_reistijden_slaat_onbruikbare_metingen_over():
    with open(FIXTURES / "reistijden.xml", "rb") as stroom:
        reistijden = {reistijd.id: reistijd for reistijd in datex3.lees_reistijden(stroom)}
    # B: dataError, C: nul waarnemingen.
    assert set(reistijden) == {"SITE_A", "SITE_D"}
    assert reistijden["SITE_A"].seconden == 113.76
    assert reistijden["SITE_A"].normaal_seconden == 60.0
    assert reistijden["SITE_D"].normaal_seconden is None


def _afsluitingen(nu):
    with open(FIXTURES / "afsluitingen.xml", "rb") as stroom:
        return {afsluiting.id: afsluiting for afsluiting in datex3.lees_afsluitingen(stroom, nu)}


def test_afsluitingen_overdag():
    actief = _afsluitingen(datetime(2026, 9, 21, 12, 0, tzinfo=UTC))
    # Niet: VOORBIJ (afgelopen), RIJSTROOK (geen afsluiting), NACHT (buiten het
    # venster), VRACHT (geldt niet voor auto's).
    assert set(actief) == {"ACTIEF"}
    assert len(actief["ACTIEF"].punten) == 3
    assert not actief["ACTIEF"].hele_weg


def test_afsluitingen_in_het_nachtvenster():
    actief = _afsluitingen(datetime(2026, 9, 21, 23, 0, tzinfo=UTC))
    assert set(actief) == {"ACTIEF", "NACHT"}
    assert actief["NACHT"].hele_weg


def test_tijd_met_nanoseconden():
    assert datex3._tijd("2026-09-15T17:40:18.057252991Z") == datetime(
        2026, 9, 15, 17, 40, 18, 57252, tzinfo=UTC
    )
