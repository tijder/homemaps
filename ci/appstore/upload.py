"""Puts the screenshots on the App Store version that is ready in App Store Connect
to be submitted. Existing screenshots in those sizes are replaced, in
every language of that version.

    python3 ci/appstore/upload.py <dir> <version>           # upload
    python3 ci/appstore/upload.py <dir> <version> --dry-run # only see what would happen

<dir> contains <lang>/iphone/*.png and <lang>/ipad/*.png (see ci/e2e/screenshots.py);
they are ordered by file name. A language in App Store Connect without its own
dir (de-DE, ...) gets the English ones. If no editable version is ready, this
creates one with <version>: submitting a version stays manual work.

Environment: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and the key itself
in APP_STORE_CONNECT_KEY_P8 (contents) or APP_STORE_CONNECT_KEY_PATH (file).
Requires PyJWT with cryptography.
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
# Dir -> display type. Apple scales these two down to the smaller devices itself.
KINDS = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129"}
# Versions whose metadata can still be changed.
EDITABLE = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}


class Api:
    def __init__(self):
        key = os.environ.get("APP_STORE_CONNECT_KEY_P8") or Path(
            os.environ["APP_STORE_CONNECT_KEY_PATH"]
        ).read_text()
        self._key = key
        self._id = os.environ["APP_STORE_CONNECT_KEY_ID"]
        self._issuer = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
        self._token, self._valid_until = "", 0.0

    def _headers(self):
        now = time.time()
        if now > self._valid_until:
            # Apple allows 20 minutes at most.
            self._token = jwt.encode(
                {"iss": self._issuer, "iat": int(now), "exp": int(now) + 1200, "aud": "appstoreconnect-v1"},
                self._key,
                algorithm="ES256",
                headers={"kid": self._id, "typ": "JWT"},
            )
            self._valid_until = now + 1000
        return {"Authorization": f"Bearer {self._token}", "Content-Type": "application/json"}

    def request(self, method, path, body=None):
        url = path if path.startswith("http") else API + path
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers=self._headers())
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                text = response.read()
        except urllib.error.HTTPError as error:
            raise SystemExit(f"{method} {path}: {error.code} {error.read().decode(errors='replace')}") from None
        return json.loads(text) if text else {}

    def all(self, path):
        """All pages of a list."""
        out, next_ = [], path
        while next_:
            page = self.request("GET", next_)
            out += page["data"]
            next_ = page.get("links", {}).get("next")
        return out


def state(version):
    attr = version["attributes"]
    return attr.get("appVersionState") or attr.get("appStoreState")


def find_version(api, app, version_string, dry_run):
    versions = api.all(f"/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=50")
    for version in versions:
        if state(version) in EDITABLE:
            return version
    print(f"no editable version ({', '.join(f'{v['attributes']['versionString']}: {state(v)}' for v in versions) or 'none yet'}); creating {version_string}")
    if dry_run:
        return None
    return api.request(
        "POST",
        "/appStoreVersions",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version_string},
                "relationships": {"app": {"data": {"type": "apps", "id": app}}},
            }
        },
    )["data"]


def upload(api, set_id, file):
    contents = file.read_bytes()
    reservation = api.request(
        "POST",
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": file.name, "fileSize": len(contents)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        },
    )["data"]
    for part in reservation["attributes"]["uploadOperations"]:
        start = part["offset"]
        req = urllib.request.Request(
            part["url"],
            data=contents[start : start + part["length"]],
            method=part["method"],
            headers={header["name"]: header["value"] for header in part["requestHeaders"]},
        )
        urllib.request.urlopen(req, timeout=120).close()
    api.request(
        "PATCH",
        f"/appScreenshots/{reservation['id']}",
        {
            "data": {
                "type": "appScreenshots",
                "id": reservation["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(contents).hexdigest()},
            }
        },
    )
    return reservation["id"]


def wait_for_processing(api, ids):
    """Apple only checks the sizes after the upload; an error shows up here."""
    open_ = set(ids)
    for _ in range(60):
        for screenshot in list(open_):
            delivery = api.request("GET", f"/appScreenshots/{screenshot}")["data"]["attributes"]["assetDeliveryState"]
            if delivery["state"] == "COMPLETE":
                open_.discard(screenshot)
            elif delivery["state"] == "FAILED":
                raise SystemExit(f"screenshot {screenshot} rejected: {delivery.get('errors')}")
        if not open_:
            return
        time.sleep(5)
    raise SystemExit(f"still not processed after 5 minutes: {sorted(open_)}")


def main(dir_, version_string, dry_run=False):
    dir_ = Path(dir_)
    files = {
        lang.name: {kind: sorted((lang / kind).glob("*.png")) for kind in KINDS}
        for lang in dir_.iterdir()
        if lang.is_dir()
    }
    if "en" not in files:
        raise SystemExit(f"no English screenshots in {dir_ / 'en'}")
    for lang, kinds in files.items():
        for kind, paths in kinds.items():
            if not paths:
                raise SystemExit(f"no screenshots in {dir_ / lang / kind}")
            if len(paths) > 10:
                raise SystemExit(f"{lang}/{kind}: at most 10 screenshots, there are {len(paths)}")

    api = Api()
    apps = api.request("GET", f"/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        raise SystemExit(f"no app with bundle ID {BUNDLE_ID} in App Store Connect")
    app = apps[0]["id"]
    version = find_version(api, app, version_string, dry_run)
    if version is None:
        return
    print(f"version {version['attributes']['versionString']} ({state(version)})")

    localizations = api.all(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    new = []
    for localization in localizations:
        locale = localization["attributes"]["locale"]
        own = files.get(locale.split("-")[0].lower(), files["en"])
        sets = {
            s["attributes"]["screenshotDisplayType"]: s["id"]
            for s in api.all(f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets")
        }
        for kind, display_type in KINDS.items():
            print(f"  {locale} {display_type}: {len(own[kind])} screenshots")
            if dry_run:
                continue
            set_id = sets.get(display_type)
            if set_id is None:
                set_id = api.request(
                    "POST",
                    "/appScreenshotSets",
                    {
                        "data": {
                            "type": "appScreenshotSets",
                            "attributes": {"screenshotDisplayType": display_type},
                            "relationships": {
                                "appStoreVersionLocalization": {
                                    "data": {"type": "appStoreVersionLocalizations", "id": localization["id"]}
                                }
                            },
                        }
                    },
                )["data"]["id"]
            for old in api.all(f"/appScreenshotSets/{set_id}/appScreenshots"):
                api.request("DELETE", f"/appScreenshots/{old['id']}")
            for file in own[kind]:
                new.append(upload(api, set_id, file))
    if new:
        wait_for_processing(api, new)
    print("done" if not dry_run else "dry run: nothing changed")


if __name__ == "__main__":
    arguments = [a for a in sys.argv[1:] if a != "--dry-run"]
    main(*arguments, dry_run="--dry-run" in sys.argv)
