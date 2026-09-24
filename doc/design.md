# Plan: HomeMaps — your own map and route planner (Flutter + Helm + CI)

## Context

Currently tiles (tileserver-gl + planetiler) and routing (GraphHopper + Photon + a
patched graphhopper-maps) run as separate raw YAML in `new-cluster`. GraphHopper can't do
real-time traffic; Valhalla can. Goal: one self-contained, reusable project with its
own Flutter app, a Helm chart that delivers the whole backend, and an NDW importer that
puts live speeds and closures into Valhalla. CI modeled on
`ister-app/player`.

**Decisions (yours):** Valhalla · NDW import included from the start · app = web + Android ·
scope "planning" (no turn-by-turn) · Photon in the chart · importer in Python ·
the Netherlands, configurable · owner `tijder`.

**Name: `homemaps`** (`~/Projecten/homemaps`, `github.com/tijder/homemaps`,
`ghcr.io/tijder/homemaps-*`, app id `nl.g4d.homemaps`). No GitHub repo with exactly
that name, no existing app found. Fallback: `kaartroute`. The name lives in one
place per component (pubspec, Chart.yaml, workflow env), so renaming stays cheap.

## Repo layout (monorepo)

```
app/             Flutter (android/, web/), lib/{l10n,models,providers,router,screens,services,utils,widgets}
docker/web/      Dockerfile + nginx/default.conf.template (nginx-unprivileged, envsubst)
importer/        Python: src/homemaps_traffic/{traffictile,tarindex,datex3,matcher,main}.py, tests/, Dockerfile
chart/homemaps/  Chart.yaml, values.yaml, values.schema.json, templates/, tests/
ci/              up.sh (kind), values-andorra.yaml, fixtures
.github/workflows/{workflow.yml,release.yml}
README.md, CONTRIBUTING.md (conventional commits), renovate.json
```

## Components

**App** — conventions from `~/Projecten/managevity` and `dutch-warnings`: riverpod 3,
auto_route 11, dio, hive_ce, l10n with `app_en.arb` as the template + `app_nl.arb`,
flutter_lints, pubspec with an exactly pinned `flutter: 3.47.5`.
- Map: **`maplibre_gl`** (0.27.x, web + Android, wasm-ready). Loads the existing
  vector styles (`osm-bright`, `positron`, `dark-matter`) from tileserver-gl; route as a
  GeoJSON line layer, markers as symbols.
- **Self-host maplibre-gl.mjs + css** in `app/web/` (by default the plugin fetches them from
  unpkg — leaks outside and clashes with `--no-web-resources-cdn`); nginx serves
  `.mjs` as `text/javascript`.
- Search: the Photon logic from `~/Projecten/dockerbuilds/graphhopper-maps/patch.py`
  ported to Dart — `limit=10`, `osm_tag` filters, postcode+house-number regex →
  `/structured`, strict coordinate detection.
- Routing: Valhalla client — profiles car/bike/walk, from/via/to, alternatives
  (Valhalla can only do those without via points → the UI hides them then), instruction list,
  elevation profile (`elevation_interval`), "depart now" = `date_time.type 3` with the current time (live traffic, and unlike
  `type 0` with alternatives).
- Runtime config (API/tile URLs) via a JSON document mounted by the chart, like
  ister's `/.well-known/`; by default derived from `location.origin`, as now.

**Chart** — set up like `ister-app/chart` (schema, HTTPRoute and Ingress optional,
NetworkPolicy, tests/). Components, each one can be turned off:
- `tiles`: 1-to-1 from `new-cluster/namespaces/tiles/` — two planetiler runs +
  `merge.py`, bootstrap of styles/fonts, tileserver-gl. World run can be turned off
  via a value (CI).
- `photon`: from `namespaces/routes/deployment-photon.yaml` (`REGION` value; Service
  `ipFamilies: [IPv4]` if Photon doesn't bind to `::`).
- `valhalla`: official base image `ghcr.io/valhalla/valhalla` 3.9.x with our own
  init scripts (the `-scripted` image wants sudo) — build CronJob: `build_config` →
  `build_elevation` → `build_tiles` → `build_extract --with-traffic`; then the pod goes away.
- `importer`: **sidecar in the Valhalla pod** (same volume, shared mmap), loop every
  N minutes (value, default 5).
- `web`: the Flutter web image.
- Cluster reality built in: non-root + drop ALL, dual-stack listeners, probes that work
  on IPv6, `Recreate` strategy, shared RWO volume Deployment/CronJob, low
  CPU requests for the build jobs.

**Importer (Python)** — format verified from `valhalla/baldr/traffictile.h`:
32-byte header (`<2Q4I`), one uint64 per directed edge (speed ×2 km/h,
breakpoints, congestion); position = tar entry offset + 32 + 8 × `GraphId.id`.
`bp1=0` = unknown, `bp1=255`+speed = whole edge live, speed 0 = closed.
- Sources: NDW **DATEX II v3** (the v2 site table has been frozen since 14-09-2026):
  `reistijden_meetgegevens` + `…configuratie_meetlocaties` (segments as linestrings)
  and `tijdelijke_verkeersmaatregelen_afsluitingen`. Point measurements and the planning feed
  later.
- Matching: linestring → Valhalla `trace_attributes` (`edge.id`); cache per
  site table version + tileset hash, because edge IDs change with every tile build.
- Write **in place via mmap MAP_SHARED**, never rename (Valhalla holds on to the mmap).
  Valhalla has no expiry → every cycle, edges without a fresh measurement go back
  to "unknown".
- Metrics (edges updated, age of the last cycle) on a `/metrics` port +
  ServiceMonitor, so a silent importer turns into an alert.

**CI** — `workflow.yml` after the ister example: `commit-lint` (PR) · `build`
(flutter test, `build apk --release`, `build web --release --wasm
--no-web-resources-cdn`, artifacts `web-build` + `android-apk`) · `importer`
(ruff + pytest) · `chart` (helm lint/template + schema) · `e2e-kind` (chart with
Andorra: tiles without the world run, Valhalla, importer with fixture XML; planetiler
sources cached) · on `main`: `docker` (web and importer image → ghcr) and the chart as
OCI → `ghcr.io/tijder/charts/homemaps`. `release.yml`: semver from conventional
commits, GitHub Release with APK + web tarball, images and chart tagged.

## Build order (risks first, each phase testable on its own)

0. **Repo + wasm spike**: empty app with maplibre_gl, self-hosted mjs, style from
   `tiles.maps.droogers.cloud`, one line + marker. ✔ web wasm build and APK succeed,
   no request to unpkg. If wasm fails: drop `--wasm`, not the library.
1. **Valhalla locally** (podman, Andorra, non-root). ✔ `/route` with alternatives and
   elevation; port visible in `/proc/net/tcp6`.
2. **traffictile writer**. ✔ unit tests on the bit layout; a manually closed
   edge changes the route **without a restart**.
3. **DATEX3 parser + matcher**. ✔ fixture test; on real NL >90% of the
   travel-time segments matched, cycle < 30 s.
4. **Chart**. ✔ lint/template; `ci/up.sh` brings kind with Andorra up green.
5. **App functionality** (search, routing, instructions, elevation profile, l10n). ✔
   unit tests for Photon/Valhalla parsing; manually against the kind backend.
6. **Workflows + release**. ✔ green run on a PR; images and chart on ghcr after main.
7. **Rollout on hilversum** next to the existing `routes`/`tiles` (separate namespace and
   host name, Application in `new-cluster/namespaces/argo-cd/`), measure, and only then
   decide whether the old setup can go. Separate step, in consultation.

## Not yet verified (will surface in phases 0-1)

- A real `--wasm` build with Flutter 3.47.5 and maplibre_gl.
- Whether the Valhalla base image runs as an arbitrary UID; whether Photon binds to `::`.
- NDW license terms (ndw.nu/copyright) — check before the repo goes public.
- Duration of the kind e2e in Actions (goal < 15 min).

## Way of working

Local `git init` in `~/Projecten/homemaps`, conventional commits per phase. **I don't create
a GitHub repo and don't push** — you do that; until then the workflows don't run
and I test locally (flutter, podman, kind, `act` not needed).
