"""Fakes the NDW feeds, for Andorra: one travel-time segment with a jam on the
CG-2, one closure in Andorra la Vella, one accident (SRTI), one temporary
speed limit, one MSI sign gantry and one open bridge on the CG-2. Same structure as the real
DATEX II v3 feeds, so the importer runs unchanged.

Usage: generate.py <output dir>
"""

import gzip
import io
import struct
import sys
import zipfile
from datetime import UTC, datetime
from pathlib import Path

NS = (
    'xmlns:mc="http://datex2.eu/schema/3/messageContainer" '
    'xmlns:roa="http://datex2.eu/schema/3/roadTrafficData" '
    'xmlns:sit="http://datex2.eu/schema/3/situation" '
    'xmlns:com="http://datex2.eu/schema/3/common" '
    'xmlns:loc="http://datex2.eu/schema/3/locationReferencing" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
)

# CG-2 from Encamp towards Canillo; ~3 km. 1800 s travel time = 6 km/h.
JAM = "42.5361 1.5828 42.5670 1.5990"
# 136 m one-way street in Andorra la Vella (so the opposite direction doesn't match).
CLOSED = "42.507193 1.526786 42.507478 1.528365"
# The importer drops an incident that hasn't been updated for a long time; so the
# accident was just updated.
NOW = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")

FEEDS = {
    "reistijden_configuratie_meetlocaties": f"""<mc:messageContainer {NS}><mc:payload>
<roa:measurementSiteTable id="FAKE" version="1"><roa:measurementSite id="FAKE_CG2" version="1">
<roa:measurementSiteLocation><loc:gmlLineString><loc:posList>{JAM}</loc:posList></loc:gmlLineString></roa:measurementSiteLocation>
</roa:measurementSite></roa:measurementSiteTable></mc:payload></mc:messageContainer>""",
    "reistijden_meetgegevens": f"""<mc:messageContainer {NS}><mc:payload><roa:siteMeasurements>
<roa:measurementSiteReference id="FAKE_CG2" version="1"/>
<roa:physicalQuantity><roa:basicData>
<roa:travelTime numberOfInputValuesUsed="9"><roa:duration>1800</roa:duration></roa:travelTime>
<roa:normallyExpectedTravelTime numberOfInputValuesUsed="9"><roa:duration>240</roa:duration></roa:normallyExpectedTravelTime>
</roa:basicData></roa:physicalQuantity></roa:siteMeasurements></mc:payload></mc:messageContainer>""",
    "tijdelijke_verkeersmaatregelen_afsluitingen": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="S"><sit:situationRecord id="FAKE_CLOSED" version="1">
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference><loc:gmlLineString><loc:posList>{CLOSED}</loc:posList></loc:gmlLineString></sit:locationReference>
<sit:roadOrCarriagewayOrLaneManagementType>roadClosed</sit:roadOrCarriagewayOrLaneManagementType>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
    "veiligheidsgerelateerde_berichten_srti": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="O"><sit:situationRecord xsi:type="sit:Accident" id="FAKE_ACCIDENT" version="1">
<sit:situationRecordVersionTime>{NOW}</sit:situationRecordVersionTime>
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference xsi:type="loc:PointLocation"><loc:pointByCoordinates><loc:pointCoordinates><loc:latitude>42.55</loc:latitude><loc:longitude>1.59</loc:longitude></loc:pointCoordinates></loc:pointByCoordinates></sit:locationReference>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
    "tijdelijke_verkeersmaatregelen_maximum_snelheden": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="M"><sit:situationRecord xsi:type="sit:SpeedManagement" id="FAKE_SPEED_LIMIT" version="1">
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference><loc:gmlLineString><loc:posList>{JAM}</loc:posList></loc:gmlLineString></sit:locationReference>
<sit:complianceOption>mandatory</sit:complianceOption><sit:temporarySpeedLimit>30.0</sit:temporarySpeedLimit>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
    "Matrixsignaalinformatie": """<SOAP:Envelope xmlns:SOAP="http://schemas.xmlsoap.org/soap/envelope/"><SOAP:Body>
<variable_message_sign_events xmlns="http://variable_message_sign.trafficmanagementinfo.publicatie.hwn.rws.nl/1.1">
<event><sign_id><uuid>FAKE_MSI_1</uuid></sign_id><display><speedlimit flashing="false" red_ring="true">50</speedlimit></display></event>
<event><sign_id><uuid>FAKE_MSI_2</uuid></sign_id><display><lane_closed/></display></event>
</variable_message_sign_events></SOAP:Body></SOAP:Envelope>""",
    "actueel_beeld": f"""<mc:messageContainer {NS}><mc:payload>
<sit:situation id="B"><sit:situationRecord xsi:type="sit:GeneralNetworkManagement" id="FAKE_BRIDGE" version="1">
<sit:validity><com:validityTimeSpecification><com:overallStartTime>2020-01-01T00:00:00Z</com:overallStartTime></com:validityTimeSpecification></sit:validity>
<sit:locationReference xsi:type="loc:PointLocation"><loc:pointByCoordinates><loc:pointCoordinates><loc:latitude>42.54</loc:latitude><loc:longitude>1.585</loc:longitude></loc:pointCoordinates></loc:pointByCoordinates></sit:locationReference>
<sit:operatorActionStatus>implemented</sit:operatorActionStatus><sit:generalNetworkManagementType>bridgeSwingInOperation</sit:generalNetworkManagementType>
</sit:situationRecord></sit:situation></mc:payload></mc:messageContainer>""",
}


def msi_locations() -> bytes:
    """NDW's shapefile zip with the locations of the signs: one gantry with two
    lanes on the CG-2 towards Canillo."""
    signs = [("FAKE_MSI_1", 1), ("FAKE_MSI_2", 2)]
    shp = bytearray(100)
    for number, _ in enumerate(signs, 1):
        shp += struct.pack(">II", number, 10) + struct.pack("<idd", 1, 1.585, 42.545)
    fields = [("uuid", 20), ("road", 5), ("carriagew0", 2), ("lane", 3), ("km", 8), ("bearing", 8)]
    length = 1 + sum(width for _, width in fields)
    dbf = bytearray(struct.pack("<BBBBIHH", 3, 126, 9, 22, len(signs), 0, length) + bytes(20))
    for name, width in fields:
        dbf += name.encode().ljust(11, b"\0") + b"C" + bytes(4) + bytes([width]) + bytes(15)
    dbf += b"\r"
    struct.pack_into("<H", dbf, 8, len(dbf))
    for uuid, lane in signs:
        values = [uuid, "CG2", "R", str(lane), "5.0", "20"]
        dbf += b" " + b"".join(
            w.encode().ljust(b) for w, (_, b) in zip(values, fields, strict=True)
        )
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as archive:
        archive.writestr("MSI/shapes.shp", bytes(shp))
        archive.writestr("MSI/shapes.dbf", bytes(dbf))
    return out.getvalue()


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for name, xml in FEEDS.items():
    with gzip.open(out / f"{name}.xml.gz", "wt", encoding="utf-8") as file:
        file.write('<?xml version="1.0" encoding="UTF-8"?>\n' + xml)
    print(out / f"{name}.xml.gz")
(out / "ndw_msi_shapefiles_latest.zip").write_bytes(msi_locations())
print(out / "ndw_msi_shapefiles_latest.zip")
