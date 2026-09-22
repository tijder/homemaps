"""Maakt de NDW-feeds na, voor Andorra: één reistijdsegment met file op de
CG-2, één afsluiting in Andorra la Vella, één ongeval (SRTI), één tijdelijke
maximumsnelheid, één matrixbord-portaal en één open brug op de CG-2. Zelfde structuur als de echte
DATEX II v3-feeds, zodat de importer ongewijzigd draait.

Gebruik: maak.py <uitvoermap>
"""

import gzip
import io
import struct
import sys
import zipfile
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
    "Matrixsignaalinformatie": """<SOAP:Envelope xmlns:SOAP="http://schemas.xmlsoap.org/soap/envelope/"><SOAP:Body>
<variable_message_sign_events xmlns="http://variable_message_sign.trafficmanagementinfo.publicatie.hwn.rws.nl/1.1">
<event><sign_id><uuid>NEP_MSI_1</uuid></sign_id><display><speedlimit flashing="false" red_ring="true">50</speedlimit></display></event>
<event><sign_id><uuid>NEP_MSI_2</uuid></sign_id><display><lane_closed/></display></event>
</variable_message_sign_events></SOAP:Body></SOAP:Envelope>""",
    "actueel_beeld": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="B"><sit:situationRecord xsi:type="sit:GeneralNetworkManagement" id="NEP_BRUG" version="1">
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference xsi:type="loc:PointLocation"><loc:pointByCoordinates><loc:pointCoordinates><loc:latitude>42.54</loc:latitude><loc:longitude>1.585</loc:longitude></loc:pointCoordinates></loc:pointByCoordinates></sit:locationReference>
<sit:operatorActionStatus>implemented</sit:operatorActionStatus><sit:generalNetworkManagementType>bridgeSwingInOperation</sit:generalNetworkManagementType>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
}


def msi_plekken() -> bytes:
    """NDW's shapefile-zip met de plekken van de borden: één portaal met twee
    stroken op de CG-2 richting Canillo."""
    borden = [("NEP_MSI_1", 1), ("NEP_MSI_2", 2)]
    shp = bytearray(100)
    for nummer, _ in enumerate(borden, 1):
        shp += struct.pack(">II", nummer, 10) + struct.pack("<idd", 1, 1.585, 42.545)
    velden = [("uuid", 20), ("road", 5), ("carriagew0", 2), ("lane", 3), ("km", 8), ("bearing", 8)]
    lengte = 1 + sum(breedte for _, breedte in velden)
    dbf = bytearray(struct.pack("<BBBBIHH", 3, 126, 9, 22, len(borden), 0, lengte) + bytes(20))
    for naam, breedte in velden:
        dbf += naam.encode().ljust(11, b"\0") + b"C" + bytes(4) + bytes([breedte]) + bytes(15)
    dbf += b"\r"
    struct.pack_into("<H", dbf, 8, len(dbf))
    for uuid, strook in borden:
        waarden = [uuid, "CG2", "R", str(strook), "5.0", "20"]
        dbf += b" " + b"".join(
            w.encode().ljust(b) for w, (_, b) in zip(waarden, velden, strict=True)
        )
    uit = io.BytesIO()
    with zipfile.ZipFile(uit, "w") as archief:
        archief.writestr("MSI/shapes.shp", bytes(shp))
        archief.writestr("MSI/shapes.dbf", bytes(dbf))
    return uit.getvalue()


uit = Path(sys.argv[1])
uit.mkdir(parents=True, exist_ok=True)
for naam, xml in FEEDS.items():
    with gzip.open(uit / f"{naam}.xml.gz", "wt", encoding="utf-8") as bestand:
        bestand.write('<?xml version="1.0" encoding="UTF-8"?>\n' + xml)
    print(uit / f"{naam}.xml.gz")
(uit / "ndw_msi_shapefiles_latest.zip").write_bytes(msi_plekken())
print(uit / "ndw_msi_shapefiles_latest.zip")
