# Plan: HomeMaps — eigen kaart- en routeplanner (Flutter + Helm + CI)

## Context

Nu draaien tiles (tileserver-gl + planetiler) en routing (GraphHopper + Photon + een
gepatchte graphhopper-maps) als losse raw YAML in `new-cluster`. GraphHopper kan geen
realtime verkeer; Valhalla wel. Doel: één zelfstandig, herbruikbaar project met een
eigen Flutter-app, een Helm chart die de hele backend levert, en een NDW-importer die
live snelheden en afsluitingen in Valhalla zet. CI naar voorbeeld van
`ister-app/player`.

**Besluiten (van jou):** Valhalla · NDW-import meteen mee · app = web + Android ·
scope "plannen" (geen turn-by-turn) · Photon in de chart · importer in Python ·
Nederland, instelbaar · owner `tijder`.

**Naam: `homemaps`** (`~/Projecten/homemaps`, `github.com/tijder/homemaps`,
`ghcr.io/tijder/homemaps-*`, app-id `nl.tijder.homemaps`). Geen GitHub-repo met exact
die naam, geen bestaande app gevonden. Reserve: `kaartroute`. De naam staat op één
plek per onderdeel (pubspec, Chart.yaml, workflow-env), dus hernoemen blijft goedkoop.

## Repo-indeling (monorepo)

```
app/             Flutter (android/, web/), lib/{l10n,models,providers,router,screens,services,utils,widgets}
docker/web/      Dockerfile + nginx/default.conf.template (nginx-unprivileged, envsubst)
importer/        Python: src/homemaps_traffic/{traffictile,tarindex,datex3,matcher,main}.py, tests/, Dockerfile
chart/homemaps/  Chart.yaml, values.yaml, values.schema.json, templates/, tests/
ci/              up.sh (kind), values-andorra.yaml, fixtures
.github/workflows/{workflow.yml,release.yml}
README.md, CONTRIBUTING.md (conventional commits), renovate.json
```

## Onderdelen

**App** — conventies uit `~/Projecten/managevity` en `dutch-warnings`: riverpod 3,
auto_route 11, dio, hive_ce, l10n met `app_nl.arb` als template + `app_en.arb`,
flutter_lints, pubspec met exact gepinde `flutter: 3.47.5`.
- Kaart: **`maplibre_gl`** (0.27.x, web + Android, wasm-ready). Laadt de bestaande
  vectorstijlen (`osm-bright`, `positron`, `dark-matter`) van tileserver-gl; route als
  GeoJSON-lijnlaag, markers als symbols.
- **maplibre-gl.mjs + css zelf hosten** in `app/web/` (de plugin haalt ze standaard van
  unpkg — lekt naar buiten en botst met `--no-web-resources-cdn`); nginx serveert
  `.mjs` als `text/javascript`.
- Zoeken: de Photon-logica uit `~/Projecten/dockerbuilds/graphhopper-maps/patch.py`
  naar Dart — `limit=10`, `osm_tag`-filters, postcode+huisnummer-regex →
  `/structured`, strikte coördinaatherkenning.
- Routing: Valhalla-client — profielen auto/fiets/lopen, van/via/naar, alternatieven
  (Valhalla kan die alleen zonder via-punten → UI verbergt ze dan), instructielijst,
  hoogteprofiel (`elevation_interval`), "vertrek nu" = `date_time.type 0` (live verkeer).
- Runtime-config (API-/tile-URL's) via een door de chart gemount JSON-document, zoals
  ister's `/.well-known/`; standaard afgeleid van `location.origin`, zoals nu.

**Chart** — opzet zoals `ister-app/chart` (schema, HTTPRoute én Ingress optioneel,
NetworkPolicy, tests/). Componenten, elk uit te zetten:
- `tiles`: 1-op-1 uit `new-cluster/namespaces/tiles/` — twee planetiler-runs +
  `samenvoegen.py`, bootstrap van stijlen/fonts, tileserver-gl. Wereld-run via value
  uit te zetten (CI).
- `photon`: uit `namespaces/routes/deployment-photon.yaml` (`REGION`-value; Service
  `ipFamilies: [IPv4]` als Photon niet op `::` bindt).
- `valhalla`: officieel base-image `ghcr.io/valhalla/valhalla` 3.9.x met eigen
  init-scripts (het `-scripted`-image wil sudo) — build-CronJob: `build_config` →
  `build_elevation` → `build_tiles` → `build_extract --with-traffic`; daarna pod weg.
- `importer`: **sidecar in de Valhalla-pod** (zelfde volume, gedeelde mmap), lus elke
  N minuten (value, default 5).
- `web`: de Flutter-web-image.
- Clusterrealiteit ingebouwd: non-root + drop ALL, dual-stack listeners, probes die op
  IPv6 werken, `Recreate`-strategie, gedeeld RWO-volume Deployment/CronJob, lage
  CPU-requests voor de bouwjobs.

**Importer (Python)** — geverifieerd formaat uit `valhalla/baldr/traffictile.h`:
header 32 bytes (`<2Q4I`), per directed edge één uint64 (snelheid ×2 km/u,
breakpoints, congestie); positie = tar-entry-offset + 32 + 8 × `GraphId.id`.
`bp1=0` = onbekend, `bp1=255`+snelheid = hele edge live, snelheid 0 = afgesloten.
- Bronnen: NDW **DATEX II v3** (de v2-sitetabel staat stil sinds 14-09-2026):
  `reistijden_meetgegevens` + `…configuratie_meetlocaties` (segmenten als linestring)
  en `tijdelijke_verkeersmaatregelen_afsluitingen`. Puntmetingen en de planningsfeed
  later.
- Matching: linestring → Valhalla `trace_attributes` (`edge.id`); cache per
  sitetabel-versie + tileset-hash, want edge-ID's wijzigen bij elke tile-build.
- Schrijven **in-place via mmap MAP_SHARED**, nooit rename (Valhalla houdt de mmap
  vast). Valhalla kent geen veroudering → elke ronde edges zonder verse meting terug
  op "onbekend".
- Metrics (edges bijgewerkt, leeftijd laatste ronde) op een `/metrics`-poort +
  ServiceMonitor, zodat een stille importer een alert wordt.

**CI** — `workflow.yml` naar het ister-voorbeeld: `commit-lint` (PR) · `build`
(flutter test, `build apk --release`, `build web --release --wasm
--no-web-resources-cdn`, artifacts `web-build` + `android-apk`) · `importer`
(ruff + pytest) · `chart` (helm lint/template + schema) · `e2e-kind` (chart met
Andorra: tiles zonder wereld-run, Valhalla, importer met fixture-XML; planetiler-
sources gecachet) · op `main`: `docker` (web- en importer-image → ghcr) en chart als
OCI → `ghcr.io/tijder/charts/homemaps`. `release.yml`: semver uit conventional
commits, GitHub Release met APK + web-tarball, images en chart getagd.

## Bouwvolgorde (risico's eerst, elke fase zelfstandig te toetsen)

0. **Repo + wasm-spike**: lege app met maplibre_gl, zelf-gehoste mjs, stijl van
   `tiles.maps.droogers.cloud`, één lijn + marker. ✔ web-wasm-build en APK slagen,
   geen verzoek naar unpkg. Faalt wasm: `--wasm` laten vallen, niet de bibliotheek.
1. **Valhalla lokaal** (podman, Andorra, non-root). ✔ `/route` met alternatieven en
   hoogte; poort zichtbaar in `/proc/net/tcp6`.
2. **traffictile-schrijver**. ✔ unit-tests op de bit-layout; een handmatig afgesloten
   edge verandert de route **zonder herstart**.
3. **DATEX3-parser + matcher**. ✔ fixture-test; op echt NL >90% van de
   reistijdsegmenten gematcht, ronde < 30 s.
4. **Chart**. ✔ lint/template; `ci/up.sh` brengt kind met Andorra groen op.
5. **App-functionaliteit** (zoeken, routing, instructies, hoogteprofiel, l10n). ✔
   unit-tests voor Photon-/Valhalla-parsing; handmatig tegen de kind-backend.
6. **Workflows + release**. ✔ groene run op een PR; images en chart op ghcr na main.
7. **Uitrol op hilversum** naast de bestaande `routes`/`tiles` (aparte namespace en
   hostnaam, Application in `new-cluster/namespaces/argo-cd/`), meten, en pas daarna
   beslissen of de oude opzet weg kan. Aparte stap, in overleg.

## Nog niet geverifieerd (komt in fase 0-1 boven water)

- Echte `--wasm`-build met Flutter 3.47.5 en maplibre_gl.
- Of het Valhalla-base-image als willekeurige UID draait; of Photon op `::` bindt.
- NDW-licentievoorwaarden (ndw.nu/copyright) — checken vóór de repo publiek gaat.
- Duur van de kind-e2e in Actions (doel < 15 min).

## Werkwijze

Lokaal `git init` in `~/Projecten/homemaps`, conventional commits per fase. **Ik maak
geen GitHub-repo aan en push niet** — dat doe jij; tot dan draaien de workflows niet
en toets ik lokaal (flutter, podman, kind, `act` niet nodig).
