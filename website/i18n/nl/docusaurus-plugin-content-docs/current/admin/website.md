---
sidebar_position: 4
title: Deze website
description: Draai deze documentatiesite zelf, als Docker-image of als onderdeel van de Helm chart.
---

# Deze website

Deze site wordt bij elke release gebouwd als de Docker-image
`ghcr.io/tijder/homemaps-website`, naast de web-app en de verkeersimporter.
Hij heeft dezelfde tags (`X.Y.Z`, `X.Y`, `latest`) en bevat de screenshots van
die release. De image is statische bestanden achter nginx op poort 8080, als
niet-root gebruiker.

## In de Helm chart

De website is een optionele component van de chart, standaard uit. Hij krijgt
een eigen hostnaam naast die van de app:

```yaml
website:
  enabled: true
  hostnames: [homemaps.example.org]
  config:
    appUrl: https://maps.example.org       # de knop "Open de web-app"
    testflightUrl: https://testflight.apple.com/join/XXXX
    playStoreUrl: ""
    appStoreUrl: ""
```

Met `httpRoute.enabled` of `ingress.enabled` voegt de chart een tweede route
toe voor die hostnamen. `appUrl` is standaard de eerste hostnaam van de app.

## Runtime-configuratie

De site wordt één keer gebouwd en draait onder elke hostnaam:

- **Site-URL.** Canonical links, de taalalternatieven en de sitemap hebben het
  absolute adres nodig. nginx vult het per verzoek in uit de headers `Host` en
  `X-Forwarded-Proto`, of uit de omgevingsvariabele `SITE_URL` als die gezet is
  (`website.siteUrl` in de chart).
- **Links.** `/config.json` bevat de adressen achter de knoppen op de landing
  pagina. Elk veld is optioneel; een leeg veld verbergt zijn knop. Zonder het
  bestand zijn alleen de GitHub-knoppen te zien.

## Zonder Kubernetes

```bash
docker run -p 8080:8080 \
  -e SITE_URL=https://homemaps.example.org \
  -v ./config:/usr/share/nginx/html/config:ro \
  ghcr.io/tijder/homemaps-website:latest
```

met `config/config.json`:

```json
{"appUrl": "https://maps.example.org", "testflightUrl": ""}
```

## Meeschrijven aan de documentatie

De bron is `website/` in de repository: Docusaurus, Engels in `docs/`,
Nederlands in `i18n/nl/`. Elke pagina heeft een link **Bewerk deze pagina**.
`npm start` draait hem lokaal; `npm run start -- --locale nl` de Nederlandse kant.
