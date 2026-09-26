---
sidebar_position: 1
title: Install the server
description: Install HomeMaps on Kubernetes with the Helm chart, start the build jobs, and connect the apps.
---

# Install the server

Everything the app needs comes from one Helm chart: map tiles (planetiler and
tileserver-gl), routing (Valhalla), search (Photon), the web app (nginx) and
the traffic importer. Everything lives under one hostname; the web pod proxies
`/valhalla`, `/geocode`, `/tiles` and `/traffic` to the other services, so
only that one pod is reachable from outside.

## What you need

- A Kubernetes cluster with a Gateway API gateway or an ingress controller,
  and a storage class. Three volumes of 20 GiB (tiles, Valhalla, Photon) and
  a 40 GiB scratch volume for the tile build are the defaults for the
  Netherlands.
- Memory for the build jobs: planetiler wants around 6 GiB, the Valhalla
  build up to 8 GiB. They run once a month and are gone in between.
- For the Netherlands, about an hour and a half of build time on a few cores.

## Install

```bash
helm install homemaps oci://ghcr.io/tijder/charts/homemaps -n homemaps --create-namespace \
  --set httpRoute.enabled=true --set 'httpRoute.hostnames={maps.example.org}' \
  --set 'httpRoute.parentRefs[0].name=public-gateway'
```

With an ingress controller instead of the Gateway API:

```bash
  --set ingress.enabled=true --set 'ingress.hosts={maps.example.org}' \
  --set ingress.className=nginx
```

The chart's NOTES then give you two commands. On a fresh install there is no
map and no routing graph yet; the pods wait for them. Start the two build jobs
once by hand:

```bash
kubectl -n homemaps create job --from=cronjob/homemaps-tiles-planetiler planetiler-initial
kubectl -n homemaps create job --from=cronjob/homemaps-valhalla-build valhalla-initial
```

After that they refresh themselves on their schedule (the fifth and sixth of
the month by default). Photon downloads its own ready-made index.

```bash
helm test homemaps -n homemaps
```

checks the four proxy paths. Then open `https://maps.example.org`.

## Connect the apps

The web app uses its own origin, nothing to configure. The Android and iOS
apps ask for the address on first start: `maps.example.org`. Behind an
authentication proxy the phone apps cannot sign in; keep the API paths
reachable without one, or use the web app.

## Upgrade

```bash
helm upgrade homemaps oci://ghcr.io/tijder/charts/homemaps -n homemaps --reuse-values
```

Every release publishes the chart and the images with the same version. The
volumes are kept on uninstall (`helm.sh/resource-policy: keep`): a build takes
hours, a `helm uninstall` should not throw it away.

## Security

The pods run as a fixed non-root user with all capabilities dropped and a
seccomp profile. A NetworkPolicy lets only the gateway's namespace reach the
web pod (`networkPolicy.ingressNamespaces`), and only the web pod the other
services.
