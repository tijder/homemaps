# HomeMaps

Een eigen kaart- en routeplanner: alles wat de app nodig heeft draait op je eigen
cluster, en tijdens het gebruik gaat er niets naar buiten.

| map | wat |
|---|---|
| `app/` | Flutter-app (web en Android): kaart, zoeken, routes plannen |
| `chart/homemaps/` | Helm chart: tiles (planetiler + tileserver-gl), routing (Valhalla), zoeken (Photon), de web-app, en de verkeersimporter |
| `importer/` | Python-sidecar die live snelheden en afsluitingen van NDW in Valhalla's `traffic.tar` schrijft |
| `docker/web/` | nginx-image rond de web-build |
| `ci/` | kind-testbed (`up.sh`) met een klein extract |

Status: in opbouw. De bouwvolgorde en wat per fase bewezen moet zijn staat in
[`doc/bouwplan.md`](doc/bouwplan.md).

Commits volgen [Conventional Commits](CONTRIBUTING.md); de releaseversie wordt
daaruit afgeleid.
