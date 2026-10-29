# CLAUDE.md

## Before pushing app changes

CI (`.github/workflows/workflow.yml`, step "Generated code is up to date")
regenerates all generated code and fails on any diff. Run the same in `app/`
before pushing, and commit what changes:

```sh
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
dart run pigeon --input pigeons/car.dart
dart format lib test
git diff --exit-code -- lib android/app/src/main/kotlin ios/Runner/CarPlay
```

Then `flutter analyze` and `flutter test`. The iOS/CarPlay Swift code only
compiles in CI.

## Updating dependencies

A dependency update covers: Flutter (pinned exactly in `app/pubspec.yaml`,
CI reads it from there) and the pub packages, the Android Gradle plugin,
Kotlin, Gradle and the libraries in `app/android/app/build.gradle.kts`, the
website's npm packages, the Docker base images, the images in the chart
(`chart/homemaps/values.yaml` and `templates/`), and the GitHub Actions.

Bumping a code generator (pigeon, build_runner, ...) changes the generated
files, if only the version in their header: run the steps above.

## Releasing

`release.yml` only releases when the "Build and Test" run of HEAD is green,
so wait for that run before starting a release by hand.
