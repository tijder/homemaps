# maplibre-gl-js, zelf gehost

Versie **6.4.1**, onveranderd uit het npm-pakket `maplibre-gl` (`dist/`). De versie
moet gelijk zijn aan `kMapLibreJsVersion` in `maplibre_gl_web` (de `@JS`-bindings
zijn tegen precies die build geschreven): bij een bump van `maplibre_gl` hoort een
bump hier.

Waarom hier en niet van de CDN: de plugin haalt de bibliotheek standaard van
unpkg.com. Dan gaat elke kaartweergave naar buiten, en dat is precies wat dit
project niet wil. `lib/main.dart` wijst `MapLibreMap.webLibrarySource` hierheen.

Alle drie de `.mjs`-bestanden zijn nodig: `maplibre-gl.mjs` importeert
`-shared.mjs` en start `-worker.mjs` relatief aan zichzelf. De webserver moet
`.mjs` als `text/javascript` serveren, anders weigert de browser de module.
