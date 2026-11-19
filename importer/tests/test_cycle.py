"""The cycle and the MSI loop against feeds that fail: what stays, what is
withdrawn, and that the loop goes on."""

import gzip
import http.client
import io
import urllib.request
from pathlib import Path

import pytest

from homemaps_traffic import main
from homemaps_traffic.matcher import Match

FIXTURES = Path(__file__).parent / "fixtures"

TRAVEL_TIMES = "reistijden_meetgegevens.xml.gz"
SITES = "reistijden_configuratie_meetlocaties.xml.gz"
CLOSURES = "tijdelijke_verkeersmaatregelen_afsluitingen.xml.gz"


def _gzip(name: str) -> bytes:
    return gzip.compress((FIXTURES / name).read_bytes())


class Feeds:
    """Stands in for NDW: per file the content, or the error fetching raises."""

    def __init__(self):
        self.files: dict[str, bytes | Exception] = {
            TRAVEL_TIMES: _gzip("travel_times.xml"),
            SITES: _gzip("measurement_sites.xml"),
            CLOSURES: _gzip("closures.xml"),
        }
        self.fetched: list[str] = []

    def __call__(self, url: str) -> io.BytesIO:
        name = url.rsplit("/", 1)[-1]
        self.fetched.append(name)
        content = self.files.get(name, OSError("404"))
        if isinstance(content, Exception):
            raise content
        return io.BytesIO(content)


class FakeValhalla:
    def tileset(self) -> int:
        return 1

    def match(self, points, covered_only=False):
        # Every line lies on its own edge.
        return Match(((hash(tuple(points)) % 10_000, 1000.0, 1),), 1000.0)


class FakeTar:
    def __init__(self):
        self.records: dict[int, int] = {}

    def clear_all(self) -> None:
        self.records.clear()

    def update(self, new, previous):
        cleared = previous - new.keys()
        for graphid in cleared:
            del self.records[graphid]
        self.records.update(new)
        return len(new), len(cleared), 0


@pytest.fixture
def feeds(monkeypatch):
    feeds = Feeds()
    monkeypatch.setattr(main, "fetch", feeds)
    return feeds


def _importer(tmp_path, state, **options):
    tar = FakeTar()
    options = {"incidents": False, "planning_seconds": 0, "speed_limits": False} | options
    importer = main.Importer(
        tar, FakeValhalla(), tmp_path, "http://ndw", state, bridges=False, **options
    )
    return importer, tar


def test_cycle_writes_speeds_and_layer(tmp_path, feeds):
    state = main.State()
    importer, tar = _importer(tmp_path, state)
    importer.cycle()
    assert tar.records
    assert state.layer is not None
    assert 'feed_last_success_timestamp_seconds{feed="travel_times"}' in state.values
    assert state.values['feed_failures_total{feed="closures"}'] == 0


def test_closures_feed_down_keeps_speeds_and_earlier_closures(tmp_path, feeds):
    state = main.State()
    importer, tar = _importer(tmp_path, state)
    importer.cycle()
    before = dict(tar.records)
    measures = len(importer.measures)
    assert measures

    feeds.files[CLOSURES] = OSError("404")
    importer.cycle()
    # The cycle went through: the speeds are written, the closures stay.
    assert tar.records == before
    assert len(importer.measures) == measures
    assert state.values['feed_failures_total{feed="closures"}'] == 1

    # Not forever: once they are stale they go.
    importer.measures_fetched -= importer.stale_seconds + 1
    importer.cycle()
    assert importer.measures == []


def test_truncated_feed_fails_the_cycle_and_stale_traffic_is_cleared(tmp_path, feeds):
    state = main.State()
    importer, tar = _importer(tmp_path, state)
    importer.cycle()
    assert tar.records

    feeds.files[TRAVEL_TIMES] = _gzip("travel_times.xml")[:-20]
    with pytest.raises(main.FEED_ERRORS):
        importer.cycle()
    assert state.values['feed_failures_total{feed="travel_times"}'] == 1
    # Not stale yet: the last good cycle stays in effect.
    importer.expire()
    assert tar.records and state.layer is not None

    importer.tar_written -= importer.stale_seconds + 1
    importer.layer_set -= importer.stale_seconds + 1
    importer.expire()
    assert tar.records == {}
    assert state.layer is None

    # And back once the feed is.
    feeds.files[TRAVEL_TIMES] = _gzip("travel_times.xml")
    importer.cycle()
    assert tar.records and state.layer is not None


def test_sites_are_not_fetched_again_for_the_same_unknown_site(tmp_path, feeds):
    state = main.State()
    importer, _ = _importer(tmp_path, state, closures=False)
    importer.cycle()
    # SITE_D is measured but not in the configuration.
    assert importer.sites_unknown
    importer.cycle()
    importer.cycle()
    assert feeds.fetched.count(SITES) == 1

    importer.sites_fetched -= main.SITES_RETRY_SECONDS + 1
    importer.cycle()
    assert feeds.fetched.count(SITES) == 2


def test_sites_feed_down_does_not_fail_the_cycle(tmp_path, feeds):
    state = main.State()
    importer, _ = _importer(tmp_path, state, closures=False)
    feeds.files[SITES] = http.client.IncompleteRead(b"")
    importer.cycle()
    assert state.values['feed_failures_total{feed="measurement_sites"}'] == 1
    assert state.layer is not None


@pytest.mark.parametrize(
    "error",
    [http.client.IncompleteRead(b""), EOFError(), IndexError("damaged shapefile")],
)
def test_msi_loop_survives_whatever_a_feed_raises(feeds, error):
    state = main.State()
    signs = main.MsiSigns("http://ndw", state, 60)
    signs.locations = {"x": None}
    signs.locations_fetched = main.time.time()
    feeds.files[main.MSI_DISPLAYS] = error
    signs.once()
    assert state.values['feed_failures_total{feed="msi"}'] == 1


def test_stale_msi_signs_are_withdrawn(feeds):
    state = main.State()
    state.set_part("cycle", [])
    state.set_part("msi", [{"type": "Feature"}])
    signs = main.MsiSigns("http://ndw", state, 60)
    signs.locations = {"x": None}
    signs.locations_fetched = main.time.time()
    signs.once()
    assert "msi" in state.parts
    signs.displays_fetched -= signs.stale_seconds + 1
    signs.once()
    assert "msi" not in state.parts
    assert state.layer is not None


def test_unreadable_record_is_skipped(tmp_path, feeds):
    damaged = (FIXTURES / "closures.xml").read_text().replace("52.", "x52.", 1)
    feeds.files[CLOSURES] = gzip.compress(damaged.encode())
    state = main.State()
    importer, _ = _importer(tmp_path, state)
    importer.cycle()
    assert state.values['feed_failures_total{feed="closures"}'] == 0


def test_healthz_reports_a_stalled_loop():
    state = main.State()
    state.beat("cycle", 60)
    server = main.start_metrics(state, 0)
    port = server.server_address[1]
    try:
        with urllib.request.urlopen(f"http://[::1]:{port}/healthz") as response:
            assert response.status == 200
        with urllib.request.urlopen(f"http://[::1]:{port}/metrics") as response:
            assert response.status == 200
        state.watched["cycle"] = (main.time.monotonic() - 61, 60)
        with pytest.raises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(f"http://[::1]:{port}/healthz")
        assert caught.value.code == 503
        assert b"cycle" in caught.value.read()
    finally:
        server.shutdown()


def test_an_old_feed_served_as_new_is_not_live_traffic(tmp_path, feeds):
    xml = (FIXTURES / "travel_times.xml").read_text()
    first = xml.index("<", xml.index("?>") + 2)
    end_of_root = xml.index(">", first) + 1

    def with_time(time: str) -> bytes:
        stamped = f"{xml[:end_of_root]}<publicationTime>{time}</publicationTime>{xml[end_of_root:]}"
        return gzip.compress(stamped.encode())

    state = main.State()
    importer, tar = _importer(tmp_path, state, closures=False)
    feeds.files[TRAVEL_TIMES] = with_time(main.datetime.now(main.UTC).isoformat())
    importer.cycle()
    assert "travel_times_published_timestamp_seconds" in state.values

    feeds.files[TRAVEL_TIMES] = with_time("2026-01-01T00:00:00.123456789Z")
    with pytest.raises(ValueError, match="published"):
        importer.cycle()
    assert state.values['feed_failures_total{feed="travel_times"}'] == 1
