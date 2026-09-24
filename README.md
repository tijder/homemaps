# HomeMaps

Een eigen kaart- en routeplanner: alles wat de app nodig heeft draait op je eigen
cluster, en tijdens het gebruik gaat er niets naar buiten.

| map | wat |
|---|---|
| `app/` | Flutter-app (web, Android en iOS): kaart, zoeken, routes plannen, je locatie, navigatie met stem en verkeerslaag |
| `chart/homemaps/` | Helm chart: tiles (planetiler + tileserver-gl), routing (Valhalla), zoeken (Photon), de web-app, en de verkeersimporter |
| `importer/` | Python-sidecar die live snelheden en afsluitingen van NDW in Valhalla's `traffic.tar` schrijft ([README](importer/README.md)) |
| `docker/web/` | nginx-image rond de web-build; proxyt `/valhalla`, `/geocode`, `/tiles` en `/verkeer` |
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

Alles hangt onder één hostnaam. De Android- en iOS-app vragen bij de eerste start om dat
adres; de web-app gebruikt zijn eigen origin.

## Ontwikkelen

```bash
cd app && flutter pub get && flutter test
cd app && flutter build web --release --wasm --no-web-resources-cdn
ci/up.sh            # de hele chart in kind, met toetsen (KIND_EXPERIMENTAL_PROVIDER=podman kan)
ci/up.sh --weg
cd importer && pip install -e '.[dev]' && pytest && ruff check .
```

Navigatie testen zonder te rijden: open de web-app met
`?simulatie=52.186,5.7035` (het startpunt), eventueel `&snelheid=20` (m/s) en
`&mis=2` (bij manoeuvre 2 rechtdoor, zodat hij herberekent). Een nagemaakte GPS
rijdt dan de route af. `&naar=52.17,5.60` (en `&van=`) opent meteen een route;
dat werkt ook zonder simulatie, om een route als link te delen.

`ci/up.sh` toetst met Playwright (als dat er is) ook de app in een browser:
`ci/e2e/app_browser.py` plant een route in Andorra, navigeert met de
nagemaakte GPS en stopt. Schermafdrukken komen in `ci/e2e/uitvoer/`.

Het app-icoon is code: `python3 app/tool/maak_icoon.py` tekent het, daarna maakt
`dart run flutter_launcher_icons` er de Android-, iOS- en web-iconen van.

Na een wijziging aan routes of vertalingen: `flutter gen-l10n` en
`dart run build_runner build`; het resultaat is ingecheckt en de CI controleert dat.

## iOS

Zonder Mac: de CI bouwt de app op `macos-latest`. Bij elke PR alleen of hij
compileert (`flutter build ios --no-codesign`); bij een release ondertekent
`release.yml` hem met een App Store Connect API-sleutel (secrets
`APP_STORE_CONNECT_KEY_P8`, `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, team `68TXJMQZH4`) en zet hem op TestFlight. De
ipa hangt ook aan de GitHub-release, maar is alleen via TestFlight te installeren.

Eenmalig bij Apple: de App ID `nl.tijder.homemaps` en een app in App Store
Connect. Zelf bouwen kan alleen op een Mac met een signing team in Xcode
(`cd app && flutter build ios --release`).

`geo:`-links uit andere apps openen HomeMaps op iOS niet: iOS kent die niet
systeembreed.

## Wat bewezen is, en hoe

| | toets |
|---|---|
| wasm-build + APK met `maplibre_gl` en zelfgehoste maplibre-gl-js | lokaal gebouwd; web in headless Chromium, geen verzoek naar buiten |
| Valhalla non-root, read-only rootfs, dual-stack | podman, Andorra en heel Nederland (tiles in 1m38 op 12 cores) |
| live verkeer zonder herstart | `ci/e2e/verkeer_live.py`: file -> andere route, afsluiting -> omweg, wissen -> terug |
| NDW op echte schaal | 96,3% van 67.227 segmenten gematcht, 77% van de afsluitingen; eerste ronde 67 s, daarna 2,4 s |
| de chart | `ci/up.sh` groen in kind: bouwjobs, `helm test`, live verkeer uit de nagemaakte feed |
| de app tegen de chart | headless Chromium, breed en smal: zoeken, route, hoogteprofiel, instructies |
| navigatie | unittests op een echte Valhalla-route (volgen, aankondigen, herberekenen) en de simulatie in headless Chromium; nog niet onderweg op een toestel |

## Nog open

- **De APK is alleen gebouwd, niet op een toestel gedraaid.** Releases worden
  ondertekend met één vaste sleutel (secrets `ANDROID_KEYSTORE` en
  `ANDROID_KEYSTORE_WACHTWOORD`); raak je die kwijt, dan kan een nieuwe versie
  niet meer over een oude heen.
- **De iOS-app** is alleen in de CI gebouwd: locatie op de achtergrond, stem met
  het scherm uit en de kaartgebaren moeten nog op een iPhone bekeken worden.
- **Navigatie op Android** is niet op een toestel gereden: stem, voorgronddienst
  met het scherm uit en de GPS van een echte telefoon zijn alleen in code en
  tests gedekt.
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
