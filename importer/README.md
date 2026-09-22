# homemaps-traffic

Sidecar bij Valhalla: haalt elke paar minuten NDW's open data op, schrijft die in
Valhalla's `traffic.tar` en maakt er de verkeerslaag van de app van.

| bron (DATEX II v3, `opendata.ndw.nu`) | wordt |
|---|---|
| `reistijden_meetgegevens` + `reistijden_configuratie_meetlocaties` | live snelheid per edge |
| `tijdelijke_verkeersmaatregelen_afsluitingen` (`carriagewayClosures`, `roadClosed`, nu geldig, niet alleen voor vracht) | afgesloten edges |
| dezelfde feeds, plus `laneClosures` | `/verkeer.geojson`: de laag op de kaart |
| `veiligheidsgerelateerde_berichten_srti` (ongeval, pechgeval, voorwerp op de weg) | punten in dezelfde laag; de app waarschuwt ervoor onderweg |
| `planningsfeed_wegwerkzaamheden_en_evenementen` (18 MB, eens per uur) | `/verkeer-gepland.geojson`: afsluitingen van de komende 8 dagen met hun vensters, voor "later vertrekken" |
| `tijdelijke_verkeersmaatregelen_maximum_snelheden` (vooral RWS) en de `SpeedManagement`-records uit de planningsfeed (ook provincies en gemeenten) | `soort: snelheid` in `/verkeer.geojson`: tijdelijke maximumsnelheden die nu gelden, over de routevorm; de app toont onderweg de laagste van deze en OSM. Niet op de kaart, niet in `traffic.tar` |
| `Matrixsignaalinformatie` (elke minuut, eigen draad) + `ndw_msi_shapefiles_latest.zip` (plekken, eens per dag) | `soort: msi` in `/verkeer.geojson`: per portaal wat de matrixborden tonen, per strook van links naar rechts (`"80r"` verplicht, `"80"` advies, `"x"`, `"<"`, `">"`, `"open"`, `"einde"`, `""`). Lege portalen alleen binnen 3 km van een bezet portaal: daar houdt een snelheid op |
| `actueel_beeld` (bruggen die nu open zijn) | `soort: brug` in `/verkeer.geojson`: een waarschuwing onderweg |

En uit het OSM-bestand van de tileset (`/data/bron/gebied.osm.pbf`, dat de bouwjob
neerzet): `maxspeed:conditional` met een tijd ("130 @ (19:00-06:00)") per OSM-way,
als `/snelheid-tijden.json`. Valhalla leest die tag niet; de app past de regel
onderweg toe op de way die Valhalla bij elk stuk route noemt. De lezer
(`osmregels.py`) pakt alleen de blokken uit waarin de tag voorkomt: voor Nederland
~20 s en ~20 MB, opnieuw zodra het bestand verandert.

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
4. **De kaartlaag** (`kaartlaag.py`). Afsluitingen ("dicht") en rijstrookafsluitingen
   ("werk") over NDW's eigen lijn; trage stukken ("traag" onder 60% van de normale
   snelheid, "file" onder 35%, altijd minstens 20 s vertraging) over de routevorm
   van de match, want NDW's lijn is meestal alleen begin en eind. Elke ronde
   opnieuw, op `:9100/verkeer.geojson` (gzip als de client het wil); de nginx van
   de web-pod geeft hem door als `/verkeer`.
5. **Wissen.** Valhalla kent geen veroudering. Elke ronde gaat alles wat de vorige
   ronde schreef en nu geen meting meer heeft terug op "onbekend", en bij de start
   wordt het hele bestand geleegd.

Live snelheden en afsluitingen tellen in Valhalla alleen mee met een vertrektijd
van nu: `date_time.type: 0` ("vertrek nu"), of `type: 3` met de tijd van nu -- dat
laatste gebruikt de app, want alleen dan komen er ook alternatieven. Zonder
`date_time` rijdt Valhalla dwars door een afsluiting heen.

## Ontwikkelen

```bash
pip install -e '.[dev]'
pytest && ruff check .
# tegen een echte Valhalla (Andorra-tileset), zie ci/:
python ../ci/e2e/verkeer_live.py /pad/naar/traffic.tar http://localhost:8002
```

Instellingen: zie de docstring van `main.py`. Metrics op `[::]:9100`
(`homemaps_traffic_*`); de chart levert er een alert op veroudering bij.
