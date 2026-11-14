#!/usr/bin/env python3
"""Fetches (or creates) the Developer ID provisioning profile for the macOS
direct-download build and installs it where Xcode looks.

The app's keychain and app groups (Drive, Google sign-in) need a profile
with a Developer ID build. Xcode cannot mint one in CI (the API key has no
access to cloud-managed certificates), so this script does it through the
App Store Connect API: reuse the active profile named PROFILE_NAME when it
covers every Developer ID certificate and has 30+ days left, otherwise delete
it and create a new one.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. Prints the profile name; with
GITHUB_ENV set, also exports DEVID_PROFILE_NAME. Needs PyJWT + cryptography.
"""
import base64, datetime, json, os, pathlib, plistlib, subprocess, sys, time, urllib.parse, urllib.request
import jwt

BUNDLE = "com.bishare.app"
PROFILE_NAME = "BIShare Developer ID"
API = "https://api.appstoreconnect.apple.com"

kid, iss = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
key = pathlib.Path(os.environ["ASC_KEY_PATH"]).read_text()
now = int(time.time())
TOKEN = jwt.encode({"iss": iss, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": kid})


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"::error::App Store Connect {method} {path}: {e.code} {e.read().decode()[:400]}")


bundle = next(b for b in call("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&limit=20")["data"]
              if b["attributes"]["identifier"] == BUNDLE)
certs = sorted(c["id"] for c in call("GET", "/v1/certificates?filter[certificateType]=DEVELOPER_ID_APPLICATION&limit=50")["data"])
if not certs:
    sys.exit("::error::no Developer ID Application certificate on the account")

q = urllib.parse.urlencode({"filter[name]": PROFILE_NAME, "filter[profileType]": "MAC_APP_DIRECT",
                            "include": "certificates", "limit": 20})
profile = None
for p in call("GET", f"/v1/profiles?{q}")["data"]:
    a = p["attributes"]
    exp = datetime.datetime.fromisoformat(a["expirationDate"].replace("Z", "+00:00"))
    have = sorted(c["id"] for c in call("GET", f"/v1/profiles/{p['id']}/certificates")["data"])
    fresh = exp - datetime.datetime.now(datetime.timezone.utc) > datetime.timedelta(days=30)
    if a["profileState"] == "ACTIVE" and fresh and have == certs:
        profile = p
    else:
        print(f"replacing profile {p['id']} (state {a['profileState']}, expires {a['expirationDate']})")
        call("DELETE", f"/v1/profiles/{p['id']}")

if profile is None:
    profile = call("POST", "/v1/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": PROFILE_NAME, "profileType": "MAC_APP_DIRECT"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": c} for c in certs]},
        }}})["data"]
    print(f"created profile {profile['id']}")

content = base64.b64decode(profile["attributes"]["profileContent"])
info = plistlib.loads(subprocess.run(["security", "cms", "-D"], input=content, capture_output=True, check=True).stdout)
# Apple leaves Sign in with Apple out of Developer ID profiles even when the
# App ID has it, so release.yml strips that entitlement from the DMG build.
uuid = info["UUID"]
for d in ("~/Library/MobileDevice/Provisioning Profiles", "~/Library/Developer/Xcode/UserData/Provisioning Profiles"):
    folder = pathlib.Path(os.path.expanduser(d))
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{uuid}.provisionprofile").write_bytes(content)
print(f"installed '{PROFILE_NAME}' {uuid}, expires {info['ExpirationDate']}")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a") as f:
        f.write(f"DEVID_PROFILE_NAME={PROFILE_NAME}\n")
