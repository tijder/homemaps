# homemaps-traffic

Sidecar to Valhalla: every few minutes it fetches NDW's open data, writes it into
Valhalla's `traffic.tar` and turns it into the app's traffic layer.

| source (DATEX II v3, `opendata.ndw.nu`) | becomes |
|---|---|
| `reistijden_meetgegevens` + `reistijden_configuratie_meetlocaties` | live speed per edge |
| `tijdelijke_verkeersmaatregelen_afsluitingen` (`carriagewayClosures`, `roadClosed`, valid now, not just for trucks) | closed edges |
| the same feeds, plus `laneClosures` | `/traffic.geojson`: the layer on the map |
| `veiligheidsgerelateerde_informatie_srti` (accident, breakdown, object on the road) | points in the same layer; the app warns about them while driving |
| `planningsfeed_wegwerkzaamheden_en_evenementen` (18 MB, once an hour) | `/traffic-planned.geojson`: closures of the coming 8 days with their windows, for "leave later" |
| `tijdelijke_verkeersmaatregelen_maximum_snelheden` (mostly RWS) and the `SpeedManagement` records from the planning feed (also provinces and municipalities) | `kind: speed_limit` in `/traffic.geojson`: temporary maximum speeds that apply now, over the route shape; while driving the app shows the lowest of these and OSM. Not on the map, not in `traffic.tar` |
| `Matrixsignaalinformatie` (every minute, own thread) + `ndw_msi_shapefiles_latest.zip` (locations, once a day) | `kind: msi` in `/traffic.geojson`: per gantry what the MSI signs show, per lane from left to right (`"80r"` mandatory, `"80"` advisory, `"x"`, `"<"`, `">"`, `"open"`, `"end"`, `""`). Blank gantries only within 3 km of an occupied gantry: that is where a speed ends |
| `actueel_beeld` (bridges that are open right now) | `kind: bridge` in `/traffic.geojson`: a warning while driving |

And from the tileset's OSM file (`/data/source/region.osm.pbf`, which the build job
puts down): `maxspeed:conditional` with a time ("130 @ (19:00-06:00)") per OSM way,
as `/conditional-speeds.json`. Valhalla does not read that tag; the app applies the
rule while driving to the way Valhalla names for each piece of the route. The reader
(`osmrules.py`) only unpacks the blocks that contain the tag: for the Netherlands
~20 s and ~20 MB, again as soon as the file changes.

From the same file, `/enforcement.geojson` (`enforcement.py`): speed cameras
(`highway=speed_camera`) and `type=enforcement` relations, as points with `kind`
`speed_camera`, `red_light`, `section_start` or `section_end` (an average speed
check; both ends share `section`), and where known `maxspeed` and `bearing` (the
direction of travel that is checked: from `from` to `to` in the relation, or the
camera's `direction`). The app shows them on the map and in a sign above the speed
limit while driving. A second pass looks up the untagged member nodes; nodes are
sorted by id, so only the blocks that can contain one are unpacked.

## How it works

1. **Matching** (`matcher.py`). An NDW segment is nearly always just a start and
   an end point. Valhalla routes from one to the other; the edges of that route
   (from `trace_attributes`) are the segment. A route that is much longer than
   the line itself is rejected. The result is stored in a cache tied to the tileset
   (`tileset_last_modified`): edge ids change with every tile build.
2. **Calculating** (`main.py`). Speed = route length / travel time; the normal
   travel time gives the congestion level. If an edge is shared by several
   segments, they are weighted by length (harmonic). A closure only includes the
   opposite direction on the same OSM way, because then it is a single carriageway.
3. **Writing** (`tarindex.py`, `traffictile.py`). Into the file itself, via a
   shared mmap, because Valhalla keeps that same file open via mmap. Never put a
   new file next to it and rename it.
4. **The map layer** (`maplayer.py`). Closures ("closed") and lane closures
   ("roadworks") over NDW's own line; slow segments ("slow" below 60% of the normal
   speed, "jam" below 35%, always at least 20 s of delay) over the route shape
   of the match, because NDW's line is usually just start and end. Rebuilt every
   cycle, on `:9100/traffic.geojson` (gzip if the client wants it); the web pod's
   nginx passes it on as `/traffic`.
5. **Clearing.** Valhalla has no expiry. Every cycle, everything the previous
   cycle wrote that no longer has a measurement goes back to "unknown", and at
   startup the whole file is emptied.

Live speeds and closures only count in Valhalla with a departure time of now:
`date_time.type: 0` ("depart now"), or `type: 3` with the current time -- the app
uses the latter, because only then do you also get alternatives. Without
`date_time` Valhalla drives straight through a closure.

## Development

```bash
pip install -e '.[dev]'
pytest && ruff check .
# against a real Valhalla (Andorra tileset), see ci/:
python ../ci/e2e/traffic_live.py /path/to/traffic.tar http://localhost:8002
```

Settings: see the docstring of `main.py`. Metrics on `[::]:9100/metrics`
(`homemaps_traffic_*`); the chart adds alerts on staleness.

## When a feed fails

NDW renames feeds, serves a truncated file now and then, and is sometimes
simply down. What happens then:

- **Travel times** fail the cycle. The speeds and closures of the last good
  cycle stay until `STALE_SECONDS` (three intervals, at least 15 minutes);
  after that they are cleared from `traffic.tar` and the map layer answers 503.
  Valhalla has no expiry of its own, so without this an old jam would stay in
  every route.
  The same goes for a file that arrives but was published longer ago than
  that: NDW makes this feed every minute, and an old file served with a 200
  is not live traffic.
- **Closures** keep the measures of the last good fetch for the same time; the
  speeds are written either way.
- **Everything else** (incidents, bridges, maximum speeds, the planning feed, the
  measurement site configuration) only costs that part.
- **MSI signs** are withdrawn from the layer after five minutes without a good
  fetch.
- A single record that cannot be read is skipped, not the feed.

Per feed there is `homemaps_traffic_feed_last_success_timestamp_seconds{feed=…}`
(0 = never arrived) and `homemaps_traffic_feed_failures_total{feed=…}`.
`/healthz` answers 503 when the cycle or the MSI loop has stopped running
(not when NDW is down: a restart does not help against that); the chart uses
it as liveness probe.
