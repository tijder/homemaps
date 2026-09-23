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


def test_maatregelen_voor_de_kaart():
    middag = datetime(2026, 9, 21, 12, 0, tzinfo=UTC)
    with open(FIXTURES / "afsluitingen.xml", "rb") as stroom:
        maatregelen = {m.id: m for m in datex3.lees_maatregelen(stroom, middag)}
    # Ook de rijstrook en de vrachtafsluiting: wat ermee gebeurt beslist de kaartlaag.
    assert set(maatregelen) == {"ACTIEF", "RIJSTROOK", "VRACHT"}
    assert maatregelen["ACTIEF"].sluit_af
    assert maatregelen["ACTIEF"].eind == datetime(2026, 11, 12, 15, 0, tzinfo=UTC)
    assert not maatregelen["RIJSTROOK"].sluit_af
    assert maatregelen["VRACHT"].alleen_vracht and not maatregelen["VRACHT"].sluit_af


def test_meldingen_ongeval_en_pech_geldig_nu():
    nu = datetime(2026, 9, 22, 15, 0, tzinfo=UTC)
    with open(FIXTURES / "meldingen.xml", "rb") as stroom:
        meldingen = {m.id: m for m in datex3.lees_meldingen(stroom, nu)}
    # VOORBIJ is afgelopen; VERGETEN is al dagen niet bijgewerkt. LANG staat er
    # al twee dagen, maar is net nog bijgewerkt. ONZEKER is niet bevestigd.
    assert set(meldingen) == {"ONGEVAL", "PECH", "LANG", "BEVESTIGD"}
    assert meldingen["ONGEVAL"].soort == "ongeval"
    assert meldingen["ONGEVAL"].punt == (52.1, 5.1)
    assert meldingen["ONGEVAL"].koers == 141
    assert meldingen["PECH"].soort == "pech"
    assert meldingen["PECH"].koers is None


def test_geplande_afsluitingen_met_hun_vensters():
    van = datetime(2026, 9, 22, 12, 0, tzinfo=UTC)
    tot = datetime(2026, 9, 30, 12, 0, tzinfo=UTC)
    with open(FIXTURES / "planning.xml", "rb") as stroom:
        gepland = {a.id: a for a in datex3.lees_geplande_afsluitingen(stroom, van, tot)}
    # VOLGEND_JAAR valt buiten de week.
    assert set(gepland) == {"NACHTEN", "WEEKEND"}
    # Van de drie nachten telt alleen die in de week; de vorige is voorbij.
    assert gepland["NACHTEN"].vensters == (
        (datetime(2026, 9, 23, 20, tzinfo=UTC), datetime(2026, 9, 24, 4, tzinfo=UTC)),
    )
    # Zonder validPeriods: één venster van begin tot eind.
    assert gepland["WEEKEND"].vensters == (
        (datetime(2026, 9, 26, 6, tzinfo=UTC), datetime(2026, 9, 27, 20, tzinfo=UTC)),
    )
    assert gepland["WEEKEND"].hele_weg


def _snelheden(van, tot):
    with open(FIXTURES / "snelheden.xml", "rb") as stroom:
        return {s.id: s for s in datex3.lees_snelheden(stroom, van, tot)}


def test_tijdelijke_snelheden_overdag():
    middag = datetime(2026, 9, 22, 12, 0, tzinfo=UTC)
    snelheden = _snelheden(middag, middag)
    # Niet: NACHT (pas vanavond), VRACHT (alleen vracht), ADVIES (geen plicht),
    # VOORBIJ (afgelopen), GEEN_SNELHEID (een rijstrookafsluiting).
    assert set(snelheden) == {"WERK"}
    werk = snelheden["WERK"]
    assert werk.kmu == 30
    assert werk.sleutel == "WERK@3"
    assert werk.oorzaak == "roadMaintenance"
    # Twee deellijnen: in volgorde, en als één reeks punten om te matchen.
    assert len(werk.lijnen) == 2
    assert werk.punten[0] == (53.29151, 6.196199) and werk.punten[-1] == (53.29539, 6.19573)
    assert werk.geldt(middag)
    assert not werk.geldt(datetime(2026, 10, 10, tzinfo=UTC))


def test_tijdelijke_snelheden_vooruit_en_venster():
    # Met twee uur vooruit (zoals de planningsfeed): de nacht telt mee, maar
    # geldt pas vanaf acht uur.
    van = datetime(2026, 9, 22, 19, 0, tzinfo=UTC)
    snelheden = _snelheden(van, datetime(2026, 9, 22, 21, 0, tzinfo=UTC))
    assert set(snelheden) == {"WERK", "NACHT"}
    nacht = snelheden["NACHT"]
    assert nacht.kmu == 70
    assert not nacht.geldt(van)
    assert nacht.geldt(datetime(2026, 9, 22, 23, 0, tzinfo=UTC))


def test_open_bruggen():
    nu = datetime(2026, 9, 22, 20, 0, tzinfo=UTC)
    with open(FIXTURES / "actueel_beeld.xml", "rb") as stroom:
        bruggen = {b.id: b for b in datex3.lees_bruggen(stroom, nu)}
    # Niet: GEPLAND (nog niet bezig), VOORBIJ (afgelopen), GEEN_BRUG.
    assert set(bruggen) == {"OPEN", "DICHTGAAN"}
    assert bruggen["OPEN"].punt == (53.07374, 5.335099)
