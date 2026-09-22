"""Maakt de NDW-feeds na, voor Andorra: één reistijdsegment met file op de
CG-2, één afsluiting in Andorra la Vella, één ongeval (SRTI) en één tijdelijke
maximumsnelheid op de CG-2. Zelfde structuur als de echte
DATEX II v3-feeds, zodat de importer ongewijzigd draait.

Gebruik: maak.py <uitvoermap>
"""

import gzip
import sys
from pathlib import Path

NS = (
    'xmlns:mc="http://datex2.eu/schema/3/messageContainer" '
    'xmlns:roa="http://datex2.eu/schema/3/roadTrafficData" '
    'xmlns:sit="http://datex2.eu/schema/3/situation" '
    'xmlns:com="http://datex2.eu/schema/3/common" '
    'xmlns:loc="http://datex2.eu/schema/3/locationReferencing" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
)

# CG-2 van Encamp richting Canillo; ~3 km. 1800 s reistijd = 6 km/u.
FILE = "42.5361 1.5828 42.5670 1.5990"
# 136 m eenrichtingsstraat in Andorra la Vella (de tegenrichting matcht dus niet).
DICHT = "42.507193 1.526786 42.507478 1.528365"

FEEDS = {
    "reistijden_configuratie_meetlocaties": f"""<mc:messageContainer {NS}><mc:payload>
<roa:measurementSiteTable id="NEP" version="1"><roa:measurementSite id="NEP_CG2" version="1">
<roa:measurementSiteLocation><loc:gmlLineString><loc:posList>{FILE}</loc:posList></loc:gmlLineString></roa:measurementSiteLocation>
</roa:measurementSite></roa:measurementSiteTable></mc:payload></mc:messageContainer>""",
    "reistijden_meetgegevens": f"""<mc:messageContainer {NS}><mc:payload><roa:siteMeasurements>
<roa:measurementSiteReference id="NEP_CG2" version="1"/>
<roa:physicalQuantity><roa:basicData>
<roa:travelTime numberOfInputValuesUsed="9"><roa:duration>1800</roa:duration></roa:travelTime>
<roa:normallyExpectedTravelTime numberOfInputValuesUsed="9"><roa:duration>240</roa:duration></roa:normallyExpectedTravelTime>
</roa:basicData></roa:physicalQuantity></roa:siteMeasurements></mc:payload></mc:messageContainer>""",
    "tijdelijke_verkeersmaatregelen_afsluitingen": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="S"><sit:situationRecord id="NEP_DICHT" version="1">
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference><loc:gmlLineString><loc:posList>{DICHT}</loc:posList></loc:gmlLineString></sit:locationReference>
<sit:roadOrCarriagewayOrLaneManagementType>roadClosed</sit:roadOrCarriagewayOrLaneManagementType>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
    "veiligheidsgerelateerde_berichten_srti": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="O"><sit:situationRecord xsi:type="sit:Accident" id="NEP_ONGEVAL" version="1">
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference xsi:type="loc:PointLocation"><loc:pointByCoordinates><loc:pointCoordinates><loc:latitude>42.55</loc:latitude><loc:longitude>1.59</loc:longitude></loc:pointCoordinates></loc:pointByCoordinates></sit:locationReference>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
    "tijdelijke_verkeersmaatregelen_maximum_snelheden": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="M"><sit:situationRecord xsi:type="sit:SpeedManagement" id="NEP_SNELHEID" version="1">
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference><loc:gmlLineString><loc:posList>{FILE}</loc:posList></loc:gmlLineString></sit:locationReference>
<sit:complianceOption>mandatory</sit:complianceOption><sit:temporarySpeedLimit>30.0</sit:temporarySpeedLimit>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
}

uit = Path(sys.argv[1])
uit.mkdir(parents=True, exist_ok=True)
for naam, xml in FEEDS.items():
    with gzip.open(uit / f"{naam}.xml.gz", "wt", encoding="utf-8") as bestand:
        bestand.write('<?xml version="1.0" encoding="UTF-8"?>\n' + xml)
    print(uit / f"{naam}.xml.gz")
