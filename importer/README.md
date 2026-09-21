# homemaps-traffic

Sidecar bij Valhalla: haalt elke paar minuten NDW's open data op en schrijft die in
Valhalla's `traffic.tar`.

| bron (DATEX II v3, `opendata.ndw.nu`) | wordt |
|---|---|
| `reistijden_meetgegevens` + `reistijden_configuratie_meetlocaties` | live snelheid per edge |
| `tijdelijke_verkeersmaatregelen_afsluitingen` (`carriagewayClosures`, `roadClosed`, nu geldig, niet alleen voor vracht) | afgesloten edges |

## Hoe het werkt

1. **Matchen** (`matcher.py`). Een NDW-segment is bijna altijd alleen een begin- en
   eindpunt. Valhalla routeert van het ene naar het andere; de edges van die route
   (uit `trace_attributes`) zijn het segment. Een route die veel langer is dan de
   lijn zelf wordt verworpen. Het resultaat staat in een cache die aan de tileset
   hangt (`tileset_last_modified`): edge-id's veranderen bij elke tile-build.
2. **Rekenen** (`main.py`). Snelheid = routelengte / reistijd; de normale reistijd
   geeft het congestieniveau. Deelt een edge meerdere segmenten, dan wegen ze naar
   lengte (harmonisch). Een afsluiting neemt de tegenrichting alleen mee op
   dezelfde OSM-way, want dan is het één rijbaan.
3. **Schrijven** (`tarindex.py`, `traffictile.py`). In het bestand zelf, via een
   gedeelde mmap, omdat Valhalla datzelfde bestand via mmap open houdt. Nooit een
   nieuw bestand ernaast zetten en hernoemen.
4. **Wissen.** Valhalla kent geen veroudering. Elke ronde gaat alles wat de vorige
   ronde schreef en nu geen meting meer heeft terug op "onbekend", en bij de start
   wordt het hele bestand geleegd.

Live snelheden tellen in Valhalla alleen mee bij `date_time.type: 0` ("vertrek
nu"), en vooral voor het begin van de route.

## Ontwikkelen

```bash
pip install -e '.[dev]'
pytest && ruff check .
# tegen een echte Valhalla (Andorra-tileset), zie ci/:
python ../ci/e2e/verkeer_live.py /pad/naar/traffic.tar http://localhost:8002
```

Instellingen: zie de docstring van `main.py`. Metrics op `[::]:9100`
(`homemaps_traffic_*`); de chart levert er een alert op veroudering bij.
