"""De NDW-feeds (DATEX II v3) die de importer gebruikt, streamend gelezen.

De configuratie van de meetlocaties is uitgepakt ruim 100 MB; alles gaat daarom
via iterparse en elk afgehandeld element wordt direct weer losgelaten.
"""

import gzip
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import BinaryIO
from xml.etree.ElementTree import Element, iterparse

Punt = tuple[float, float]  # (lat, lon)

XSI_TYPE = "{http://www.w3.org/2001/XMLSchema-instance}type"
AFSLUITTYPES = {"carriagewayClosures", "roadClosed"}


def _naam(element: Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _vind(element: Element, naam: str) -> Iterator[Element]:
    return (kind for kind in element.iter() if _naam(kind) == naam)


def _eerste(element: Element, naam: str) -> Element | None:
    return next(_vind(element, naam), None)


def _punten(poslist: str) -> list[Punt]:
    getallen = [float(deel) for deel in poslist.split()]
    return list(zip(getallen[0::2], getallen[1::2], strict=True))


def _records(stroom: BinaryIO, naam: str) -> Iterator[Element]:
    """Geeft elk element `naam` zodra het compleet is, en ruimt het daarna op."""
    wortel = None
    for gebeurtenis, element in iterparse(stroom, events=("start", "end")):
        if gebeurtenis == "start":
            if wortel is None:
                wortel = element
            continue
        if _naam(element) == naam:
            yield element
            element.clear()
            # De ouder houdt anders 67.000 lege hulzen vast.
            wortel.clear()


def open_feed(pad_of_stroom) -> BinaryIO:
    return gzip.open(pad_of_stroom, "rb")


@dataclass(frozen=True)
class Meetlocatie:
    id: str
    versie: str
    punten: tuple[Punt, ...]

    @property
    def sleutel(self) -> str:
        return f"{self.id}@{self.versie}"


def lees_meetlocaties(stroom: BinaryIO) -> Iterator[Meetlocatie]:
    for site in _records(stroom, "measurementSite"):
        punten: list[Punt] = []
        for lijn in _vind(site, "posList"):
            punten.extend(_punten(lijn.text or ""))
        if len(punten) >= 2:
            yield Meetlocatie(site.attrib["id"], site.attrib.get("version", ""), tuple(punten))


@dataclass(frozen=True)
class Reistijd:
    id: str
    versie: str
    seconden: float
    normaal_seconden: float | None

    @property
    def sleutel(self) -> str:
        return f"{self.id}@{self.versie}"


def _duur(basis: Element, naam: str) -> float | None:
    veld = _eerste(basis, naam)
    if veld is None or _eerste(veld, "dataError") is not None:
        return None
    if veld.attrib.get("numberOfInputValuesUsed") == "0":
        return None
    duur = _eerste(veld, "duration")
    if duur is None or not duur.text:
        return None
    waarde = float(duur.text)
    return waarde if waarde > 0 else None


def lees_reistijden(stroom: BinaryIO) -> Iterator[Reistijd]:
    for meting in _records(stroom, "siteMeasurements"):
        verwijzing = _eerste(meting, "measurementSiteReference")
        seconden = _duur(meting, "travelTime")
        if verwijzing is None or seconden is None:
            continue
        yield Reistijd(
            verwijzing.attrib["id"],
            verwijzing.attrib.get("version", ""),
            seconden,
            _duur(meting, "normallyExpectedTravelTime"),
        )


@dataclass(frozen=True)
class Afsluiting:
    id: str
    versie: str
    punten: tuple[Punt, ...]
    hele_weg: bool  # roadClosed: beide richtingen, ook bij gescheiden rijbanen

    @property
    def sleutel(self) -> str:
        return f"{self.id}@{self.versie}"


def _tijd(tekst: str | None) -> datetime | None:
    if not tekst:
        return None
    # NDW levert nanoseconden; fromisoformat kan er hooguit zes aan.
    hoofd, _, rest = tekst.partition(".")
    if rest:
        cijfers = "".join(teken for teken in rest if teken.isdigit())
        zone = rest[len(cijfers) :]
        tekst = f"{hoofd}.{cijfers[:6]}{zone}"
    tijd = datetime.fromisoformat(tekst.replace("Z", "+00:00"))
    return tijd if tijd.tzinfo else tijd.replace(tzinfo=UTC)


def _geldig(record: Element, nu: datetime) -> bool:
    specificatie = _eerste(record, "validityTimeSpecification")
    if specificatie is None:
        return True
    begin = _tijd(getattr(_eerste(specificatie, "overallStartTime"), "text", None))
    eind = _tijd(getattr(_eerste(specificatie, "overallEndTime"), "text", None))
    if begin and nu < begin or eind and nu > eind:
        return False
    # Met validPeriod's geldt de maatregel alleen binnen een van die vensters
    # (nachtafsluitingen). Herhalende dagdelen komen in de feed niet voor.
    perioden = list(_vind(specificatie, "validPeriod"))
    if not perioden:
        return True
    for periode in perioden:
        start = _tijd(getattr(_eerste(periode, "startOfPeriod"), "text", None))
        stop = _tijd(getattr(_eerste(periode, "endOfPeriod"), "text", None))
        if (start is None or start <= nu) and (stop is None or nu <= stop):
            return True
    return False


@dataclass(frozen=True)
class Maatregel:
    """Een geldige maatregel op de weg, zoals de kaart hem toont. Een afsluiting
    voor de routeplanner is er een bijzonder geval van (zie `als_afsluiting`)."""

    id: str
    versie: str
    soort: str  # roadOrCarriagewayOrLaneManagementType
    lijnen: tuple[tuple[Punt, ...], ...]  # één per posList, in volgorde
    alleen_vracht: bool
    rijbaan: str | None  # mainCarriageway, exitSlipRoad, ...
    oorzaak: str | None  # causeType
    eind: datetime | None
    stroken_open: int | None

    @property
    def sleutel(self) -> str:
        return f"{self.id}@{self.versie}"

    @property
    def sluit_af(self) -> bool:
        return self.soort in AFSLUITTYPES and not self.alleen_vracht

    def als_afsluiting(self) -> Afsluiting:
        return Afsluiting(
            self.id,
            self.versie,
            tuple(punt for lijn in self.lijnen for punt in lijn),
            self.soort == "roadClosed",
        )


def _tekst(element: Element, naam: str) -> str | None:
    """De eerste `naam` met tekst: DATEX nest soms gelijknamige elementen
    (`carriageway` in `carriageway`)."""
    for kind in _vind(element, naam):
        if kind.text and kind.text.strip():
            return kind.text.strip()
    return None


def lees_maatregelen(stroom: BinaryIO, nu: datetime | None = None) -> Iterator[Maatregel]:
    nu = nu or datetime.now(UTC)
    for record in _records(stroom, "situationRecord"):
        soort = _tekst(record, "roadOrCarriagewayOrLaneManagementType")
        if soort is None or not _geldig(record, nu):
            continue
        lijnen = tuple(
            tuple(punten)
            for lijn in _vind(record, "posList")
            if len(punten := _punten(lijn.text or "")) >= 2
        )
        if not lijnen:
            continue
        specificatie = _eerste(record, "validityTimeSpecification")
        stroken = _tekst(record, "numberOfOperationalLanes")
        yield Maatregel(
            record.attrib["id"],
            record.attrib.get("version", ""),
            soort,
            lijnen,
            # Een afsluiting voor alleen vrachtverkeer is er voor de auto niet.
            _eerste(record, "vehicleType") is not None,
            _tekst(record, "carriageway"),
            _tekst(record, "causeType"),
            _tijd(_tekst(specificatie, "overallEndTime")) if specificatie is not None else None,
            int(stroken) if stroken and stroken.isdigit() else None,
        )


def lees_afsluitingen(stroom: BinaryIO, nu: datetime | None = None) -> Iterator[Afsluiting]:
    for maatregel in lees_maatregelen(stroom, nu):
        if maatregel.sluit_af:
            yield maatregel.als_afsluiting()


# Van het xsi:type van een SRTI-melding naar wat de app toont.
MELDINGSOORTEN = {
    "Accident": "ongeval",
    "VehicleObstruction": "pech",
    "GeneralObstruction": "obstakel",
}


# Een melding zonder eind blijft staan tot de bron hem intrekt. Pijlwagens en
# botsabsorbers van wegwerkbedrijven (ook als VehicleObstruction) worden dat
# lang niet altijd: ze staan er dan dagen, soms weken. Wat zo lang niet is
# bijgewerkt, is niet meer te vertrouwen. Pech en ongevallen van NDW zelf zijn
# er meestal binnen een paar uur weer af.
MELDING_VERLOOPT = timedelta(hours=12)


@dataclass(frozen=True)
class Melding:
    """Een veiligheidsmelding (SRTI): ongeval, pechgeval of iets op de weg, op
    één punt."""

    id: str
    soort: str
    punt: Punt
    koers: float | None
    sinds: datetime | None


def lees_meldingen(stroom: BinaryIO, nu: datetime | None = None) -> Iterator[Melding]:
    nu = nu or datetime.now(UTC)
    for record in _records(stroom, "situationRecord"):
        soort = MELDINGSOORTEN.get(record.attrib.get(XSI_TYPE, "").rsplit(":", 1)[-1])
        if soort is None or not _geldig(record, nu):
            continue
        lat, lon = _tekst(record, "latitude"), _tekst(record, "longitude")
        if lat is None or lon is None:
            continue
        koers = _tekst(record, "bearing")
        specificatie = _eerste(record, "validityTimeSpecification")
        sinds = (
            _tijd(_tekst(specificatie, "overallStartTime")) if specificatie is not None else None
        )
        bijgewerkt = _tijd(_tekst(record, "situationRecordVersionTime")) or sinds
        if bijgewerkt and nu - bijgewerkt > MELDING_VERLOOPT:
            continue
        yield Melding(
            record.attrib["id"],
            soort,
            (float(lat), float(lon)),
            float(koers) if koers else None,
            sinds,
        )


@dataclass(frozen=True)
class GeplandeAfsluiting:
    """Een afsluiting uit de planningsfeed, met de vensters waarin hij geldt."""

    id: str
    lijnen: tuple[tuple[Punt, ...], ...]
    hele_weg: bool
    rijbaan: str | None
    vensters: tuple[tuple[datetime, datetime | None], ...]  # (begin, eind)


def _vensters(
    record: Element, van: datetime, tot: datetime
) -> list[tuple[datetime, datetime | None]]:
    """De geldigheidsvensters die [van, tot] raken. Zonder validPeriods is het
    één venster van begin tot eind."""
    specificatie = _eerste(record, "validityTimeSpecification")
    if specificatie is None:
        return []
    begin = _tijd(_tekst(specificatie, "overallStartTime"))
    eind = _tijd(_tekst(specificatie, "overallEndTime"))
    perioden = [
        (_tijd(_tekst(p, "startOfPeriod")), _tijd(_tekst(p, "endOfPeriod")))
        for p in _vind(specificatie, "validPeriod")
    ] or [(begin, eind)]
    uit = []
    for start, stop in perioden:
        start = start or begin
        stop = stop or eind
        if start is None or start > tot or (stop is not None and stop < van):
            continue
        uit.append((start, stop))
    return uit


def lees_geplande_afsluitingen(
    stroom: BinaryIO, van: datetime, tot: datetime
) -> Iterator[GeplandeAfsluiting]:
    """Afsluitingen (voor auto's) die ergens tussen [van] en [tot] gelden."""
    for record in _records(stroom, "situationRecord"):
        soort = _tekst(record, "roadOrCarriagewayOrLaneManagementType")
        if soort not in AFSLUITTYPES or _eerste(record, "vehicleType") is not None:
            continue
        vensters = _vensters(record, van, tot)
        if not vensters:
            continue
        lijnen = tuple(
            tuple(punten)
            for lijn in _vind(record, "posList")
            if len(punten := _punten(lijn.text or "")) >= 2
        )
        if lijnen:
            yield GeplandeAfsluiting(
                record.attrib["id"],
                lijnen,
                soort == "roadClosed",
                _tekst(record, "carriageway"),
                tuple(vensters),
            )


@dataclass(frozen=True)
class TijdelijkeSnelheid:
    """Een tijdelijke maximumsnelheid (bij werk of een evenement), met de
    vensters waarin hij geldt."""

    id: str
    versie: str
    kmu: int
    lijnen: tuple[tuple[Punt, ...], ...]
    oorzaak: str | None
    vensters: tuple[tuple[datetime, datetime | None], ...]  # (begin, eind)

    @property
    def sleutel(self) -> str:
        return f"{self.id}@{self.versie}"

    @property
    def punten(self) -> tuple[Punt, ...]:
        return tuple(punt for lijn in self.lijnen for punt in lijn)

    def geldt(self, nu: datetime) -> bool:
        return any(begin <= nu and (eind is None or nu <= eind) for begin, eind in self.vensters)


def lees_snelheden(stroom: BinaryIO, van: datetime, tot: datetime) -> Iterator[TijdelijkeSnelheid]:
    """Tijdelijke maximumsnelheden die ergens tussen [van] en [tot] gelden, uit
    de feed met maximumsnelheden of de planningsfeed (dezelfde records). Wat
    alleen voor sommige voertuigen geldt, of alleen een advies is, valt af."""
    for record in _records(stroom, "situationRecord"):
        if not record.attrib.get(XSI_TYPE, "").endswith("SpeedManagement"):
            continue
        limiet = _tekst(record, "temporarySpeedLimit")
        naleving = _tekst(record, "complianceOption")
        if (
            limiet is None
            or _eerste(record, "vehicleType") is not None
            or (naleving is not None and naleving != "mandatory")
        ):
            continue
        try:
            kmu = round(float(limiet))
        except ValueError:
            continue
        if kmu <= 0:
            continue
        vensters = _vensters(record, van, tot)
        if not vensters:
            continue
        lijnen = tuple(
            tuple(punten)
            for lijn in _vind(record, "posList")
            if len(punten := _punten(lijn.text or "")) >= 2
        )
        if lijnen:
            yield TijdelijkeSnelheid(
                record.attrib["id"],
                record.attrib.get("version", ""),
                kmu,
                lijnen,
                _tekst(record, "causeType"),
                tuple(vensters),
            )


BRUG_BEZIG = {"beingImplemented", "implemented", "beingTerminated"}


@dataclass(frozen=True)
class Brug:
    """Een brug die nu open staat (voor de scheepvaart): dicht voor het verkeer."""

    id: str
    punt: Punt


def lees_bruggen(stroom: BinaryIO, nu: datetime | None = None) -> Iterator[Brug]:
    """Uit `actueel_beeld`: bruggen die nu open zijn. Een geplande opening
    (`approved`) telt pas als hij bezig is: opengaan, open, of weer dichtgaan --
    in alle drie staat het verkeer stil."""
    nu = nu or datetime.now(UTC)
    for record in _records(stroom, "situationRecord"):
        soort = _tekst(record, "generalNetworkManagementType") or ""
        if (
            not soort.startswith("bridge")
            or _tekst(record, "operatorActionStatus") not in BRUG_BEZIG
            or not _geldig(record, nu)
        ):
            continue
        lat, lon = _tekst(record, "latitude"), _tekst(record, "longitude")
        if lat is not None and lon is not None:
            yield Brug(record.attrib["id"], (float(lat), float(lon)))
