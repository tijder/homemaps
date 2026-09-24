"""The loop: fetch NDW, lay it onto edges, update traffic.tar, measure.

Settings come from the environment (the chart sets them):

  TRAFFIC_TAR        path to traffic.tar             (/data/traffic.tar)
  VALHALLA_URL       the Valhalla in the same pod    (http://localhost:8002)
  CACHE_DIR          where the match cache may live  (/data/importer)
  NDW_URL            base of the feeds               (https://opendata.ndw.nu)
  INTERVAL_SECONDS   between two cycles              (300)
  CLOSURES           "false" turns that feed off     (true)
  INCIDENTS          "false" turns the SRTI feed off (true)
  PLANNING_SECONDS   how often the planning feed     (3600; 0 = never)
  SPEED_LIMITS       "false" turns temporary maximum speeds off (true)
  OSM_PBF            the tileset's OSM file          (/data/source/region.osm.pbf)
  MSI_SECONDS        how often the MSI signs         (60; 0 = never)
  BRIDGES            "false" turns open bridges off  (true)
  METRICS_PORT       /metrics and /traffic.geojson   (9100)
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

from . import datex3, maplayer, msi, osmrules
from . import traffictile as tt
from .matcher import Match, MatchCache, Valhalla
from .tarindex import TrafficTar

log = logging.getLogger("homemaps_traffic")

SRTI = "veiligheidsgerelateerde_berichten_srti.xml.gz"
PLANNING = "planningsfeed_wegwerkzaamheden_en_evenementen.xml.gz"
SPEED_LIMITS = "tijdelijke_verkeersmaatregelen_maximum_snelheden.xml.gz"
CURRENT_SITUATION = "actueel_beeld.xml.gz"
MSI_DISPLAYS = "Matrixsignaalinformatie.xml.gz"
MSI_LOCATIONS = "ndw_msi_shapefiles_latest.zip"
# The locations of the signs rarely change.
MSI_LOCATIONS_SECONDS = 24 * 3600
# Temporary maximum speeds from the planning feed: this far ahead, so that a
# restriction that starts before the feed is fetched again (once an hour)
# counts in time.
SPEED_LIMIT_LOOKAHEAD = timedelta(hours=2)
# Planned closures are included this far ahead (the app lets you pick a week).
PLANNING_LOOKAHEAD = timedelta(days=8)
MAX_KPH = 160  # above that it is a measurement error, not a car


def compute_speeds(
    travel_times: Iterable[datex3.TravelTime], matches: dict[str, Match | None]
) -> dict[int, int]:
    """One record per edge. If an edge lies under several segments, each segment
    counts in proportion to the length it has on that edge."""
    sums: dict[int, list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0])  # m, m/kph, m/free
    for travel_time in travel_times:
        match = matches.get(travel_time.key)
        if not match:
            continue
        kph = match.length_m / travel_time.seconds * 3.6
        if kph > MAX_KPH:
            continue
        freeflow = (
            match.length_m / travel_time.normal_seconds * 3.6
            if travel_time.normal_seconds
            else None
        )
        for graphid, length, _ in match.edges:
            total = sums[graphid]
            total[0] += length
            total[1] += length / max(kph, 0.1)
            if freeflow:
                total[2] += length / max(freeflow, 0.1)
    return {
        graphid: tt.speed(meters / per_kph, meters / per_free if per_free else None)
        for graphid, (meters, per_kph, per_free) in sums.items()
        if meters > 0
    }


def compute_closures(
    closures: Iterable[datex3.Closure], matches: dict[str, Match | None]
) -> dict[int, int]:
    """NDW's line runs in one direction. The opposite direction is closed too if
    it runs over the same OSM way: then it is a single carriageway and the work
    covers the whole road. On dual carriageways the other side has its own way
    and stays open -- except with `roadClosed`, which concerns the whole road."""
    closed: dict[int, int] = {}
    for closure in closures:
        forward = matches.get(closure.key)
        if not forward:
            continue
        ways = {way for _, _, way in forward.edges}
        for graphid, _, _ in forward.edges:
            closed[graphid] = tt.closed()
        reverse = matches.get(closure.key + "#reverse")
        if reverse:
            for graphid, _, way in reverse.edges:
                if closure.whole_road or way in ways:
                    closed[graphid] = tt.closed()
    return closed


def place_speed_limits(
    limits: Iterable[datex3.TemporarySpeedLimit], matches: dict[str, Match | None]
) -> list[tuple[datex3.TemporarySpeedLimit, Match]]:
    """Every temporary maximum speed with the road it lies on. NDW's line runs
    in one direction; the opposite direction counts if it runs entirely over the
    same OSM way(s) (a single carriageway: a 30 at road works applies to both
    sides). A dual carriageway has its own way and stays out."""
    out = []
    for limit in limits:
        forward = matches.get(limit.key)
        if not forward:
            continue
        out.append((limit, forward))
        reverse = matches.get(limit.key + "#reverse")
        ways = {way for _, _, way in forward.edges}
        if reverse and all(way in ways for _, _, way in reverse.edges):
            out.append((limit, reverse))
    return out


class State:
    """What /metrics and the layers show. The traffic layer consists of parts
    that each get updated by their own thread (the cycle, the MSI signs); it is
    reassembled on every change."""

    def __init__(self):
        self.lock = threading.Lock()
        self.values: dict[str, float] = {}
        self.layer: tuple[bytes, bytes] | None = None  # (plain, gzip)
        self.parts: dict[str, list[dict]] = {}
        self.planned: tuple[bytes, bytes] | None = None
        self.conditional_speeds: tuple[bytes, bytes] | None = None

    def set_part(self, name: str, features: list[dict]) -> None:
        """The part [name] of the traffic layer. The layer only becomes available
        once the cycle is there: that is the core (closures, jams)."""
        with self.lock:
            self.parts[name] = features
            if "cycle" in self.parts:
                self.layer = maplayer.geojson(
                    [feature for part in self.parts.values() for feature in part]
                )

    def set_conditional_speeds(self, content: tuple[bytes, bytes]) -> None:
        with self.lock:
            self.conditional_speeds = content

    def set_planned(self, layer: tuple[bytes, bytes]) -> None:
        with self.lock:
            self.planned = layer

    def set(self, **values: float) -> None:
        with self.lock:
            self.values.update(values)

    def text(self) -> str:
        with self.lock:
            return "".join(
                f"homemaps_traffic_{name} {value}\n" for name, value in sorted(self.values.items())
            )


class _Server(ThreadingHTTPServer):
    # Dual-stack: probes and Prometheus come in over IPv6 in this cluster.
    address_family = AF_INET6


def start_metrics(state: State, port: int) -> None:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = self.path.split("?")[0]
            if path == "/traffic.geojson":
                self._layer(state.layer, 60)
                return
            if path == "/traffic-planned.geojson":
                self._layer(state.planned, 600)
                return
            if path == "/conditional-speeds.json":
                self._layer(state.conditional_speeds, 3600, "application/json")
                return
            self._send(200, state.text().encode(), "text/plain; version=0.0.4")

        def _layer(self, layer, cache, content_type="application/geo+json"):
            if layer is None:  # the first cycle is still running
                self._send(503, b"no cycle yet\n", "text/plain")
                return
            gzip = "gzip" in self.headers.get("Accept-Encoding", "")
            self._send(
                200,
                layer[1] if gzip else layer[0],
                content_type,
                {"Cache-Control": f"max-age={cache}", "Vary": "Accept-Encoding"}
                | ({"Content-Encoding": "gzip"} if gzip else {}),
            )

        def _send(self, status, body, content_type, extra=None):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            for name, value in (extra or {}).items():
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    server = _Server(("::", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()


def fetch(url: str) -> io.BytesIO:
    request = urllib.request.Request(url, headers={"User-Agent": "homemaps-traffic"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return io.BytesIO(response.read())


class Importer:
    def __init__(
        self,
        tar: TrafficTar,
        valhalla: Valhalla,
        cache_dir: Path,
        ndw: str,
        state: State,
        closures: bool = True,
        incidents: bool = True,
        planning_seconds: int = 3600,
        speed_limits: bool = True,
        osm_pbf: Path | None = None,
        bridges: bool = True,
    ):
        self.tar, self.valhalla, self.ndw, self.state = tar, valhalla, ndw.rstrip("/"), state
        self.with_closures = closures
        self.with_incidents = incidents
        self.planning_seconds = planning_seconds
        self.planning_fetched = 0.0
        self.with_speed_limits = speed_limits
        # From the planning feed, refreshed on every fetch.
        self.planned_speed_limits: list[datex3.TemporarySpeedLimit] = []
        self.osm_pbf = osm_pbf
        self.with_bridges = bridges
        self.pbf_read: float | None = None  # mtime of the last PBF read
        tileset = valhalla.tileset()
        self.sites = MatchCache(cache_dir / "measurement_sites.json", tileset)
        self.closures = MatchCache(cache_dir / "closures.json", tileset, covered_only=True)
        self.speed_limits = MatchCache(cache_dir / "speed_limits.json", tileset)
        self.written: set[int] = set()
        # What a previous instance wrote is unknown, so clear everything first.
        tar.clear_all()

    def _refresh_sites(self, needed: set[str]) -> None:
        """The configuration is 100 MB; only fetch it when the measurements point
        to a site (version) that is not in the cache yet."""
        if needed <= self.sites.matches.keys():
            return
        log.info("fetching measurement sites (%d unknown)", len(needed - self.sites.matches.keys()))
        feed = datex3.open_feed(fetch(f"{self.ndw}/reistijden_configuratie_meetlocaties.xml.gz"))
        items = {site.key: site.points for site in datex3.read_measurement_sites(feed)}
        if self.sites.fill(self.valhalla, items):
            self.sites.save()

    def _planning(self) -> None:
        """Once an hour: the planning feed (18 MB) for "leave later". It changes
        slowly, and a failed attempt keeps the previous one."""
        if not self.planning_seconds or time.time() - self.planning_fetched < self.planning_seconds:
            return
        self.planning_fetched = time.time()
        now = datetime.now(UTC)
        try:
            raw = fetch(f"{self.ndw}/{PLANNING}")
            planned = list(
                datex3.read_planned_closures(datex3.open_feed(raw), now, now + PLANNING_LOOKAHEAD)
            )
            if self.with_speed_limits:
                raw.seek(0)
                self.planned_speed_limits = list(
                    datex3.read_speed_limits(
                        datex3.open_feed(raw), now, now + SPEED_LIMIT_LOOKAHEAD
                    )
                )
        except (OSError, ValueError, ParseError) as error:
            log.warning("planning feed not fetched: %s", error)
            return
        self.state.set_planned(maplayer.geojson(maplayer.planned_closures(planned)))
        self.state.set(planned_closures=len(planned))
        log.info(
            "planning feed: %d closures in the coming days, %d temporary speed limits",
            len(planned),
            len(self.planned_speed_limits),
        )

    def _speed_limits(self, now: datetime) -> list[dict]:
        """The temporary maximum speeds that apply now, as features for the
        layer: from their own feed (every cycle) and from the planning feed. Only
        for the app while driving; Valhalla has no maximum speed in traffic.tar."""
        current: list[datex3.TemporarySpeedLimit] = []
        try:
            feed = datex3.open_feed(fetch(f"{self.ndw}/{SPEED_LIMITS}"))
            current = list(datex3.read_speed_limits(feed, now, now))
        except (OSError, ValueError, ParseError) as error:
            log.warning("maximum speeds not fetched: %s", error)
        valid = current + [s for s in self.planned_speed_limits if s.applies(now)]
        items: dict[str, tuple] = {}
        for limit in valid:
            items[limit.key] = limit.points
            items[limit.key + "#reverse"] = limit.points[::-1]
        if self.speed_limits.fill(self.valhalla, items):
            self.speed_limits.save()
        placed = place_speed_limits(valid, self.speed_limits.matches)
        self.state.set(
            temporary_speed_limits=len(valid),
            temporary_speed_limits_matched=sum(
                1 for s in valid if self.speed_limits.matches.get(s.key)
            ),
        )
        return maplayer.speed_limits(placed, now)

    def _conditional_speeds(self) -> None:
        """Maximum speeds by time of day from the tileset's OSM file: at startup,
        and again when the build job puts down a new file."""
        if self.osm_pbf is None:
            return
        try:
            modified = self.osm_pbf.stat().st_mtime
        except OSError:
            if self.pbf_read is None:
                log.warning("no OSM file at %s: no speeds by time of day", self.osm_pbf)
                self.pbf_read = 0.0
            return
        if modified == self.pbf_read:
            return
        start = time.time()
        try:
            with open(self.osm_pbf, "rb") as stream:
                ways = osmrules.conditional_speeds(stream)
        except (OSError, ValueError, KeyError, zlib.error) as error:
            log.warning("OSM file not read: %s", error)
            return
        self.pbf_read = modified
        self.state.set_conditional_speeds(maplayer.compress({"ways": ways}))
        self.state.set(conditional_speed_ways=len(ways))
        log.info("speeds by time of day: %d ways (%.1f s)", len(ways), time.time() - start)

    def cycle(self) -> None:
        start = time.time()
        self._conditional_speeds()
        feed = datex3.open_feed(fetch(f"{self.ndw}/reistijden_meetgegevens.xml.gz"))
        travel_times = list(datex3.read_travel_times(feed))
        self._refresh_sites({travel_time.key for travel_time in travel_times})
        records = compute_speeds(travel_times, self.sites.matches)
        speeds = len(records)

        closed: dict[int, int] = {}
        measures: list[datex3.Measure] = []
        if self.with_closures:
            feed = datex3.open_feed(
                fetch(f"{self.ndw}/tijdelijke_verkeersmaatregelen_afsluitingen.xml.gz")
            )
            measures = list(datex3.read_measures(feed))
            active = [measure.as_closure() for measure in measures if measure.closes]
            items: dict[str, tuple] = {}
            for closure in active:
                items[closure.key] = closure.points
                items[closure.key + "#reverse"] = closure.points[::-1]
            if self.closures.fill(self.valhalla, items):
                self.closures.save()
            closed = compute_closures(active, self.closures.matches)
            records.update(closed)  # closed wins over a measured speed

        self._planning()
        written, cleared, unknown = self.tar.update(records, self.written)
        self.written = set(records)

        features = maplayer.measures(measures) + maplayer.slow_segments(
            travel_times, self.sites.matches
        )
        if self.with_speed_limits:
            features += self._speed_limits(datetime.now(UTC))
        if self.with_incidents:
            # Only for the map and the warning while driving: the delay an
            # accident causes is already in the travel times. A failed fetch
            # therefore only costs the points, not the cycle.
            try:
                feed = datex3.open_feed(
                    fetch(f"{self.ndw}/veiligheidsgerelateerde_berichten_srti.xml.gz")
                )
                features += maplayer.incidents(datex3.read_incidents(feed))
            except (OSError, ValueError) as error:
                log.warning("incidents not fetched: %s", error)
        if self.with_bridges:
            # An open bridge: only the warning while driving. It closes again
            # after a few minutes, so Valhalla does not need to route around it.
            try:
                feed = datex3.open_feed(fetch(f"{self.ndw}/{CURRENT_SITUATION}"))
                open_bridges = list(datex3.read_bridges(feed))
                features += maplayer.bridges(open_bridges)
                self.state.set(bridges_open=len(open_bridges))
            except (OSError, ValueError, ParseError) as error:
                log.warning("current situation not fetched: %s", error)
        self.state.set_part("cycle", features)
        matched = sum(1 for match in self.sites.matches.values() if match)
        self.state.set(
            last_cycle_timestamp_seconds=time.time(),
            cycle_duration_seconds=round(time.time() - start, 2),
            edges_with_speed=speeds,
            edges_closed=len(closed),
            edges_cleared=cleared,
            edges_outside_tileset=unknown,
            measurements=len(travel_times),
            measurement_sites=len(self.sites.matches),
            measurement_sites_matched=matched,
            map_layer_features=len(features),
        )
        log.info(
            "cycle: %d measurements -> %d edges with speed, %d closed, %d cleared (%.1f s)",
            len(travel_times),
            speeds,
            len(closed),
            cleared,
            time.time() - start,
        )


class MsiSigns:
    """Every minute what the MSI signs show, in a thread of its own: the cycle
    takes five minutes, and a 70 above the road is sometimes only there for a
    few minutes."""

    def __init__(self, ndw: str, state: State, seconds: int):
        self.ndw, self.state, self.seconds = ndw.rstrip("/"), state, seconds
        self.locations: dict[str, msi.SignLocation] = {}
        self.locations_fetched = 0.0

    def refresh(self) -> None:
        if not self.locations or time.time() - self.locations_fetched > MSI_LOCATIONS_SECONDS:
            try:
                self.locations = msi.read_locations(fetch(f"{self.ndw}/{MSI_LOCATIONS}"))
                self.locations_fetched = time.time()
                log.info("MSI signs: %d locations", len(self.locations))
            except (OSError, ValueError, KeyError, StopIteration, zipfile.BadZipFile) as error:
                log.warning("MSI sign locations not fetched: %s", error)
                if not self.locations:
                    return
        displays = msi.read_displays(datex3.open_feed(fetch(f"{self.ndw}/{MSI_DISPLAYS}")))
        gantries = msi.gantries(self.locations, displays)
        self.state.set_part("msi", maplayer.msi(gantries))
        self.state.set(
            msi_gantries=len(gantries),
            msi_timestamp_seconds=time.time(),
        )

    def loop(self) -> None:
        while True:
            try:
                self.refresh()
            except (OSError, ValueError, ParseError) as error:
                log.warning("MSI signs not fetched: %s", error)
            time.sleep(self.seconds)


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    env = os.environ
    interval = int(env.get("INTERVAL_SECONDS", "300"))
    cache_dir = Path(env.get("CACHE_DIR", "/data/importer"))
    cache_dir.mkdir(parents=True, exist_ok=True)
    state = State()
    state.set(cycles_failed_total=0)
    start_metrics(state, int(env.get("METRICS_PORT", "9100")))

    valhalla = Valhalla(env.get("VALHALLA_URL", "http://localhost:8002"))
    while True:
        try:
            valhalla.tileset()
            break
        except OSError:
            log.info("waiting for Valhalla")
            time.sleep(5)

    tar = TrafficTar(env.get("TRAFFIC_TAR", "/data/traffic.tar"))
    log.info("traffic.tar: %d tiles, %d edges", len(tar.tiles), tar.edge_count)
    importer = Importer(
        tar,
        valhalla,
        cache_dir,
        env.get("NDW_URL", "https://opendata.ndw.nu"),
        state,
        env.get("CLOSURES", "true").lower() != "false",
        env.get("INCIDENTS", "true").lower() != "false",
        int(env.get("PLANNING_SECONDS", "3600")),
        env.get("SPEED_LIMITS", "true").lower() != "false",
        Path(env.get("OSM_PBF", "/data/source/region.osm.pbf")),
        env.get("BRIDGES", "true").lower() != "false",
    )
    msi_seconds = int(env.get("MSI_SECONDS", "60"))
    if msi_seconds:
        signs = MsiSigns(env.get("NDW_URL", "https://opendata.ndw.nu"), state, msi_seconds)
        threading.Thread(target=signs.loop, daemon=True).start()
    failed = 0
    while True:
        try:
            importer.cycle()
        except Exception:  # noqa: BLE001 -- one bad cycle must not stop the loop
            failed += 1
            state.set(cycles_failed_total=failed)
            log.exception("cycle failed")
        time.sleep(interval)


if __name__ == "__main__":
    main()
