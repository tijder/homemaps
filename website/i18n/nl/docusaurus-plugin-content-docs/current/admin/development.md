---
sidebar_position: 5
title: Ontwikkelen
description: De app, de chart en de importer bouwen, en hoe releases gemaakt worden.
---

# Ontwikkelen

De repository is een monorepo: [github.com/tijder/homemaps](https://github.com/tijder/homemaps).

| map | wat |
|---|---|
| `app/` | Flutter-app (web, Android, iOS), Android Auto en CarPlay |
| `chart/homemaps/` | de Helm chart |
| `importer/` | de verkeersimporter (Python) |
| `docker/web/` | de nginx-image rond de web-build |
| `website/` | deze site |
| `ci/` | een kind-testomgeving met Andorra en een nep-NDW-feed |

## Bouwen en testen

```bash
cd app && flutter pub get && flutter test
cd app && flutter build web --release --wasm --no-web-resources-cdn
ci/up.sh                # de hele chart in kind, met tests
cd importer && pip install -e '.[dev]' && pytest && ruff check .
cd website && npm ci && npm run build
```

`ci/up.sh` bouwt de web-image, maakt een kind-cluster, installeert de chart met
Andorra als regio en een nep-NDW-feed, wacht op de bouwtaken, draait
`helm test`, controleert dat actueel verkeer een route verandert, en rijdt de
app in een headless browser met een nep-gps. `SCREENSHOTS=1 ci/up.sh` maakt
ook de screenshots voor de App Store en deze site.

Navigatie testen zonder te rijden: open de web-app met
`?simulate=52.186,5.7035` (het startpunt), eventueel `&speed=20` (m/s) en
`&miss=2` (rechtdoor bij manoeuvre 2, zodat hij herberekent).

## Releases

Commits volgen Conventional Commits (`feat(app): …`, `fix(chart): …`); CI
weigert andere onderwerpregels. Een nachtelijke workflow releaset als er
nieuwe commits zijn en de bouw van `main` groen is: `fix` verhoogt de
patchversie, `feat` de minor, `!` de major. Hij ondertekent de APK en de
iOS-app, uploadt naar TestFlight, pusht de drie images en de chart met die
versie, tagt de commit en schrijft de release notes uit de commits.

## iOS zonder Mac

CI bouwt de iOS-app op macOS-runners: bij elke pull request of hij compileert,
bij een release ondertekend met een App Store Connect API-sleutel. De App
Store-screenshots komen uit de web-app in het kind-cluster, in de maten die
Apple wil, en gaan bij een release naar App Store Connect.
