---
sidebar_position: 4
title: This website
description: Run this documentation site yourself, as a Docker image or as part of the Helm chart.
---

# This website

This site is built with every release as the Docker image
`ghcr.io/tijder/homemaps-website`, next to the web app and the traffic
importer. It has the same tags (`X.Y.Z`, `X.Y`, `latest`) and contains the
screenshots of that release. The image is static files behind nginx on port
8080, as a non-root user.

## In the Helm chart

The website is an optional component of the chart, off by default. It gets
its own hostname next to the app's:

```yaml
website:
  enabled: true
  hostnames: [homemaps.example.org]
  config:
    appUrl: https://maps.example.org       # the "Open the web app" button
    testflightUrl: https://testflight.apple.com/join/XXXX
    playStoreUrl: ""
    appStoreUrl: ""
```

With `httpRoute.enabled` or `ingress.enabled` the chart adds a second route
for those hostnames. `appUrl` defaults to the first hostname of the app.

## Runtime configuration

The site is built once and runs under any hostname:

- **Site URL.** Canonical links, the language alternates and the sitemap need
  the absolute address. nginx fills it in per request from the `Host` and
  `X-Forwarded-Proto` headers, or from the environment variable `SITE_URL`
  when set (`website.siteUrl` in the chart).
- **Links.** `/config.json` holds the addresses behind the buttons on the
  landing page. Every field is optional; an empty one hides its button.
  Without the file only the GitHub buttons show.

## Without Kubernetes

```bash
docker run -p 8080:8080 \
  -e SITE_URL=https://homemaps.example.org \
  -v ./config:/usr/share/nginx/html/config:ro \
  ghcr.io/tijder/homemaps-website:latest
```

with `config/config.json`:

```json
{"appUrl": "https://maps.example.org", "testflightUrl": ""}
```

## Contributing to the docs

The source is `website/` in the repository: Docusaurus, English in
`docs/`, Dutch in `i18n/nl/`. Every page has an **Edit this page** link.
`npm start` runs it locally; `npm run start -- --locale nl` the Dutch side.
