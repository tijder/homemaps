---
sidebar_position: 2
title: Configuratie
description: De chart-values die ertoe doen — regio, opslag, componenten, resources.
---

# Configuratie

Alle values staan in `values.yaml` van de chart; `helm show values
oci://ghcr.io/tijder/charts/homemaps` drukt ze af met commentaar. De
belangrijkste:

## Regio

Standaard is Nederland. Een andere regio is drie values:

```yaml
region:
  name: germany                       # zoals planetilers --area het kent
  pbfUrl: https://download.geofabrik.de/europe/germany-latest.osm.pbf
  bbox: "5.8,47.2,15.1,55.1"          # minlon,minlat,maxlon,maxlat
photon:
  dbUrl: https://download1.graphhopper.com/public/europe/germany/photon-db-germany-1.0-latest.tar.bz2
```

`bbox` bepaalt welke hoogtetegels worden opgehaald (voor het hoogteprofiel en
voor fietsen) en welke landsgrenzen Valhalla gebruikt. Leeg betekent geen
hoogtegegevens. De tegels bevatten altijd de hele wereld op lage zoom onder de
regio (`tiles.planetiler.world`, uit om een bouw te besparen).

De verkeersimporter kent alleen NDW, dus buiten Nederland zet je hem uit:
`valhalla.traffic.enabled=false`.

## Opslag

```yaml
storage:
  storageClassName: longhorn-no-backup   # alles erop is opnieuw te bouwen
  accessMode: ReadWriteOnce
tiles: { size: 20Gi }
valhalla: { size: 20Gi }
photon: { size: 20Gi }
tiles.planetiler.scratchSize: 40Gi
```

## Componenten

Elk van `web`, `tiles`, `valhalla`, `photon` en de `website` kan uit met
`enabled: false`. Een component die uit staat geeft een 502 op zijn pad, niets
ergers. Elke image heeft `repository`, `tag` (leeg = de appVersion van de
chart) en `pullPolicy`.

## Web-app

`web.config` is de runtime-configuratie van de web-app, geserveerd als
`/config.json`. Leeg laten is prima: de app leidt alles af van zijn eigen origin.

## Tegels

- `tiles.styles`: `osm-bright`, `positron`, `dark-matter` (Kaart, Licht,
  Donker in de app).
- `tiles.publicUrl`: leeg laten; tileserver-gl leidt de URL's af van het
  verzoek, zodat meerdere hostnamen werken. De hostnamen van `httpRoute` en
  `ingress` worden automatisch vertrouwd, `tiles.extraAllowedHosts` voegt er
  andere aan toe zoals `localhost` voor een port-forward.
- `tiles.rendererPool`: hoeveel renderers per stijl; de standaard is met opzet
  klein voor een gedeelde node.

## Schema's

`tiles.planetiler.schedule` (`0 2 5 * *`) en `valhalla.build.schedule`
(`0 3 6 * *`), beide `Europe/Amsterdam`. De Valhalla-bouw draait een dag na de
tegels, zodat beide hetzelfde verse OSM-extract gebruiken.

## Resources

Elke component heeft `resources.requests` en `resources.limits`. De bouwtaken
hebben met opzet lage CPU-requests: de request is alleen de drempel om
ingepland te worden, zonder CPU-limiet gebruiken ze wat vrij is.
`valhalla.threads` en `tiles.planetiler.javaOpts` zijn de knoppen voor snelheid.

## Monitoring

`monitoring.serviceMonitor.enabled` en `monitoring.prometheusRule.enabled`
voegen een ServiceMonitor en alerts toe voor de verkeersimporter (de enige
component met metrics); `networkPolicy.monitoringNamespace` laat Prometheus binnen.

## Photon

`photon.heap` is de JVM-heap; houd die ruim onder de geheugenlimiet, OpenSearch
wil daarbuiten nog eens zoveel ruimte. `photon.ipFamilies: [IPv4]` staat er
omdat Photon alleen IPv4 bindt; op een IPv6-first cluster moet de Service dat
expliciet zeggen.
