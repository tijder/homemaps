---
sidebar_position: 2
title: Configuration
description: The chart values that matter — region, storage, components, resources.
---

# Configuration

All values live in `values.yaml` of the chart; `helm show values
oci://ghcr.io/tijder/charts/homemaps` prints them with comments. The
important ones:

## Region

The default is the Netherlands. Another region is three values:

```yaml
region:
  name: germany                       # as planetiler's --area knows it
  pbfUrl: https://download.geofabrik.de/europe/germany-latest.osm.pbf
  bbox: "5.8,47.2,15.1,55.1"          # minlon,minlat,maxlon,maxlat
photon:
  dbUrl: https://download1.graphhopper.com/public/europe/germany/photon-db-germany-1.0-latest.tar.bz2
```

`bbox` decides which elevation tiles are fetched (for the elevation profile
and for cycling) and which country boundaries Valhalla uses. Empty means no
elevation data. The tiles always include the whole world at low zoom
underneath the region (`tiles.planetiler.world`, off to save a build).

The traffic importer only knows NDW, so outside the Netherlands turn it off:
`valhalla.traffic.enabled=false`.

## Storage

```yaml
storage:
  storageClassName: longhorn-no-backup   # everything on it can be rebuilt
  accessMode: ReadWriteOnce
tiles: { size: 20Gi }
valhalla: { size: 20Gi }
photon: { size: 20Gi }
tiles.planetiler.scratchSize: 40Gi
```

## Components

Each of `web`, `tiles`, `valhalla`, `photon` and the `website` can be turned
off with `enabled: false`. A component that is off gives a 502 on its path,
nothing worse. Every image has `repository`, `tag` (empty = the chart's
appVersion) and `pullPolicy`.

## Web app

`web.config` is the runtime configuration of the web app, served as
`/config.json`. Leaving it empty is fine: the app derives everything from its
own origin.

## Tiles

- `tiles.styles`: `osm-bright`, `positron`, `dark-matter` (Map, Light, Dark in
  the app).
- `tiles.publicUrl`: leave empty; tileserver-gl derives the URLs from the
  request, so several hostnames work. The hostnames of `httpRoute` and
  `ingress` are trusted automatically, `tiles.extraAllowedHosts` adds
  others such as `localhost` for a port-forward.
- `tiles.rendererPool`: how many renderers per style; the default is small on
  purpose for a shared node.

## Schedules

`tiles.planetiler.schedule` (`0 2 5 * *`) and `valhalla.build.schedule`
(`0 3 6 * *`), both `Europe/Amsterdam`. The Valhalla build runs a day after the
tiles so both use the same fresh OSM extract.

## Resources

Every component has `resources.requests` and `resources.limits`. The build
jobs have low CPU requests on purpose: the request is only the threshold for
getting scheduled, without a CPU limit they use whatever is free.
`valhalla.threads` and `tiles.planetiler.javaOpts` are the knobs for speed.

## Monitoring

`monitoring.serviceMonitor.enabled` and `monitoring.prometheusRule.enabled`
add a ServiceMonitor and alerts for the traffic importer (the only component
with metrics); `networkPolicy.monitoringNamespace` lets Prometheus in.

## Photon

`photon.heap` is the JVM heap; keep it well below the memory limit, OpenSearch
wants as much room again outside it. `photon.ipFamilies: [IPv4]` is there
because Photon only binds IPv4; on an IPv6-first cluster the Service must say
so.
