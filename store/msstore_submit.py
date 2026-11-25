#!/usr/bin/env python3
"""Sends a Windows build to the Microsoft Store and submits it, with the
release notes of store/listing.json, through the Store submission API.

    python3 store/msstore_submit.py <store.msix> [--dry-run] [--no-commit]

Needs MSSTORE_TENANT_ID, MSSTORE_CLIENT_ID, MSSTORE_CLIENT_SECRET (an Entra
app added to Partner Center with the Manager role) and MSSTORE_PRODUCT_ID.

What it does: a new submission (a copy of the last published one), the old
packages out and <store.msix> in, the release notes of every listing from
listing.json `msstore.whatsNew` (Windows has its own text: the phone notes name
things a PC does not have), then the commit; it waits for the Store to accept the package. With --dry-run it
only reads: it prints what it would send. --no-commit leaves the submission
as a draft in Partner Center.

A submission the Store is still working on (certification, publishing) cannot
be replaced: the script stops and says so. A draft left in Partner Center is
replaced. It also stops, before anything is written, when `msstore.version` is
not this release or a Store language has no notes.
"""

import io
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
API = "https://manage.devcenter.microsoft.com/v1.0/my/applications"
# Statuses of a submission the Store is still working on: it cannot be replaced.
BUSY = {"CommitStarted", "PreProcessing", "Certification", "Release", "Publishing"}
NOTES_MAX = 1500


def env(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        sys.exit(f"{name} is not set")
    return v


def token() -> str:
    body = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": env("MSSTORE_CLIENT_ID"),
        "client_secret": env("MSSTORE_CLIENT_SECRET"),
        "resource": "https://manage.devcenter.microsoft.com",
    }).encode()
    url = f"https://login.microsoftonline.com/{env('MSSTORE_TENANT_ID')}/oauth2/token"
    return json.load(urllib.request.urlopen(url, body))["access_token"]


def call(tok: str, method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{API}/{path}", data=data, method=method,
                                 headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: HTTP {e.code} {e.read().decode(errors='replace')[:600]}")


def read_listing() -> dict:
    return json.loads((HERE / "listing.json").read_text())


def notes_problem(listing: dict) -> str | None:
    """Why the Windows release notes cannot go out, or None."""
    ms = listing.get("msstore") or {}
    if ms.get("version") != listing["version"]:
        return f"listing.json msstore notes are for {ms.get('version')}, the release is {listing['version']}: write the Windows notes first"
    for lang, text in ms["whatsNew"].items():
        if not text.strip() or len(text) > NOTES_MAX:
            return f"listing.json msstore {lang}: {len(text)} characters (1 to {NOTES_MAX})"
    return None


def notes_for(listing_lang: str, notes: dict) -> str | None:
    """The Windows notes of a Store listing language ("zh" is Traditional Chinese)."""
    lang = listing_lang.lower()
    special = {"zh-hant": "zh", "zh-tw": "zh", "zh-hk": "zh", "zh-cn": "zh-hans"}
    return notes.get(lang) or notes.get(special.get(lang) or lang.split("-")[0])


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry, commit = "--dry-run" in sys.argv, "--no-commit" not in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    msix = pathlib.Path(args[0])
    if not msix.is_file():
        sys.exit(f"no package at {msix}")

    listing = read_listing()
    pub = re.search(r"^version:\s*([0-9.]+)\+", (HERE.parent / "pubspec.yaml").read_text(), re.M).group(1)
    if listing["version"] != pub:
        sys.exit(f"store/listing.json is for {listing['version']}, pubspec says {pub}: write this release's notes first")
    if problem := notes_problem(listing):
        sys.exit(problem)
    notes = listing["msstore"]["whatsNew"]

    tok = token()
    app_id = env("MSSTORE_PRODUCT_ID")
    app = call(tok, "GET", app_id)
    published = call(tok, "GET", f"{app_id}/submissions/{app['lastPublishedApplicationSubmission']['id']}")
    missing = [lang for lang in published.get("listings", {}) if not notes_for(lang, notes)]
    if missing:
        sys.exit(f"no Windows release notes for {', '.join(missing)}: add them to listing.json msstore.whatsNew")
    pending = app.get("pendingApplicationSubmission")
    if pending:
        status = call(tok, "GET", f"{app_id}/submissions/{pending['id']}/status").get("status")
        if status in BUSY:
            sys.exit(f"the Store is still working on submission {pending['id']} ({status}); try again when it is done")
        print(f"draft submission {pending['id']} ({status}) is replaced")
        if not dry:
            call(tok, "DELETE", f"{app_id}/submissions/{pending['id']}")

    sub = published if dry else call(tok, "POST", f"{app_id}/submissions")

    for p in sub.get("applicationPackages", []):
        p["fileStatus"] = "PendingDelete"
    sub.setdefault("applicationPackages", []).append({"fileName": msix.name, "fileStatus": "PendingUpload"})

    for lang, l in sub.get("listings", {}).items():
        l["baseListing"]["releaseNotes"] = notes_for(lang, notes)
    print(f"release notes for {len(sub.get('listings', {}))} listings")
    print(f"package: {msix.name} ({msix.stat().st_size // 1024} KB), replacing {len(sub['applicationPackages']) - 1}")

    if dry:
        en = sub["listings"].get("en-us") or next(iter(sub["listings"].values()))
        print("en notes:\n" + en["baseListing"]["releaseNotes"])
        print("dry run: nothing sent")
        return 0

    call(tok, "PUT", f"{app_id}/submissions/{sub['id']}", sub)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(msix, msix.name)
    put = urllib.request.Request(sub["fileUploadUrl"].replace("+", "%2B"), data=buf.getvalue(), method="PUT",
                                 headers={"x-ms-blob-type": "BlockBlob"})
    urllib.request.urlopen(put).read()
    print(f"uploaded to submission {sub['id']}")
    if not commit:
        print("left as a draft in Partner Center")
        return 0

    call(tok, "POST", f"{app_id}/submissions/{sub['id']}/commit")
    for _ in range(60):
        s = call(tok, "GET", f"{app_id}/submissions/{sub['id']}/status")
        status = s.get("status")
        if status != "CommitStarted":
            break
        time.sleep(30)
    print(f"status: {status}")
    if status == "CommitFailed":
        print(json.dumps(s.get("statusDetails"), indent=2)[:3000])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
