---
sidebar_position: 3
title: Actueel verkeer
description: Hoe de open data van NDW actuele snelheden, afsluitingen en waarschuwingen wordt in Valhalla en de app.
---

# Actueel verkeer

De verkeersimporter is een sidecar in de Valhalla-pod. Elke paar minuten haalt
hij open data op bij NDW (het Nationaal Dataportaal Wegverkeer), schrijft
actuele snelheden en afsluitingen rechtstreeks in Valhalla's `traffic.tar`, en
bouwt de verkeerslaag voor de app. Valhalla houdt dat bestand open via mmap,
dus een nieuwe route rekent met de files van nu zonder herstart.

Hij kent alleen Nederland. Elders zet je hem uit met
`valhalla.traffic.enabled=false`; de app verbergt dan de verkeerslaag en de optie.

## Wat komt waarvandaan

| NDW-feed | in de app |
|---|---|
| reistijden per segment | actuele snelheid per wegsegment: de route ontwijkt files, en de laag toont langzaam verkeer en files |
| afsluitingen (`carriagewayClosures`, `roadClosed`) | afgesloten segmenten: de route rijdt eromheen; op de kaart met de oorzaak en tot wanneer |
| rijstrookafsluitingen | werkzaamheden op de kaart |
| veiligheidsberichten (ongeval, pechgeval, voorwerp op de weg) | punten op de kaart; een gesproken waarschuwing onderweg |
| planningsfeed wegwerkzaamheden (elk uur) | geplande afsluitingen van de komende 8 dagen, voor **Vertrek › Later** |
| tijdelijke maximumsnelheden | de maximumsnelheid onderweg, als die lager is dan die van OpenStreetMap |
| matrixborden (MSI, elke minuut) | de matrixborden getekend zoals ze staan, en hun snelheid als limiet |
| open bruggen | een waarschuwing onderweg |

Uit het OSM-extract zelf (dat de Valhalla-bouw neerzet) haalt de importer ook
`maxspeed:conditional` (limieten die van het tijdstip afhangen) en de flitsers
en trajectcontroles; die werken in elke regio.

## Values

```yaml
valhalla:
  traffic:
    enabled: true
    intervalSeconds: 300     # een cyclus; de eerste duurt op volle schaal ongeveer een minuut
    closures: true
    msiSeconds: 60           # de matrixborden; 0 zet ze uit
    ndwUrl: https://opendata.ndw.nu
```

## Hoe goed matcht het

Een NDW-segment is bijna altijd alleen een begin- en een eindpunt. De importer
laat Valhalla ertussen routeren en neemt die segmenten als het segment. Op
volle schaal matcht 96% van de 67.000 segmenten, en 77% van de afsluitingen;
de rest zijn punten die op een parallelweg of de andere rijbaan vielen.
Matches worden per tileset gecachet, omdat de segment-id's bij elke
Valhalla-bouw veranderen.

## Voorwaarden

De chart en de images bevatten geen NDW-data. Wie de importer draait gebruikt
de open data van NDW onder de voorwaarden van NDW
([ndw.nu/copyright](https://www.ndw.nu/copyright)).

## Metrics

De importer biedt Prometheus-metrics op poort 9100 (cyclustijd, gematchte
segmenten, afsluitingen, feedfouten); `monitoring.serviceMonitor.enabled`
scrapet ze en `monitoring.prometheusRule.enabled` alarmeert als een feed
verouderd raakt.
