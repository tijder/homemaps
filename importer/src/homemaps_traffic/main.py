"""De lus: NDW ophalen, op edges leggen, traffic.tar bijwerken, meten.

Instellingen komen uit de omgeving (de chart zet ze):

  TRAFFIC_TAR        pad naar traffic.tar            (/data/traffic.tar)
  VALHALLA_URL       de Valhalla in dezelfde pod     (http://localhost:8002)
  CACHE_DIR          waar de match-cache mag staan   (/data/importer)
  NDW_URL            basis van de feeds              (https://opendata.ndw.nu)
  INTERVAL_SECONDEN  tussen twee rondes              (300)
  AFSLUITINGEN       "false" zet die feed uit        (true)
  METRICS_POORT      Prometheus-endpoint             (9100)
"""

import io
import logging
import os
import sys
import threading
import time
import urllib.request
from collections import defaultdict
from collections.abc import Iterable
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socket import AF_INET6

from . import datex3
from . import traffictile as tt
from .matcher import Match, MatchCache, Valhalla
from .tarindex import TrafficTar

log = logging.getLogger("homemaps_traffic")

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


class Stand:
    """Wat /metrics laat zien. Eén ronde per keer, dus een lock volstaat."""

    def __init__(self):
        self.slot = threading.Lock()
        self.waarden: dict[str, float] = {}

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
            body = stand.tekst().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
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
    ):
        self.tar, self.valhalla, self.ndw, self.stand = tar, valhalla, ndw.rstrip("/"), stand
        self.met_afsluitingen = afsluitingen
        tileset = valhalla.tileset()
        self.locaties = MatchCache(cache_dir / "meetlocaties.json", tileset)
        self.afsluitingen = MatchCache(cache_dir / "afsluitingen.json", tileset)
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

    def ronde(self) -> None:
        begin = time.time()
        feed = datex3.open_feed(haal(f"{self.ndw}/reistijden_meetgegevens.xml.gz"))
        reistijden = list(datex3.lees_reistijden(feed))
        self._ververs_locaties({reistijd.sleutel for reistijd in reistijden})
        records = bereken_snelheden(reistijden, self.locaties.matches)
        snelheden = len(records)

        dicht: dict[int, int] = {}
        if self.met_afsluitingen:
            feed = datex3.open_feed(
                haal(f"{self.ndw}/tijdelijke_verkeersmaatregelen_afsluitingen.xml.gz")
            )
            actief = list(datex3.lees_afsluitingen(feed))
            items: dict[str, tuple] = {}
            for afsluiting in actief:
                items[afsluiting.sleutel] = afsluiting.punten
                items[afsluiting.sleutel + "#terug"] = afsluiting.punten[::-1]
            if self.afsluitingen.vul_aan(self.valhalla, items):
                self.afsluitingen.bewaar()
            dicht = bereken_afsluitingen(actief, self.afsluitingen.matches)
            records.update(dicht)  # dicht wint van een gemeten snelheid

        geschreven, gewist, onbekend = self.tar.werk_bij(records, self.geschreven)
        self.geschreven = set(records)
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
        )
        log.info(
            "ronde: %d metingen -> %d edges met snelheid, %d afgesloten, %d gewist (%.1f s)",
            len(reistijden),
            snelheden,
            len(dicht),
            gewist,
            time.time() - begin,
        )


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
    )
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
