# HomeMaps

Your own map and route planner: everything the app needs runs on your own
cluster, and nothing goes out while it's in use.

| dir | what |
|---|---|
| `app/` | Flutter app (web, Android and iOS, in English and Dutch): map, search, route planning, your location, navigation with voice and a traffic layer |
| `chart/homemaps/` | Helm chart: tiles (planetiler + tileserver-gl), routing (Valhalla), search (Photon), the web app, and the traffic importer |
| `importer/` | Python sidecar that writes live speeds and closures from NDW into Valhalla's `traffic.tar` ([README](importer/README.md)) |
| `docker/web/` | nginx image around the web build; proxies `/valhalla`, `/geocode`, `/tiles` and `/traffic` |
| `ci/` | kind test bed (`up.sh`) with Andorra and a fake NDW feed |

## Installing

```bash
helm install homemaps oci://ghcr.io/tijder/charts/homemaps -n homemaps --create-namespace \
  --set httpRoute.enabled=true --set 'httpRoute.hostnames={maps.example.org}' \
  --set 'httpRoute.parentRefs[0].name=public-gateway'
```

Then start the two build jobs once (the chart's NOTES give the
commands); the pods wait until they're done. The default region is
the Netherlands; `region.*` and `photon.dbUrl` in the values pick another one.

Everything lives under one host name. The Android and iOS apps ask for that
address on first start; the web app uses its own origin.

## Development

```bash
cd app && flutter pub get && flutter test
cd app && flutter build web --release --wasm --no-web-resources-cdn
ci/up.sh            # the whole chart in kind, with tests (KIND_EXPERIMENTAL_PROVIDER=podman works)
ci/up.sh --down
cd importer && pip install -e '.[dev]' && pytest && ruff check .
```

Testing navigation without driving: open the web app with
`?simulate=52.186,5.7035` (the starting point), optionally `&speed=20` (m/s) and
`&miss=2` (go straight on at maneuver 2, so it reroutes). A fake GPS
then drives the route. `&to=52.17,5.60` (and `&from=`) opens a route right away;
that also works without simulation, to share a route as a link.

`ci/up.sh` also tests the app in a browser with Playwright (if available):
`ci/e2e/app_browser.py` plans a route in Andorra, navigates with the
fake GPS and stops. Screenshots go to `ci/e2e/output/`.

The app icon is code: `python3 app/tool/make_icon.py` draws it, then
`dart run flutter_launcher_icons` turns it into the Android, iOS and web icons.

After a change to routes or translations: `flutter gen-l10n` and
`dart run build_runner build`; the result is checked in and CI verifies it.

## iOS

No Mac needed: CI builds the app on `macos-latest`. On every PR only whether it
compiles (`flutter build ios --no-codesign`); on a release
`release.yml` signs it with an App Store Connect API key (secrets
`APP_STORE_CONNECT_KEY_P8`, `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, team `68TXJMQZH4`) and puts it on TestFlight. The
ipa is also attached to the GitHub release, but can only be installed via TestFlight.

One-time setup at Apple: the App ID `nl.g4d.homemaps` and an app in App Store
Connect. Building it yourself only works on a Mac with a signing team in Xcode
(`cd app && flutter build ios --release`).

The screenshots for the App Store (iPhone 6.7" and iPad 12.9", Dutch and
English) come from the web app in the kind cluster: `ci/e2e/screenshots.py`, on
main in the e2e job. On a release `ci/appstore/upload.py` puts them on the version
that is ready in App Store Connect (or creates it); they're also attached as a zip to
the GitHub release. Locally: `SCREENSHOTS=1 ci/up.sh`, and
`python3 ci/appstore/upload.py ci/e2e/output/appstore <version> --dry-run` to see
what would happen.

`geo:` links from other apps don't open HomeMaps on iOS: iOS doesn't support them
system-wide.

## Android Auto and CarPlay

The same navigation on the car's screen. Dart stays in charge (planning,
guidance, the voice); `app/lib/car/car_bridge.dart` mirrors it to the car
over the Pigeon contract in `app/pigeons/car.dart` (regenerate with
`dart run pigeon --input pigeons/car.dart`; the output is checked in). Native
draws the map with MapLibre, the same SDK maplibre_gl brings for the phone,
and fills the car's templates: home, work and recent places, search, a route
preview, and turn-by-turn with the next maneuver, lanes, speed limit and ETA.

**Android Auto** (`app/android/.../car/`): a `CarAppService` in the
navigation category; the map is a `Presentation` on a virtual display on the
car's surface. Test without a car with the Desktop Head Unit: install it in
the SDK Manager ("Android Auto Desktop Head Unit Emulator"), on the phone turn
on developer settings in the Android Auto app and "Start head unit server",
then `adb forward tcp:5277 tcp:5277` and start `desktop-head-unit`. Real head
units only accept apps installed from Play (internal testing is enough), or
"Unknown sources" in the Android Auto developer settings. The test drive Play
requires: `adb shell dumpsys activity service nl.g4d.homemaps/.car.HomemapsCarAppService AUTO_DRIVE`
(a fake GPS then drives the route). In Play Console the app needs the Android
Auto declaration, category Navigation.

**CarPlay** (`app/ios/Runner/CarPlay/`): a `CPTemplateApplicationScene` with
`CPMapTemplate` and a `CPNavigationSession`; the map is an `MLNMapView` in the
CarPlay window. It needs Apple's `com.apple.developer.carplay-maps`
entitlement (request it at developer.apple.com/carplay, category Navigation;
weeks to months). Once granted, add the CarPlay Navigation capability to the
App ID and `<key>com.apple.developer.carplay-maps</key><true/>` to
`app/ios/Runner/Runner.entitlements`; the release workflow signs with it. Until
then it only runs in the iOS Simulator (I/O > External Displays > CarPlay), on
an iOS 18 simulator: the 26.4+ simulator crashes on `CPMapTemplate`.

## What has been proven, and how

| | test |
|---|---|
| wasm build + APK with `maplibre_gl` and self-hosted maplibre-gl-js | built locally; web in headless Chromium, no outgoing requests |
| Valhalla non-root, read-only rootfs, dual-stack | podman, Andorra and all of the Netherlands (tiles in 1m38 on 12 cores) |
| live traffic without a restart | `ci/e2e/traffic_live.py`: jam -> different route, closure -> detour, clear -> back |
| NDW at real scale | 96.3% of 67,227 segments matched, 77% of the closures; first cycle 67 s, then 2.4 s |
| the chart | `ci/up.sh` green in kind: build jobs, `helm test`, live traffic from the fake feed |
| the app against the chart | headless Chromium, wide and narrow: search, route, elevation profile, instructions |
| navigation | unit tests on a real Valhalla route (tracking, announcing, rerouting) and the simulation in headless Chromium; not yet on the road on a device |

## Still open

- Android Auto and CarPlay have been built and unit-tested (the bridge), but not
  yet driven on a head unit or in the CarPlay Simulator; CarPlay waits for the
  entitlement.
- **The APK has only been built, not run on a device.** Releases are
  signed with one fixed key (secrets `ANDROID_KEYSTORE` and
  `ANDROID_KEYSTORE_WACHTWOORD`); if you lose it, a new version can no longer
  be installed over an old one.
- **The iOS app** has only been built in CI: background location, voice with
  the screen off and the map gestures still need to be checked on an iPhone.
- **Navigation on Android** hasn't been driven on a device: voice, foreground service
  with the screen off and the GPS of a real phone are only covered in code and
  tests.
- **NDW terms**: the repo contains no NDW data (the test feed is fake), but
  whoever runs the importer uses NDW's open data under their terms
  (ndw.nu/copyright).
- **The last 3.7% of the segments** don't match (route much longer than the line:
  the point fell on a parallel road or the other carriageway). Snapping by driving
  direction or a larger search radius is the next step if that matters.
- **Point measurements and the planning feed** from NDW are not used; the
  travel times cover main and provincial roads.
- **tileserver-gl 5.6.0 has no metrics**; only the importer has a
  ServiceMonitor and alerts.
- **Rollout next to `routes`/`tiles` on hilversum** is a separate step.

The original design is in [`doc/design.md`](doc/design.md). Commits
follow [Conventional Commits](CONTRIBUTING.md); the release version is derived
from them.
