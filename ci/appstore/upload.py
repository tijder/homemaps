"""Zet de schermafdrukken bij de App Store-versie die in App Store Connect klaarstaat
om ingediend te worden. Bestaande schermafdrukken in die maten worden vervangen, in
elke taal van die versie.

    python3 ci/appstore/upload.py <map> <versie>        # uploaden
    python3 ci/appstore/upload.py <map> <versie> --droog # alleen kijken wat er zou gebeuren

<map> bevat <taal>/iphone/*.png en <taal>/ipad/*.png (zie ci/e2e/schermafdrukken.py);
ze komen op volgorde van de bestandsnaam. Een taal in App Store Connect zonder eigen
map (de-DE, ...) krijgt de Engelse. Staat er geen bewerkbare versie klaar, dan maakt
dit er een met <versie>: een versie indienen blijft handwerk.

Omgeving: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID en de sleutel zelf
in APP_STORE_CONNECT_KEY_P8 (inhoud) of APP_STORE_CONNECT_KEY_PATH (bestand).
Vereist PyJWT met cryptography.
"""

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "nl.g4d.homemaps"
# Map -> weergavetype. Apple schaalt deze twee zelf naar de kleinere toestellen.
SOORTEN = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129"}
# Versies waarvan de metadata nog te wijzigen is.
BEWERKBAAR = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}


class Api:
    def __init__(self):
        sleutel = os.environ.get("APP_STORE_CONNECT_KEY_P8") or Path(
            os.environ["APP_STORE_CONNECT_KEY_PATH"]
        ).read_text()
        self._sleutel = sleutel
        self._id = os.environ["APP_STORE_CONNECT_KEY_ID"]
        self._uitgever = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
        self._token, self._geldig = "", 0.0

    def _kop(self):
        nu = time.time()
        if nu > self._geldig:
            # Apple staat hooguit 20 minuten toe.
            self._token = jwt.encode(
                {"iss": self._uitgever, "iat": int(nu), "exp": int(nu) + 1200, "aud": "appstoreconnect-v1"},
                self._sleutel,
                algorithm="ES256",
                headers={"kid": self._id, "typ": "JWT"},
            )
            self._geldig = nu + 1000
        return {"Authorization": f"Bearer {self._token}", "Content-Type": "application/json"}

    def vraag(self, methode, pad, lichaam=None):
        url = pad if pad.startswith("http") else API + pad
        data = json.dumps(lichaam).encode() if lichaam is not None else None
        verzoek = urllib.request.Request(url, data=data, method=methode, headers=self._kop())
        try:
            with urllib.request.urlopen(verzoek, timeout=60) as antwoord:
                tekst = antwoord.read()
        except urllib.error.HTTPError as fout:
            raise SystemExit(f"{methode} {pad}: {fout.code} {fout.read().decode(errors='replace')}") from None
        return json.loads(tekst) if tekst else {}

    def alles(self, pad):
        """Alle pagina's van een lijst."""
        uit, volgende = [], pad
        while volgende:
            pagina = self.vraag("GET", volgende)
            uit += pagina["data"]
            volgende = pagina.get("links", {}).get("next")
        return uit


def staat(versie):
    attr = versie["attributes"]
    return attr.get("appVersionState") or attr.get("appStoreState")


def zoek_versie(api, app, versienummer, droog):
    versies = api.alles(f"/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=50")
    for versie in versies:
        if staat(versie) in BEWERKBAAR:
            return versie
    print(f"geen bewerkbare versie ({', '.join(f'{v['attributes']['versionString']}: {staat(v)}' for v in versies) or 'nog geen'}); maak {versienummer}")
    if droog:
        return None
    return api.vraag(
        "POST",
        "/appStoreVersions",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": versienummer},
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        },
    )["data"]


def upload(api, set_id, bestand):
    inhoud = bestand.read_bytes()
    reservering = api.vraag(
        "POST",
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": bestand.name, "fileSize": len(inhoud)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        },
    )["data"]
    for stuk in reservering["attributes"]["uploadOperations"]:
        begin = stuk["offset"]
        verzoek = urllib.request.Request(
            stuk["url"],
            data=inhoud[begin : begin + stuk["length"]],
            method=stuk["method"],
            headers={kop["name"]: kop["value"] for kop in stuk["requestHeaders"]},
        )
        urllib.request.urlopen(verzoek, timeout=120).close()
    api.vraag(
        "PATCH",
        f"/appScreenshots/{reservering['id']}",
        {
            "data": {
                "type": "appScreenshots",
                "id": reservering["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(inhoud).hexdigest()},
            }
        },
    )
    return reservering["id"]


def wacht_op_verwerking(api, ids):
    """Apple controleert de maten pas na de upload; een fout komt hier."""
    open_ = set(ids)
    for _ in range(60):
        for schermafdruk in list(open_):
            stand = api.vraag("GET", f"/appScreenshots/{schermafdruk}")["data"]["attributes"]["assetDeliveryState"]
            if stand["state"] == "COMPLETE":
                open_.discard(schermafdruk)
            elif stand["state"] == "FAILED":
                raise SystemExit(f"schermafdruk {schermafdruk} geweigerd: {stand.get('errors')}")
        if not open_:
            return
        time.sleep(5)
    raise SystemExit(f"nog niet verwerkt na 5 minuten: {sorted(open_)}")


def main(map_, versienummer, droog=False):
    map_ = Path(map_)
    bestanden = {
        taal.name: {soort: sorted((taal / soort).glob("*.png")) for soort in SOORTEN}
        for taal in map_.iterdir()
        if taal.is_dir()
    }
    if "en" not in bestanden:
        raise SystemExit(f"geen Engelse schermafdrukken in {map_ / 'en'}")
    for taal, soorten in bestanden.items():
        for soort, lijst in soorten.items():
            if not lijst:
                raise SystemExit(f"geen schermafdrukken in {map_ / taal / soort}")
            if len(lijst) > 10:
                raise SystemExit(f"{taal}/{soort}: hooguit 10 schermafdrukken, er zijn er {len(lijst)}")

    api = Api()
    apps = api.vraag("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        raise SystemExit(f"geen app met bundle ID {BUNDLE_ID} in App Store Connect")
    app = apps[0]["id"]
    versie = zoek_versie(api, app, versienummer, droog)
    if versie is None:
        return
    print(f"versie {versie['attributes']['versionString']} ({staat(versie)})")

    talen = api.alles(f"/appStoreVersions/{versie['id']}/appStoreVersionLocalizations")
    nieuw = []
    for taal in talen:
        locale = taal["attributes"]["locale"]
        eigen = bestanden.get(locale.split("-")[0].lower(), bestanden["en"])
        sets = {
            s["attributes"]["screenshotDisplayType"]: s["id"]
            for s in api.alles(f"/appStoreVersionLocalizations/{taal['id']}/appScreenshotSets")
        }
        for soort, weergave in SOORTEN.items():
            print(f"  {locale} {weergave}: {len(eigen[soort])} schermafdrukken")
            if droog:
                continue
            set_id = sets.get(weergave)
            if set_id is None:
                set_id = api.vraag(
                    "POST",
                    "/appScreenshotSets",
                    {
                        "data": {
                            "type": "appScreenshotSets",
                            "attributes": {"screenshotDisplayType": weergave},
                            "relationships": {
                                "appStoreVersionLocalization": {
                                    "data": {"type": "appStoreVersionLocalizations", "id": taal["id"]}
                                }
                            },
                        }
                    },
                )["data"]["id"]
            for oud in api.alles(f"/appScreenshotSets/{set_id}/appScreenshots"):
                api.vraag("DELETE", f"/appScreenshots/{oud['id']}")
            for bestand in eigen[soort]:
                nieuw.append(upload(api, set_id, bestand))
    if nieuw:
        wacht_op_verwerking(api, nieuw)
    print("klaar" if not droog else "droog: niets gewijzigd")


if __name__ == "__main__":
    argumenten = [a for a in sys.argv[1:] if a != "--droog"]
    main(*argumenten, droog="--droog" in sys.argv)
