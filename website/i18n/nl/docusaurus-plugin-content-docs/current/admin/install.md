---
sidebar_position: 1
title: De server installeren
description: Installeer HomeMaps op Kubernetes met de Helm chart, start de bouwtaken en koppel de apps.
---

# De server installeren

Alles wat de app nodig heeft komt uit één Helm chart: kaarttegels (planetiler
en tileserver-gl), routes (Valhalla), zoeken (Photon), de web-app (nginx) en
de verkeersimporter. Alles staat onder één hostnaam; de web-pod stuurt
`/valhalla`, `/geocode`, `/tiles` en `/traffic` door naar de andere services,
zodat alleen die ene pod van buiten bereikbaar is.

## Wat je nodig hebt

- Een Kubernetes-cluster met een Gateway API-gateway of een ingress
  controller, en een storage class. Drie volumes van 20 GiB (tegels, Valhalla,
  Photon) en een kladvolume van 40 GiB voor de tegelbouw zijn de standaard voor
  Nederland.
- Geheugen voor de bouwtaken: planetiler wil rond de 6 GiB, de Valhalla-bouw
  tot 8 GiB. Ze draaien één keer per maand en zijn tussendoor weg.
- Voor Nederland ongeveer anderhalf uur bouwtijd op een paar cores.

## Installeren

```bash
helm install homemaps oci://ghcr.io/tijder/charts/homemaps -n homemaps --create-namespace \
  --set httpRoute.enabled=true --set 'httpRoute.hostnames={maps.example.org}' \
  --set 'httpRoute.parentRefs[0].name=public-gateway'
```

Met een ingress controller in plaats van de Gateway API:

```bash
  --set ingress.enabled=true --set 'ingress.hosts={maps.example.org}' \
  --set ingress.className=nginx
```

De NOTES van de chart geven je dan twee commando's. Op een verse installatie
is er nog geen kaart en geen routegraaf; de pods wachten erop. Start de twee
bouwtaken één keer met de hand:

```bash
kubectl -n homemaps create job --from=cronjob/homemaps-tiles-planetiler planetiler-initial
kubectl -n homemaps create job --from=cronjob/homemaps-valhalla-build valhalla-initial
```

Daarna verversen ze zichzelf op hun schema (standaard de vijfde en zesde van
de maand). Photon haalt zijn eigen kant-en-klare index op.

```bash
helm test homemaps -n homemaps
```

controleert de vier proxy-paden. Open daarna `https://maps.example.org`.

## De apps koppelen

De web-app gebruikt zijn eigen origin, niets in te stellen. De Android- en
iOS-apps vragen bij de eerste start om het adres: `maps.example.org`. Achter
een inlogproxy kunnen de telefoon-apps niet inloggen; houd de API-paden zonder
bereikbaar, of gebruik de web-app.

## Upgraden

```bash
helm upgrade homemaps oci://ghcr.io/tijder/charts/homemaps -n homemaps --reuse-values
```

Elke release publiceert de chart en de images met dezelfde versie. De volumes
blijven bij een uninstall bewaard (`helm.sh/resource-policy: keep`): een bouw
duurt uren, een `helm uninstall` mag die niet weggooien.

## Beveiliging

De pods draaien als een vaste niet-root gebruiker zonder capabilities en met
een seccomp-profiel. Een NetworkPolicy laat alleen de namespace van de gateway
bij de web-pod (`networkPolicy.ingressNamespaces`), en alleen de web-pod bij de
andere services.
