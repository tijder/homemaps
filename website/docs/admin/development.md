---
sidebar_position: 5
title: Development
description: Building the app, the chart and the importer, and how releases are made.
---

# Development

The repository is a monorepo: [github.com/tijder/homemaps](https://github.com/tijder/homemaps).

| directory | what |
|---|---|
| `app/` | Flutter app (web, Android, iOS), Android Auto and CarPlay |
| `chart/homemaps/` | the Helm chart |
| `importer/` | the traffic importer (Python) |
| `docker/web/` | the nginx image around the web build |
| `website/` | this site |
| `ci/` | a kind test bed with Andorra and a fake NDW feed |

## Build and test

```bash
cd app && flutter pub get && flutter test
cd app && flutter build web --release --wasm --no-web-resources-cdn
ci/up.sh                # the whole chart in kind, with tests
cd importer && pip install -e '.[dev]' && pytest && ruff check .
cd website && npm ci && npm run build
```

`ci/up.sh` builds the web image, creates a kind cluster, installs the chart
with Andorra as the region and a fake NDW feed, waits for the build jobs, runs
`helm test`, checks that live traffic changes a route, and drives the app in a
headless browser with a fake GPS. `SCREENSHOTS=1 ci/up.sh` also takes the
screenshots for the App Store and this site.

Testing navigation without driving: open the web app with
`?simulate=52.186,5.7035` (the starting point), optionally `&speed=20` (m/s)
and `&miss=2` (go straight on at manoeuvre 2, so it reroutes).

## Releases

Commits follow Conventional Commits (`feat(app): …`, `fix(chart): …`); CI
rejects other subjects. A nightly workflow releases when there are new
commits and the build of `main` is green: `fix` bumps the patch version,
`feat` the minor, `!` the major. It signs the APK and the iOS app, uploads to
TestFlight, pushes the three images and the chart with that version, tags the
commit and writes the release notes from the commits.

## iOS without a Mac

CI builds the iOS app on macOS runners: on every pull request whether it
compiles, on a release signed with an App Store Connect API key. The App
Store screenshots come from the web app in the kind cluster, in the sizes
Apple wants, and are uploaded to App Store Connect on a release.
