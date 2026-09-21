# HomeMaps

Een eigen kaart- en routeplanner: alles wat de app nodig heeft draait op je eigen
cluster, en tijdens het gebruik gaat er niets naar buiten.

| map | wat |
|---|---|
| `app/` | Flutter-app (web en Android): kaart, zoeken, routes plannen |
| `chart/homemaps/` | Helm chart: tiles (planetiler + tileserver-gl), routing (Valhalla), zoeken (Photon), de web-app, en de verkeersimporter |
| `importer/` | Python-sidecar die live snelheden en afsluitingen van NDW in Valhalla's `traffic.tar` schrijft ([README](importer/README.md)) |
| `docker/web/` | nginx-image rond de web-build; proxyt `/valhalla`, `/geocode` en `/tiles` |
| `ci/` | kind-testbed (`up.sh`) met Andorra en een nagemaakte NDW-feed |

## Installeren

```bash
helm install homemaps oci://ghcr.io/tijder/charts/homemaps -n homemaps --create-namespace \
  --set httpRoute.enabled=true --set 'httpRoute.hostnames={maps.example.org}' \
  --set 'httpRoute.parentRefs[0].name=public-gateway'
```

Daarna één keer de twee bouwjobs starten (de NOTES van de chart geven de
commando's); tot die klaar zijn wachten de pods. Standaard is het gebied
Nederland; `gebied.*` en `photon.dbUrl` in de values kiezen een ander.

Alles hangt onder één hostnaam. De Android-app vraagt bij de eerste start om dat
adres; de web-app gebruikt zijn eigen origin.

## Ontwikkelen

```bash
cd app && flutter pub get && flutter test
cd app && flutter build web --release --wasm --no-web-resources-cdn
ci/up.sh            # de hele chart in kind, met toetsen (KIND_EXPERIMENTAL_PROVIDER=podman kan)
ci/up.sh --weg
cd importer && pip install -e '.[dev]' && pytest && ruff check .
```

Het app-icoon is code: `python3 app/tool/maak_icoon.py` tekent het, daarna maakt
`dart run flutter_launcher_icons` er de Android- en web-iconen van.

Na een wijziging aan routes of vertalingen: `flutter gen-l10n` en
`dart run build_runner build`; het resultaat is ingecheckt en de CI controleert dat.

## Wat bewezen is, en hoe

| | toets |
|---|---|
| wasm-build + APK met `maplibre_gl` en zelfgehoste maplibre-gl-js | lokaal gebouwd; web in headless Chromium, geen verzoek naar buiten |
| Valhalla non-root, read-only rootfs, dual-stack | podman, Andorra en heel Nederland (tiles in 1m38 op 12 cores) |
| live verkeer zonder herstart | `ci/e2e/verkeer_live.py`: file -> andere route, afsluiting -> omweg, wissen -> terug |
| NDW op echte schaal | 96,3% van 67.227 segmenten gematcht, 77% van de afsluitingen; eerste ronde 67 s, daarna 2,4 s |
| de chart | `ci/up.sh` groen in kind: bouwjobs, `helm test`, live verkeer uit de nagemaakte feed |
| de app tegen de chart | headless Chromium, breed en smal: zoeken, route, hoogteprofiel, instructies |

## Nog open

- **De APK is alleen gebouwd, niet op een toestel gedraaid**, en wordt met de
  debug-sleutel ondertekend. Voor een installeerbare release: een keystore als
  secret en een `signingConfig` in `app/android/app/build.gradle.kts`.
- **NDW-voorwaarden**: de repo bevat geen NDW-data (de testfeed is nagemaakt), maar
  wie de importer draait gebruikt NDW's open data onder hun voorwaarden
  (ndw.nu/copyright).
- **De laatste 3,7% van de segmenten** matcht niet (route veel langer dan de lijn:
  het punt viel op een parallelweg of de andere rijbaan). Snappen op rijrichting
  of een ruimere zoekstraal is de volgende stap als dat ertoe doet.
- **Puntmetingen en de planningsfeed** van NDW worden niet gebruikt; de
  reistijden dekken hoofd- en provinciale wegen.
- **tileserver-gl 5.6.0 heeft geen metrics**; alleen de importer heeft een
  ServiceMonitor en alerts.
- **Uitrol naast `routes`/`tiles` op hilversum** is een aparte stap.

De oorspronkelijke opzet staat in [`doc/bouwplan.md`](doc/bouwplan.md). Commits
volgen [Conventional Commits](CONTRIBUTING.md); de releaseversie wordt daaruit
afgeleid.
