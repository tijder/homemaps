"""De lus: NDW ophalen, op edges leggen, traffic.tar bijwerken, meten.

Instellingen komen uit de omgeving (de chart zet ze):

  TRAFFIC_TAR        pad naar traffic.tar            (/data/traffic.tar)
  VALHALLA_URL       de Valhalla in dezelfde pod     (http://localhost:8002)
  CACHE_DIR          waar de match-cache mag staan   (/data/importer)
  NDW_URL            basis van de feeds              (https://opendata.ndw.nu)
  INTERVAL_SECONDEN  tussen twee rondes              (300)
  AFSLUITINGEN       "false" zet die feed uit        (true)
  MELDINGEN          "false" zet de SRTI-feed uit    (true)
  PLANNING_SECONDEN  hoe vaak de planningsfeed        (3600; 0 = nooit)
  SNELHEDEN          "false" zet tijdelijke maximumsnelheden uit (true)
  OSM_PBF            het OSM-bestand van de tileset    (/data/bron/gebied.osm.pbf)
  MSI_SECONDEN       hoe vaak de matrixborden          (60; 0 = nooit)
  BRUGGEN            "false" zet open bruggen uit      (true)
  METRICS_POORT      /metrics en /verkeer.geojson    (9100)
"""

import io
import logging
import os
import sys
import threading
import time
import urllib.request
import zipfile
import zlib
from collections import defaultdict
from collections.abc import Iterable
from datetime import UTC, datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socket import AF_INET6
from xml.etree.ElementTree import ParseError

from . import datex3, kaartlaag, msi, osmregels
from . import traffictile as tt
from .matcher import Match, MatchCache, Valhalla
from .tarindex import TrafficTar

log = logging.getLogger("homemaps_traffic")

SRTI = "veiligheidsgerelateerde_berichten_srti.xml.gz"
PLANNING = "planningsfeed_wegwerkzaamheden_en_evenementen.xml.gz"
SNELHEDEN = "tijdelijke_verkeersmaatregelen_maximum_snelheden.xml.gz"
ACTUEEL = "actueel_beeld.xml.gz"
MSI_BEELDEN = "Matrixsignaalinformatie.xml.gz"
MSI_LOCATIES = "ndw_msi_shapefiles_latest.zip"
# De plekken van de borden veranderen zelden.
MSI_LOCATIES_SECONDEN = 24 * 3600
# Tijdelijke maximumsnelheden uit de planningsfeed: zo ver vooruit, zodat een
# beperking die ingaat voordat de feed weer wordt opgehaald (eens per uur) op
# tijd meetelt.
SNELHEID_VOORUIT = timedelta(hours=2)
# Zo ver vooruit gaan geplande afsluitingen mee (de app laat een week kiezen).
PLANNING_VOORUIT = timedelta(days=8)
MAX_KPH = 160  # daarboven is het een meetfout, geen auto


def bereken_snelheden(
    reistijden: Iterable[datex3.Reistijd], matches: dict[str, Match | None]
) -> dict[int, int]:
    """Eén record per edge. Ligt een edge onder meerdere segmenten, dan telt elk
    segment mee naar rato van de lengte die het op die edge heeft."""
    som: dict[int, list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0])  # m, m/kph, m/vrij
    for reistijd in reistijden:
        match = matches.get(reistijd.sleutel)
        if not match:
            continue
        kph = match.lengte_m / reistijd.seconden * 3.6
        if kph > MAX_KPH:
            continue
        vrij = (
            match.lengte_m / reistijd.normaal_seconden * 3.6 if reistijd.normaal_seconden else None
        )
        for graphid, lengte, _ in match.edges:
            totaal = som[graphid]
            totaal[0] += lengte
            totaal[1] += lengte / max(kph, 0.1)
            if vrij:
                totaal[2] += lengte / max(vrij, 0.1)
    return {
        graphid: tt.snelheid(meters / per_kph, meters / per_vrij if per_vrij else None)
        for graphid, (meters, per_kph, per_vrij) in som.items()
        if meters > 0
    }


def bereken_afsluitingen(
    afsluitingen: Iterable[datex3.Afsluiting], matches: dict[str, Match | None]
) -> dict[int, int]:
    """De lijn van NDW loopt in één richting. De tegenrichting gaat mee dicht als
    hij over dezelfde OSM-way loopt: dan is het één rijbaan en ligt het werk op de
    hele weg. Bij gescheiden rijbanen heeft de overkant een eigen way en blijft
    hij open -- behalve bij `roadClosed`, dat de hele weg betreft."""
    dicht: dict[int, int] = {}
    for afsluiting in afsluitingen:
        heen = matches.get(afsluiting.sleutel)
        if not heen:
            continue
        ways = {way for _, _, way in heen.edges}
        for graphid, _, _ in heen.edges:
            dicht[graphid] = tt.afgesloten()
        terug = matches.get(afsluiting.sleutel + "#terug")
        if terug:
            for graphid, _, way in terug.edges:
                if afsluiting.hele_weg or way in ways:
                    dicht[graphid] = tt.afgesloten()
    return dicht


def leg_snelheden(
    snelheden: Iterable[datex3.TijdelijkeSnelheid], matches: dict[str, Match | None]
) -> list[tuple[datex3.TijdelijkeSnelheid, Match]]:
    """Elke tijdelijke maximumsnelheid met de weg waar hij op ligt. De lijn van
    NDW loopt in één richting; de tegenrichting telt mee als hij helemaal over
    dezelfde OSM-way(s) loopt (één rijbaan: een 30 bij werk geldt voor beide
    kanten). Een gescheiden rijbaan heeft een eigen way en blijft erbuiten."""
    uit = []
    for snelheid in snelheden:
        heen = matches.get(snelheid.sleutel)
        if not heen:
            continue
        uit.append((snelheid, heen))
        terug = matches.get(snelheid.sleutel + "#terug")
        ways = {way for _, _, way in heen.edges}
        if terug and all(way in ways for _, _, way in terug.edges):
            uit.append((snelheid, terug))
    return uit


class Stand:
    """Wat /metrics en de lagen laten zien. De verkeerslaag bestaat uit delen die
    elk hun eigen draad bijwerkt (de ronde, de matrixborden); bij elke wijziging
    wordt hij opnieuw samengesteld."""

    def __init__(self):
        self.slot = threading.Lock()
        self.waarden: dict[str, float] = {}
        self.laag: tuple[bytes, bytes] | None = None  # (gewoon, gzip)
        self.delen: dict[str, list[dict]] = {}
        self.gepland: tuple[bytes, bytes] | None = None
        self.tijden: tuple[bytes, bytes] | None = None

    def zet_deel(self, naam: str, features: list[dict]) -> None:
        """Het deel [naam] van de verkeerslaag. De laag komt pas beschikbaar als
        de ronde er is: die is de kern (afsluitingen, files)."""
        with self.slot:
            self.delen[naam] = features
            if "ronde" in self.delen:
                self.laag = kaartlaag.geojson(
                    [feature for deel in self.delen.values() for feature in deel]
                )

    def zet_tijden(self, inhoud: tuple[bytes, bytes]) -> None:
        with self.slot:
            self.tijden = inhoud

    def zet_gepland(self, laag: tuple[bytes, bytes]) -> None:
        with self.slot:
            self.gepland = laag

    def zet(self, **waarden: float) -> None:
        with self.slot:
            self.waarden.update(waarden)

    def tekst(self) -> str:
        with self.slot:
            return "".join(
                f"homemaps_traffic_{naam} {waarde}\n"
                for naam, waarde in sorted(self.waarden.items())
            )


class _Server(ThreadingHTTPServer):
    # Dual-stack: probes en Prometheus komen in dit cluster over IPv6 binnen.
    address_family = AF_INET6


def start_metrics(stand: Stand, poort: int) -> None:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            pad = self.path.split("?")[0]
            if pad == "/verkeer.geojson":
                self._laag(stand.laag, 60)
                return
            if pad == "/verkeer-gepland.geojson":
                self._laag(stand.gepland, 600)
                return
            if pad == "/snelheid-tijden.json":
                self._laag(stand.tijden, 3600, "application/json")
                return
            self._stuur(200, stand.tekst().encode(), "text/plain; version=0.0.4")

        def _laag(self, laag, cache, soort="application/geo+json"):
            if laag is None:  # de eerste ronde loopt nog
                self._stuur(503, b"nog geen ronde\n", "text/plain")
                return
            gzip = "gzip" in self.headers.get("Accept-Encoding", "")
            self._stuur(
                200,
                laag[1] if gzip else laag[0],
                soort,
                {"Cache-Control": f"max-age={cache}", "Vary": "Accept-Encoding"}
                | ({"Content-Encoding": "gzip"} if gzip else {}),
            )

        def _stuur(self, status, body, soort, extra=None):
            self.send_response(status)
            self.send_header("Content-Type", soort)
            self.send_header("Content-Length", str(len(body)))
            for naam, waarde in (extra or {}).items():
                self.send_header(naam, waarde)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    server = _Server(("::", poort), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()


def haal(url: str) -> io.BytesIO:
    verzoek = urllib.request.Request(url, headers={"User-Agent": "homemaps-traffic"})
    with urllib.request.urlopen(verzoek, timeout=120) as antwoord:
        return io.BytesIO(antwoord.read())


class Importer:
    def __init__(
        self,
        tar: TrafficTar,
        valhalla: Valhalla,
        cache_dir: Path,
        ndw: str,
        stand: Stand,
        afsluitingen: bool = True,
        meldingen: bool = True,
        planning_seconden: int = 3600,
        snelheden: bool = True,
        osm_pbf: Path | None = None,
        bruggen: bool = True,
    ):
        self.tar, self.valhalla, self.ndw, self.stand = tar, valhalla, ndw.rstrip("/"), stand
        self.met_afsluitingen = afsluitingen
        self.met_meldingen = meldingen
        self.planning_seconden = planning_seconden
        self.planning_gehaald = 0.0
        self.met_snelheden = snelheden
        # Uit de planningsfeed, bij elke ophaalbeurt ververst.
        self.geplande_snelheden: list[datex3.TijdelijkeSnelheid] = []
        self.osm_pbf = osm_pbf
        self.met_bruggen = bruggen
        self.pbf_gelezen: float | None = None  # mtime van de laatst gelezen PBF
        tileset = valhalla.tileset()
        self.locaties = MatchCache(cache_dir / "meetlocaties.json", tileset)
        self.afsluitingen = MatchCache(cache_dir / "afsluitingen.json", tileset, alleen_bedekt=True)
        self.snelheden = MatchCache(cache_dir / "snelheden.json", tileset)
        self.geschreven: set[int] = set()
        # Wat een vorige instantie schreef is onbekend, dus alles eerst leeg.
        tar.wis_alles()

    def _ververs_locaties(self, nodig: set[str]) -> None:
        """De configuratie is 100 MB; alleen ophalen als de metingen naar een
        locatie(versie) wijzen die nog niet in de cache zit."""
        if nodig <= self.locaties.matches.keys():
            return
        log.info("meetlocaties ophalen (%d onbekend)", len(nodig - self.locaties.matches.keys()))
        feed = datex3.open_feed(haal(f"{self.ndw}/reistijden_configuratie_meetlocaties.xml.gz"))
        items = {locatie.sleutel: locatie.punten for locatie in datex3.lees_meetlocaties(feed)}
        if self.locaties.vul_aan(self.valhalla, items):
            self.locaties.bewaar()

    def _planning(self) -> None:
        """Eens per uur: de planningsfeed (18 MB) voor "later vertrekken". Hij
        verandert traag, en een mislukte beurt laat de vorige staan."""
        if (
            not self.planning_seconden
            or time.time() - self.planning_gehaald < self.planning_seconden
        ):
            return
        self.planning_gehaald = time.time()
        nu = datetime.now(UTC)
        try:
            ruw = haal(f"{self.ndw}/{PLANNING}")
            gepland = list(
                datex3.lees_geplande_afsluitingen(datex3.open_feed(ruw), nu, nu + PLANNING_VOORUIT)
            )
            if self.met_snelheden:
                ruw.seek(0)
                self.geplande_snelheden = list(
                    datex3.lees_snelheden(datex3.open_feed(ruw), nu, nu + SNELHEID_VOORUIT)
                )
        except (OSError, ValueError, ParseError) as fout:
            log.warning("planningsfeed niet opgehaald: %s", fout)
            return
        self.stand.zet_gepland(kaartlaag.geojson(kaartlaag.geplande_afsluitingen(gepland)))
        self.stand.zet(geplande_afsluitingen=len(gepland))
        log.info(
            "planningsfeed: %d afsluitingen in de komende dagen, %d tijdelijke snelheden",
            len(gepland),
            len(self.geplande_snelheden),
        )

    def _snelheden(self, nu: datetime) -> list[dict]:
        """De tijdelijke maximumsnelheden die nu gelden, als features voor de
        laag: uit de eigen feed (elke ronde) en uit de planningsfeed. Alleen voor
        de app onderweg; Valhalla kent geen maximumsnelheid in traffic.tar."""
        actueel: list[datex3.TijdelijkeSnelheid] = []
        try:
            feed = datex3.open_feed(haal(f"{self.ndw}/{SNELHEDEN}"))
            actueel = list(datex3.lees_snelheden(feed, nu, nu))
        except (OSError, ValueError, ParseError) as fout:
            log.warning("maximumsnelheden niet opgehaald: %s", fout)
        geldig = actueel + [s for s in self.geplande_snelheden if s.geldt(nu)]
        items: dict[str, tuple] = {}
        for snelheid in geldig:
            items[snelheid.sleutel] = snelheid.punten
            items[snelheid.sleutel + "#terug"] = snelheid.punten[::-1]
        if self.snelheden.vul_aan(self.valhalla, items):
            self.snelheden.bewaar()
        gelegd = leg_snelheden(geldig, self.snelheden.matches)
        self.stand.zet(
            tijdelijke_snelheden=len(geldig),
            tijdelijke_snelheden_gematcht=sum(
                1 for s in geldig if self.snelheden.matches.get(s.sleutel)
            ),
        )
        return kaartlaag.snelheden(gelegd, nu)

    def _snelheid_tijden(self) -> None:
        """Maximumsnelheden naar tijdstip uit het OSM-bestand van de tileset:
        bij de start, en opnieuw als de bouwjob een nieuw bestand neerzet."""
        if self.osm_pbf is None:
            return
        try:
            gewijzigd = self.osm_pbf.stat().st_mtime
        except OSError:
            if self.pbf_gelezen is None:
                log.warning("geen OSM-bestand op %s: geen snelheden naar tijdstip", self.osm_pbf)
                self.pbf_gelezen = 0.0
            return
        if gewijzigd == self.pbf_gelezen:
            return
        begin = time.time()
        try:
            with open(self.osm_pbf, "rb") as stroom:
                ways = osmregels.snelheid_tijden(stroom)
        except (OSError, ValueError, KeyError, zlib.error) as fout:
            log.warning("OSM-bestand niet gelezen: %s", fout)
            return
        self.pbf_gelezen = gewijzigd
        self.stand.zet_tijden(kaartlaag.comprimeer({"ways": ways}))
        self.stand.zet(snelheid_tijden_ways=len(ways))
        log.info("snelheden naar tijdstip: %d ways (%.1f s)", len(ways), time.time() - begin)

    def ronde(self) -> None:
        begin = time.time()
        self._snelheid_tijden()
        feed = datex3.open_feed(haal(f"{self.ndw}/reistijden_meetgegevens.xml.gz"))
        reistijden = list(datex3.lees_reistijden(feed))
        self._ververs_locaties({reistijd.sleutel for reistijd in reistijden})
        records = bereken_snelheden(reistijden, self.locaties.matches)
        snelheden = len(records)

        dicht: dict[int, int] = {}
        maatregelen: list[datex3.Maatregel] = []
        if self.met_afsluitingen:
            feed = datex3.open_feed(
                haal(f"{self.ndw}/tijdelijke_verkeersmaatregelen_afsluitingen.xml.gz")
            )
            maatregelen = list(datex3.lees_maatregelen(feed))
            actief = [maatregel.als_afsluiting() for maatregel in maatregelen if maatregel.sluit_af]
            items: dict[str, tuple] = {}
            for afsluiting in actief:
                items[afsluiting.sleutel] = afsluiting.punten
                items[afsluiting.sleutel + "#terug"] = afsluiting.punten[::-1]
            if self.afsluitingen.vul_aan(self.valhalla, items):
                self.afsluitingen.bewaar()
            dicht = bereken_afsluitingen(actief, self.afsluitingen.matches)
            records.update(dicht)  # dicht wint van een gemeten snelheid

        self._planning()
        geschreven, gewist, onbekend = self.tar.werk_bij(records, self.geschreven)
        self.geschreven = set(records)

        features = kaartlaag.maatregelen(maatregelen) + kaartlaag.trage_stukken(
            reistijden, self.locaties.matches
        )
        if self.met_snelheden:
            features += self._snelheden(datetime.now(UTC))
        if self.met_meldingen:
            # Alleen voor de kaart en de waarschuwing onderweg: de vertraging
            # die een ongeval geeft zit al in de reistijden. Een mislukte
            # ophaalbeurt kost dus alleen de punten, niet de ronde.
            try:
                feed = datex3.open_feed(
                    haal(f"{self.ndw}/veiligheidsgerelateerde_berichten_srti.xml.gz")
                )
                features += kaartlaag.meldingen(datex3.lees_meldingen(feed))
            except (OSError, ValueError) as fout:
                log.warning("meldingen niet opgehaald: %s", fout)
        if self.met_bruggen:
            # Een open brug: alleen de waarschuwing onderweg. Hij gaat na een
            # paar minuten weer dicht, dus Valhalla hoeft er niet omheen.
            try:
                feed = datex3.open_feed(haal(f"{self.ndw}/{ACTUEEL}"))
                open_bruggen = list(datex3.lees_bruggen(feed))
                features += kaartlaag.bruggen(open_bruggen)
                self.stand.zet(bruggen_open=len(open_bruggen))
            except (OSError, ValueError, ParseError) as fout:
                log.warning("actueel beeld niet opgehaald: %s", fout)
        self.stand.zet_deel("ronde", features)
        gematcht = sum(1 for match in self.locaties.matches.values() if match)
        self.stand.zet(
            laatste_ronde_timestamp_seconds=time.time(),
            ronde_duur_seconds=round(time.time() - begin, 2),
            edges_met_snelheid=snelheden,
            edges_afgesloten=len(dicht),
            edges_gewist=gewist,
            edges_buiten_tileset=onbekend,
            metingen=len(reistijden),
            meetlocaties=len(self.locaties.matches),
            meetlocaties_gematcht=gematcht,
            kaartlaag_features=len(features),
        )
        log.info(
            "ronde: %d metingen -> %d edges met snelheid, %d afgesloten, %d gewist (%.1f s)",
            len(reistijden),
            snelheden,
            len(dicht),
            gewist,
            time.time() - begin,
        )


class Matrixborden:
    """Elke minuut wat de matrixborden tonen, in een eigen draad: de ronde duurt
    vijf minuten, en een 70 boven de weg staat er soms maar een paar minuten."""

    def __init__(self, ndw: str, stand: Stand, seconden: int):
        self.ndw, self.stand, self.seconden = ndw.rstrip("/"), stand, seconden
        self.locaties: dict[str, msi.Bordplek] = {}
        self.locaties_gehaald = 0.0

    def ververs(self) -> None:
        if not self.locaties or time.time() - self.locaties_gehaald > MSI_LOCATIES_SECONDEN:
            try:
                self.locaties = msi.lees_locaties(haal(f"{self.ndw}/{MSI_LOCATIES}"))
                self.locaties_gehaald = time.time()
                log.info("matrixborden: %d plekken", len(self.locaties))
            except (OSError, ValueError, KeyError, StopIteration, zipfile.BadZipFile) as fout:
                log.warning("plekken van de matrixborden niet opgehaald: %s", fout)
                if not self.locaties:
                    return
        beelden = msi.lees_beelden(datex3.open_feed(haal(f"{self.ndw}/{MSI_BEELDEN}")))
        portalen = msi.portalen(self.locaties, beelden)
        self.stand.zet_deel("msi", kaartlaag.msi(portalen))
        self.stand.zet(
            msi_portalen=len(portalen),
            msi_timestamp_seconds=time.time(),
        )

    def lus(self) -> None:
        while True:
            try:
                self.ververs()
            except (OSError, ValueError, ParseError) as fout:
                log.warning("matrixborden niet opgehaald: %s", fout)
            time.sleep(self.seconden)


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    omgeving = os.environ
    interval = int(omgeving.get("INTERVAL_SECONDEN", "300"))
    cache_dir = Path(omgeving.get("CACHE_DIR", "/data/importer"))
    cache_dir.mkdir(parents=True, exist_ok=True)
    stand = Stand()
    stand.zet(rondes_mislukt_total=0)
    start_metrics(stand, int(omgeving.get("METRICS_POORT", "9100")))

    valhalla = Valhalla(omgeving.get("VALHALLA_URL", "http://localhost:8002"))
    while True:
        try:
            valhalla.tileset()
            break
        except OSError:
            log.info("wachten op Valhalla")
            time.sleep(5)

    tar = TrafficTar(omgeving.get("TRAFFIC_TAR", "/data/traffic.tar"))
    log.info("traffic.tar: %d tegels, %d edges", len(tar.tegels), tar.aantal_edges)
    importer = Importer(
        tar,
        valhalla,
        cache_dir,
        omgeving.get("NDW_URL", "https://opendata.ndw.nu"),
        stand,
        omgeving.get("AFSLUITINGEN", "true").lower() != "false",
        omgeving.get("MELDINGEN", "true").lower() != "false",
        int(omgeving.get("PLANNING_SECONDEN", "3600")),
        omgeving.get("SNELHEDEN", "true").lower() != "false",
        Path(omgeving.get("OSM_PBF", "/data/bron/gebied.osm.pbf")),
        omgeving.get("BRUGGEN", "true").lower() != "false",
    )
    msi_seconden = int(omgeving.get("MSI_SECONDEN", "60"))
    if msi_seconden:
        borden = Matrixborden(
            omgeving.get("NDW_URL", "https://opendata.ndw.nu"), stand, msi_seconden
        )
        threading.Thread(target=borden.lus, daemon=True).start()
    mislukt = 0
    while True:
        try:
            importer.ronde()
        except Exception:  # noqa: BLE001 -- één slechte ronde mag de lus niet stoppen
            mislukt += 1
            stand.zet(rondes_mislukt_total=mislukt)
            log.exception("ronde mislukt")
        time.sleep(interval)


if __name__ == "__main__":
    main()
