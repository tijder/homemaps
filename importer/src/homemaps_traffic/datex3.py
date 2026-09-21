"""De drie NDW-feeds (DATEX II v3) die de importer gebruikt, streamend gelezen.

De configuratie van de meetlocaties is uitgepakt ruim 100 MB; alles gaat daarom
via iterparse en elk afgehandeld element wordt direct weer losgelaten.
"""

import gzip
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime
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


def lees_afsluitingen(stroom: BinaryIO, nu: datetime | None = None) -> Iterator[Afsluiting]:
    nu = nu or datetime.now(UTC)
    for record in _records(stroom, "situationRecord"):
        soort = _eerste(record, "roadOrCarriagewayOrLaneManagementType")
        if soort is None or soort.text not in AFSLUITTYPES:
            continue
        # Een afsluiting voor alleen vrachtverkeer is er voor de auto niet.
        if _eerste(record, "vehicleType") is not None:
            continue
        if not _geldig(record, nu):
            continue
        punten: list[Punt] = []
        for lijn in _vind(record, "posList"):
            punten.extend(_punten(lijn.text or ""))
        if len(punten) >= 2:
            yield Afsluiting(
                record.attrib["id"],
                record.attrib.get("version", ""),
                tuple(punten),
                soort.text == "roadClosed",
            )
