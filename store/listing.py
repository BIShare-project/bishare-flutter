#!/usr/bin/env python3
"""Pushes store/listing.json and the screenshots to the App Store (iOS and
macOS) and Google Play. Adapted from the games repo's store_listing.py.

  python3 store/listing.py --check
  python3 store/listing.py --asc --dry-run [--screenshots <dir>] [--whats-new]
  python3 store/listing.py --asc [--create-version] [--screenshots <dir>] [--whats-new]
  python3 store/listing.py --play --dry-run [--screenshots <dir>]
  python3 store/listing.py --play [--screenshots <dir>]
  python3 store/listing.py --play-notes production --dry-run
  python3 store/listing.py --asc-submit [--dry-run]
  python3 store/listing.py --play [--screenshots <dir>] --play-release production [--dry-run]

--check        limits (App Store name 30 / subtitle 30 / keywords 100 /
               promotional 170 / description 4000 / what's new 4000; Play
               title 30 / short 80 / full 4000 / what's new 500), keywords
               that repeat the name or subtitle, spaces around commas, and any
               "MIT" licence left in a description. Exits 1 on a problem.
--asc          for IOS and MAC_OS: the editable version (created with
               --create-version when there is none) gets description,
               keywords, promotional text and, with --whats-new, what's new;
               the editable app info gets name, subtitle and privacy URL.
               --screenshots <dir> replaces the sets from <dir>/<lang>/:
               ios_phone → APP_IPHONE_67 (and removes APP_IPHONE_65),
               ios_ipad → APP_IPAD_PRO_3GEN_129, mac → APP_DESKTOP.
--play         one edit: every listing's title, short and full description;
               with --screenshots, phone (play_phone) and 7"/10" tablet
               (play_tablet) screenshots; committed at the end.
--play-notes T sets what's new on the newest release of track T.
--play-release T  in the same edit as --play: the internal-track release of
               this pubspec build goes to track T, fully rolled out, with
               what's new; one commit, one review for listing and release.
--asc-submit   for IOS and MAC_OS: the processed build of this pubspec build
               number is attached to the editable version (export compliance
               "no non-exempt encryption", as every earlier build) and the
               version is submitted for review.
--dry-run      prints what would be sent, calls nothing (except reading the
               App Store version list, which changes nothing).

Credentials: ASC key P392W2N5LV (~/.appstoreconnect/private_keys), Play
service account PLAY_SA_JSON. Nothing here prints a secret. Every write is a
store change: run it only with the owner's go-ahead.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = pathlib.Path(__file__).parent
ASC = "https://api.appstoreconnect.apple.com"
PLAY = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
PLAY_UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
PACKAGE = "com.bishare.app"
APP = "6760924092"
PLATFORMS = ("IOS", "MAC_OS")
LIMITS = {
    "asc": {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000, "whatsNew": 4000},
    "play": {"title": 30, "short": 80, "full": 4000, "whatsNew": 500},
}
# screenshot folder per App Store display type, per platform
ASC_SETS = {
    "IOS": {"APP_IPHONE_67": "ios_phone", "APP_IPAD_PRO_3GEN_129": "ios_ipad"},
    "MAC_OS": {"APP_DESKTOP": "mac"},
}
# older sets that the new ones replace (the store would show them to older devices)
ASC_DROP = {"IOS": ["APP_IPHONE_65"], "MAC_OS": []}
PLAY_SETS = {"phoneScreenshots": "play_phone", "sevenInchScreenshots": "play_tablet", "tenInchScreenshots": "play_tablet"}
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")


def load() -> dict:
    return json.loads((HERE / "listing.json").read_text())


def build_number() -> str:
    """The +N of pubspec's version, the build the stores know."""
    m = re.search(r"^version:\s*([0-9.]+)\+([0-9]+)", (HERE.parent / "pubspec.yaml").read_text(), re.M)
    return m.group(2)


# ---------------------------------------------------------------- check
def words(s: str) -> set[str]:
    return {w for w in re.split(r"[\s:：,，·・、]+", s.lower()) if w}


def check(listing: dict) -> int:
    bad = 0
    for store in ("asc", "play"):
        for loc, l in listing[store].items():
            for field, limit in LIMITS[store].items():
                if len(l.get(field) or "") > limit:
                    print(f"{store} {loc} {field}: {len(l[field])} > {limit}")
                    bad += 1
            text = l.get("description") or l.get("full") or ""
            if re.search(r"\bMIT\b(?! ALLEM)", text):
                print(f"{store} {loc}: description still names the MIT licence")
                bad += 1
            if store == "asc":
                kw = l["keywords"]
                if ", " in kw or " ," in kw:
                    print(f"asc {loc} keywords: spaces around commas")
                    bad += 1
                dup = sorted(set(kw.lower().split(",")) & (words(l["name"]) | words(l["subtitle"])))
                if dup:
                    print(f"asc {loc} keywords repeat the name/subtitle: {dup}")
                    bad += 1
                print(f"asc  {loc:8} name {len(l['name']):2} subtitle {len(l['subtitle']):2} keywords {len(kw):3} description {len(l['description']):4} whatsNew {len(l['whatsNew']):3}")
            else:
                print(f"play {loc:8} title {len(l['title']):2} short {len(l['short']):2} full {len(l['full']):4} whatsNew {len(l['whatsNew']):3}")
    print("ok" if not bad else f"{bad} problem(s)")
    return 1 if bad else 0


# ---------------------------------------------------------------- http
def call(method: str, url: str, token: str, body: bytes | None = None, ctype: str = "application/json") -> tuple[int, dict]:
    for attempt in range(4):
        req = urllib.request.Request(url, method=method, data=body, headers={"Authorization": "Bearer " + token, "Content-Type": ctype})
        try:
            with urllib.request.urlopen(req, timeout=900) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read()
            if e.code >= 500 and attempt < 3:
                time.sleep(5 * (attempt + 1))
                continue
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {"raw": raw[:300].decode(errors="replace")}
        except (urllib.error.URLError, OSError) as e:  # a dropped connection
            if attempt == 3:
                raise
            print(f"    retry after {type(e).__name__}")
            time.sleep(5 * (attempt + 1))
    raise RuntimeError("unreachable")


def put_chunk(op: dict, chunk: bytes) -> None:
    for attempt in range(4):
        try:
            req = urllib.request.Request(op["url"], method=op["method"], data=chunk, headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            with urllib.request.urlopen(req, timeout=300) as r:
                r.read()
            return
        except (urllib.error.URLError, OSError):
            if attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))


def asc_token() -> str:
    import jwt

    key_id = os.environ.get("ASC_KEY_ID", "P392W2N5LV")
    issuer = os.environ.get("ASC_ISSUER_ID", "33bc6028-efc0-46f2-9b26-62e50a71135f")
    path = os.environ.get("ASC_KEY_PATH", os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"))
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, pathlib.Path(path).read_text(), algorithm="ES256", headers={"kid": key_id})


def asc(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    return call(method, ASC + path, asc_token(), json.dumps(body).encode() if body is not None else None)


def play_token() -> str:
    import jwt

    sa = json.loads(pathlib.Path(os.environ["PLAY_SA_JSON"]).read_text())
    now = int(time.time())
    assertion = jwt.encode({"iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher", "aud": sa["token_uri"], "iat": now, "exp": now + 3600}, sa["private_key"], algorithm="RS256")
    data = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion}).encode()
    with urllib.request.urlopen(urllib.request.Request(sa["token_uri"], data=data)) as r:
        return json.load(r)["access_token"]


def shots(root: pathlib.Path | None, lang: str, folder: str) -> list[pathlib.Path]:
    return sorted((root / lang / folder).glob("*.png")) if root else []


# ---------------------------------------------------------------- app store
def editable_version(platform: str, version: str, create: bool, dry: bool) -> str | None:
    st, vers = asc("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]={platform}&limit=10")
    for v in vers.get("data", []):
        if v["attributes"]["appStoreState"] in EDITABLE:
            if v["attributes"]["versionString"] != version:
                print(f"asc {platform}: editable version is {v['attributes']['versionString']}, listing says {version}")
                if not dry:
                    asc("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"versionString": version}}})
            return v["id"]
    if not create:
        print(f"asc {platform}: no editable version (use --create-version)")
        return None
    print(f"asc {platform}: create version {version}")
    if dry:
        return "(new)"
    st, d = asc("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {"platform": platform, "versionString": version}, "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    if st != 201:
        print("  failed", st, str(d.get("errors", d))[:200])
        return None
    return d["data"]["id"]


def upsert(kind: str, parent: str, parent_id: str, have: dict[str, str], locale: str, attrs: dict, dry: bool) -> None:
    if dry:
        print(f"  {kind[:-13]} {locale}: {', '.join(sorted(attrs))}")
        return
    if locale in have:
        st, d = asc("PATCH", f"/v1/{kind}/{have[locale]}", {"data": {"type": kind, "id": have[locale], "attributes": attrs}})
    else:
        st, d = asc("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": {"locale": locale, **attrs}, "relationships": {parent: {"data": {"type": parent + "s", "id": parent_id}}}}})
    print(f"  {kind[:-13]} {locale}: {st} {'' if st in (200, 201) else str(d.get('errors', d))[:200]}")


def replace_set(localization_id: str, display: str, files: list[pathlib.Path]) -> None:
    st, sets = asc("GET", f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=50")
    set_id = next((s["id"] for s in sets["data"] if s["attributes"]["screenshotDisplayType"] == display), None)
    if set_id is None:
        st, d = asc("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display}, "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}})
        set_id = d["data"]["id"]
    st, existing = asc("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50")
    done = [(x["attributes"]["fileName"], x["attributes"]["sourceFileChecksum"], (x["attributes"].get("assetDeliveryState") or {}).get("state")) for x in existing.get("data", [])]
    want = [(f.name, hashlib.md5(f.read_bytes()).hexdigest(), "COMPLETE") for f in files]
    if done == want:  # a rerun after a dropped connection: this set is already in
        print("    ", display, "already uploaded")
        return
    for shot in existing.get("data", []):
        asc("DELETE", f"/v1/appScreenshots/{shot['id']}")
    for f in files:
        data = f.read_bytes()
        st, d = asc("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)}, "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
        if st != 201:
            print("    reserve", f.name, st, str(d.get("errors", d))[:160])
            continue
        shot = d["data"]
        for op in shot["attributes"]["uploadOperations"]:
            put_chunk(op, data[op["offset"]: op["offset"] + op["length"]])
        st, d = asc("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"], "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print("    ", display, f.name, st)


def drop_set(localization_id: str, display: str) -> None:
    st, sets = asc("GET", f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=50")
    for s in sets.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == display:
            st, _ = asc("DELETE", f"/v1/appScreenshotSets/{s['id']}")
            print("    removed", display, st)


def push_asc(listing: dict, root: pathlib.Path | None, whats_new: bool, create: bool, dry: bool) -> int:
    urls = listing["urls"]
    for platform in PLATFORMS:
        vid = editable_version(platform, listing["version"], create, dry)
        if vid is None:
            return 1
        print(f"asc {platform} version {listing['version']}:")
        have: dict[str, str] = {}
        if vid != "(new)":
            st, locs = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50")
            have = {l["attributes"]["locale"]: l["id"] for l in locs.get("data", [])}
        for loc, l in listing["asc"].items():
            attrs = {"description": l["description"], "keywords": l["keywords"], "promotionalText": l["promotionalText"], "supportUrl": urls["support"], "marketingUrl": urls["marketing"]}
            if whats_new:
                attrs["whatsNew"] = l["whatsNew"]
            upsert("appStoreVersionLocalizations", "appStoreVersion", vid, have, loc, attrs, dry)
        if root:
            if not dry:
                st, locs = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50")
                have = {l["attributes"]["locale"]: l["id"] for l in locs.get("data", [])}
            for loc, l in listing["asc"].items():
                for display, folder in ASC_SETS[platform].items():
                    files = shots(root, l["shots"], folder)
                    print(f"  screenshots {loc} {display}: {len(files)} from {l['shots']}/{folder}")
                    if not dry and files and loc in have:
                        replace_set(have[loc], display, files)
                for display in ASC_DROP[platform]:
                    print(f"  screenshots {loc} {display}: remove")
                    if not dry and loc in have:
                        drop_set(have[loc], display)
    # name and subtitle live on the app info, editable only while a version is
    st, infos = asc("GET", f"/v1/apps/{APP}/appInfos")
    info = next((i for i in infos.get("data", []) if i["attributes"].get("state") not in ("READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO")), None)
    if info is None:
        print("asc app info: none editable yet (it appears once the new version exists)")
        return 0 if dry else 1
    st, locs = asc("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50")
    have = {l["attributes"]["locale"]: l["id"] for l in locs.get("data", [])}
    print("asc app info:")
    for loc, l in listing["asc"].items():
        upsert("appInfoLocalizations", "appInfo", info["id"], have, loc, {"name": l["name"], "subtitle": l["subtitle"], "privacyPolicyUrl": urls["privacy"]}, dry)
    return 0


def asc_submit(listing: dict, dry: bool) -> int:
    code = build_number()
    rc = 0
    for platform in PLATFORMS:
        st, vers = asc("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]={platform}&filter[versionString]={listing['version']}")
        ver = next((v for v in vers.get("data", []) if v["attributes"]["appStoreState"] in EDITABLE), None)
        if ver is None:
            print(f"asc {platform}: no editable version {listing['version']}")
            rc = 1
            continue
        st, builds = asc("GET", f"/v1/builds?filter[app]={APP}&filter[version]={code}&filter[preReleaseVersion.platform]={platform}&filter[preReleaseVersion.version]={listing['version']}")
        build = next((b for b in builds.get("data", []) if b["attributes"]["processingState"] == "VALID"), None)
        if build is None:
            states = [b["attributes"]["processingState"] for b in builds.get("data", [])]
            print(f"asc {platform}: build {code} not processed yet ({states or 'not uploaded'})")
            rc = 1
            continue
        print(f"asc {platform}: attach build {code} to {listing['version']} and submit")
        if dry:
            continue
        if build["attributes"].get("usesNonExemptEncryption") is None:
            st, d = asc("PATCH", f"/v1/builds/{build['id']}", {"data": {"type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
            print("  export compliance:", st)
        st, d = asc("PATCH", f"/v1/appStoreVersions/{ver['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
        print("  attach:", st, "" if st == 204 else str(d.get("errors", d))[:200])
        st, sub = asc("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": platform}, "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        if st != 201:
            print("  review submission:", st, str(sub.get("errors", sub))[:300])
            rc = 1
            continue
        sid = sub["data"]["id"]
        st, d = asc("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}}, "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
        print("  item:", st, "" if st == 201 else str(d.get("errors", d))[:300])
        if st != 201:
            rc = 1
            continue
        st, d = asc("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
        print("  submitted:", st, "" if st == 200 else str(d.get("errors", d))[:300])
        rc |= st != 200
    return rc


# ---------------------------------------------------------------- play
def push_play(listing: dict, root: pathlib.Path | None, dry: bool, release_track: str | None = None) -> int:
    if dry:
        for lang, l in listing["play"].items():
            print(f"play {lang}: title/short/full")
            for image_type, folder in PLAY_SETS.items():
                if root:
                    print(f"  {image_type}: {len(shots(root, l['shots'], folder)[:8])} from {l['shots']}/{folder}")
        if release_track:
            print(f"play {release_track}: release build {build_number()} from internal, completed, what's new in {len(listing['play'])} languages")
        return 0
    token = play_token()
    base = f"{PLAY}/{PACKAGE}"
    st, d = call("POST", f"{base}/edits", token, b"{}")
    edit = d["id"]
    failed = 0
    for lang, l in listing["play"].items():
        body = {"language": lang, "title": l["title"], "shortDescription": l["short"], "fullDescription": l["full"]}
        st, d = call("PUT", f"{base}/edits/{edit}/listings/{lang}", token, json.dumps(body).encode())
        print(f"play {lang}: {st} {d.get('error', {}).get('message', '')[:120]}")
        failed += st != 200
        if root:
            for image_type, folder in PLAY_SETS.items():
                files = shots(root, l["shots"], folder)[:8]
                if not files:
                    continue
                call("DELETE", f"{base}/edits/{edit}/listings/{lang}/{image_type}", token)
                for f in files:
                    st, d = call("POST", f"{PLAY_UPLOAD}/{PACKAGE}/edits/{edit}/listings/{lang}/{image_type}?uploadType=media", token, f.read_bytes(), ctype="image/png")
                    print(f"  {image_type} {f.name}: {st} {d.get('error', {}).get('message', '')[:120]}")
                    failed += st != 200
    if release_track and not failed:
        code = build_number()
        st, internal = call("GET", f"{base}/edits/{edit}/tracks/internal", token)
        rel = next((r for r in internal.get("releases", []) if code in r.get("versionCodes", [])), None)
        if rel is None:
            print(f"play: build {code} is not on the internal track yet")
            failed += 1
        else:
            notes = [{"language": lang, "text": l["whatsNew"]} for lang, l in listing["play"].items()]
            body = {"track": release_track, "releases": [{"name": f"{listing['version']} ({code})", "versionCodes": [code], "status": "completed", "releaseNotes": notes}]}
            st, d = call("PUT", f"{base}/edits/{edit}/tracks/{release_track}", token, json.dumps(body).encode())
            print(f"play {release_track} release {code}: {st} {d.get('error', {}).get('message', '')[:200]}")
            failed += st != 200
    if failed:
        call("DELETE", f"{base}/edits/{edit}", token)
        print("edit discarded")
        return 1
    st, d = call("POST", f"{base}/edits/{edit}:commit", token)
    print("commit", st, d.get("error", {}).get("message", "")[:200] or "ok")
    return 0 if st == 200 else 1


def play_notes(listing: dict, track: str, dry: bool) -> int:
    notes = [{"language": lang, "text": l["whatsNew"]} for lang, l in listing["play"].items()]
    if dry:
        print(f"play {track}: what's new for " + ", ".join(n["language"] for n in notes))
        return 0
    token = play_token()
    base = f"{PLAY}/{PACKAGE}"
    st, d = call("POST", f"{base}/edits", token, b"{}")
    edit = d["id"]
    st, t = call("GET", f"{base}/edits/{edit}/tracks/{track}", token)
    releases = t.get("releases", [])
    if not releases:
        print(f"play {track}: no release")
        call("DELETE", f"{base}/edits/{edit}", token)
        return 1
    releases[0]["releaseNotes"] = notes
    st, d = call("PUT", f"{base}/edits/{edit}/tracks/{track}", token, json.dumps({"track": track, "releases": releases}).encode())
    print(f"play {track} notes: {st} {d.get('error', {}).get('message', '')[:160]}")
    if st != 200:
        call("DELETE", f"{base}/edits/{edit}", token)
        return 1
    st, d = call("POST", f"{base}/edits/{edit}:commit", token)
    print("commit", st, d.get("error", {}).get("message", "")[:200] or "ok")
    return 0 if st == 200 else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--asc", action="store_true")
    ap.add_argument("--play", action="store_true")
    ap.add_argument("--play-notes", metavar="TRACK")
    ap.add_argument("--play-release", metavar="TRACK")
    ap.add_argument("--asc-submit", action="store_true")
    ap.add_argument("--screenshots", metavar="DIR", help="store-screenshots folder (<lang>/<target>/*.png)")
    ap.add_argument("--whats-new", action="store_true")
    ap.add_argument("--create-version", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    listing = load()
    rc = check(listing)
    if rc or (args.check and not (args.asc or args.play or args.play_notes or args.asc_submit)):
        return rc
    root = pathlib.Path(args.screenshots) if args.screenshots else None
    if args.asc:
        rc |= push_asc(listing, root, args.whats_new, args.create_version, args.dry_run)
    if args.play:
        rc |= push_play(listing, root, args.dry_run, args.play_release)
    if args.asc_submit:
        rc |= asc_submit(listing, args.dry_run)
    if args.play_notes:
        rc |= play_notes(listing, args.play_notes, args.dry_run)
    return rc


if __name__ == "__main__":
    sys.exit(main())
