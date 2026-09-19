#!/usr/bin/env python3
"""Daily download figures from the App Store and Google Play, for bishare.app/stats.

Reads the last DAYS days from each store and posts them to the BIShare API,
which keeps one row per day and sums them (see server/modules/stats in the API).
Posting is idempotent, so every run simply re-sends its whole window; that also
picks up the corrections both stores make to recent days.

Each store is optional: one whose settings are missing is skipped with a note,
so the App Store half can run before the Play half is configured. A store that
IS configured and fails makes the run fail — but only after the other store's
numbers have been posted.

Nothing secret is printed. Set DRY_RUN=1 to see the numbers without posting.

App Store   ASC_KEY_ID, ASC_ISSUER_ID, ASC_API_KEY_P8, ASC_VENDOR_NUMBER
            ASC_APP_IDS   comma-separated Apple IDs to count (default: BIShare)
Google Play PLAY_REPORTS_SERVICE_ACCOUNT_JSON (falls back to PLAY_SERVICE_ACCOUNT_JSON),
            PLAY_REPORTS_BUCKET (pubsite_prod_…)
            PLAY_PACKAGE  (default com.bishare.app)
API         STATS_INGEST_TOKEN, STATS_INGEST_URL (default production)
"""

from __future__ import annotations

import csv
import datetime as dt
import gzip
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT, with `cryptography` for ES256 / RS256

UA = "bishare-store-stats/1 (+https://bishare.app/stats)"
TODAY = dt.datetime.now(dt.timezone.utc).date()

# App Store "Product Type Identifier" values that are a FIRST download of an
# app. Re-downloads (3, 3F, 3T, F3) and updates (7, 7F, 7T, F7) are left out:
# "total downloads" on a public page should mean people, not reinstalls.
APPLE_FIRST_DOWNLOAD = {"1", "1F", "1T", "1E", "1EP", "1EU", "F1"}


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def http(url: str, *, headers: dict[str, str], data: bytes | None = None) -> tuple[int, bytes]:
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, **headers})
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            return res.status, res.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def window(days: int) -> list[dt.date]:
    """Yesterday back to `days` days ago, oldest first. Today is never complete."""
    return [TODAY - dt.timedelta(days=n) for n in range(days, 0, -1)]


# ── App Store ────────────────────────────────────────────────────────────────


def apple(days: int, verbose: bool) -> dict[str, int] | None:
    key_id, issuer, p8, vendor = (
        env("ASC_KEY_ID"), env("ASC_ISSUER_ID"), env("ASC_API_KEY_P8"), env("ASC_VENDOR_NUMBER"),
    )
    if not (key_id and issuer and p8 and vendor):
        missing = [n for n, v in [("ASC_KEY_ID", key_id), ("ASC_ISSUER_ID", issuer),
                                  ("ASC_API_KEY_P8", p8), ("ASC_VENDOR_NUMBER", vendor)] if not v]
        print(f"App Store: skipped, not configured ({', '.join(missing)})")
        return None
    app_ids = {s.strip() for s in env("ASC_APP_IDS", "6760924092").split(",") if s.strip()}

    now = int(time.time())
    token = jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        p8, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )

    out: dict[str, int] = {}
    seen: dict[tuple[str, str, str], int] = {}
    for day in window(days):
        query = urllib.parse.urlencode({
            "filter[frequency]": "DAILY",
            "filter[reportType]": "SALES",
            "filter[reportSubType]": "SUMMARY",
            "filter[vendorNumber]": vendor,
            "filter[reportDate]": day.isoformat(),
        })
        status, body = http(
            f"https://api.appstoreconnect.apple.com/v1/salesReports?{query}",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/a-gzip"},
        )
        if status == 404:
            continue  # no sales that day, or the report is not out yet: no row
        if status != 200:
            raise SystemExit(f"App Store: HTTP {status} for {day}: {body[:300].decode('utf8', 'replace')}")
        rows = csv.DictReader(io.StringIO(gzip.decompress(body).decode("utf8")), delimiter="\t")
        units = 0
        for r in rows:
            apple_id = (r.get("Apple Identifier") or "").strip()
            kind = (r.get("Product Type Identifier") or "").strip()
            n = int(float(r.get("Units") or 0))
            k = (apple_id, (r.get("Title") or "").strip(), kind)
            seen[k] = seen.get(k, 0) + n
            if apple_id in app_ids and kind in APPLE_FIRST_DOWNLOAD:
                units += n
        if units > 0:
            out[day.isoformat()] = units

    if verbose:
        print("App Store: every (Apple ID, title, product type) in the window —")
        for (apple_id, title, kind), n in sorted(seen.items()):
            mark = "counted" if apple_id in app_ids and kind in APPLE_FIRST_DOWNLOAD else "-"
            print(f"    {apple_id:>12}  {kind:<4} {n:>6}  {mark:<8} {title}")
    print(f"App Store: {sum(out.values())} first downloads over {len(out)} day(s) with sales")
    return out


# ── Google Play ──────────────────────────────────────────────────────────────


def play(days: int, verbose: bool) -> tuple[dict[str, int], int | None] | None:
    # Reading reports and publishing releases are different jobs, and need not
    # be the same account: a reports-only key wins when there is one, so the
    # release key is never touched for this.
    sa_json = env("PLAY_REPORTS_SERVICE_ACCOUNT_JSON") or env("PLAY_SERVICE_ACCOUNT_JSON")
    bucket = env("PLAY_REPORTS_BUCKET")
    if not (sa_json and bucket):
        missing = [n for n, v in [("PLAY_REPORTS_SERVICE_ACCOUNT_JSON", sa_json), ("PLAY_REPORTS_BUCKET", bucket)] if not v]
        print(f"Google Play: skipped, not configured ({', '.join(missing)})")
        return None
    package = env("PLAY_PACKAGE", "com.bishare.app")
    # Accept the URI exactly as Play Console copies it (gs://bucket/stats/…/).
    bucket = bucket.removeprefix("gs://").strip("/").split("/")[0]
    sa = json.loads(sa_json)

    now = int(time.time())
    assertion = jwt.encode(
        {"iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/devstorage.read_only",
         "aud": sa["token_uri"], "iat": now, "exp": now + 900},
        sa["private_key"], algorithm="RS256",
    )
    status, body = http(sa["token_uri"], headers={"Content-Type": "application/x-www-form-urlencoded"},
                        data=urllib.parse.urlencode({
                            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                            "assertion": assertion}).encode())
    if status != 200:
        raise SystemExit(f"Google Play: token exchange failed, HTTP {status}")
    access = json.loads(body)["access_token"]

    wanted = {d.isoformat() for d in window(days)}
    months = {d.strftime("%Y%m") for d in window(days)}

    # Ask the bucket what it holds instead of guessing file names. It also makes
    # a refusal readable: Cloud Storage answers 403 both for "no access" and for
    # "no such object" when the caller may not list, so a 403 on a guessed name
    # says nothing. A 403 on the listing can only mean the first.
    prefix = f"stats/installs/installs_{package}_"
    names: list[str] = []
    page = ""
    while True:
        query = urllib.parse.urlencode({"prefix": prefix, "fields": "items(name),nextPageToken",
                                        **({"pageToken": page} if page else {})})
        status, body = http(f"https://storage.googleapis.com/storage/v1/b/{bucket}/o?{query}",
                            headers={"Authorization": f"Bearer {access}"})
        if status == 403:
            raise SystemExit(f"Google Play: no access to the reports bucket yet (HTTP 403 listing {prefix}*). "
                             f"{sa['client_email']} needs the ACCOUNT permission \"View app information and "
                             "download bulk reports\" in Play Console; Google can take up to a day to apply it.")
        if status != 200:
            raise SystemExit(f"Google Play: HTTP {status} listing {prefix}*: {body[:300].decode('utf8', 'replace')}")
        listing = json.loads(body)
        names += [i["name"] for i in listing.get("items", [])]
        page = listing.get("nextPageToken", "")
        if not page:
            break
    overviews = sorted(n for n in names if n.endswith("_overview.csv"))
    if verbose:
        print(f"Google Play: {len(names)} install report file(s) in the bucket, {len(overviews)} overview(s)"
              + (f": {overviews[0].rsplit('/', 1)[-1]} … {overviews[-1].rsplit('/', 1)[-1]}" if overviews else ""))

    out: dict[str, int] = {}
    active: tuple[str, int] | None = None
    for obj in overviews:
        if obj[len(prefix):len(prefix) + 6] not in months:
            continue
        status, body = http(
            f"https://storage.googleapis.com/storage/v1/b/{bucket}/o/{urllib.parse.quote(obj, safe='')}?alt=media",
            headers={"Authorization": f"Bearer {access}"},
        )
        if status != 200:
            raise SystemExit(f"Google Play: HTTP {status} reading {obj}: {body[:300].decode('utf8', 'replace')}")
        text = body.decode("utf-16") if body[:2] in (b"\xff\xfe", b"\xfe\xff") else body.decode("utf8")
        reader = csv.DictReader(io.StringIO(text))
        fields = reader.fieldnames or []
        if verbose and not out and active is None:
            print(f"Google Play: columns: {fields}")
        for col in ("Date", "Daily User Installs"):
            if col not in fields:
                raise SystemExit(f"Google Play: column {col!r} missing in {obj}; has {fields}")
        month_sum, last_total = 0, ""
        for r in reader:
            date = (r.get("Date") or "").strip()
            n = int(float(r.get("Daily User Installs") or 0))
            month_sum += n
            last_total = (r.get("Total User Installs") or "").strip() or last_total
            if date in wanted and n > 0:
                out[date] = n
            level = (r.get("Active Device Installs") or "").strip()
            if date and level and (active is None or date > active[0]):
                active = (date, int(float(level)))
        if verbose:
            # Google's own running total, to check the daily rows against.
            print(f"    {obj.rsplit('_', 2)[-2]}: daily user installs sum {month_sum}, "
                  f"'Total User Installs' at month end {last_total or 'n/a'}")

    print(f"Google Play: {sum(out.values())} user installs over {len(out)} day(s) with installs"
          + (f"; {active[1]} active devices as of {active[0]}" if active else ""))
    return out, (active[1] if active else None)


# ── Post ─────────────────────────────────────────────────────────────────────


def main() -> int:
    days = max(1, min(int(env("DAYS", "10") or 10), 400))
    dry = env("DRY_RUN").lower() in ("1", "true", "yes")
    print(f"window: {window(days)[0]} … {window(days)[-1]} ({days} days){'  [dry run]' if dry else ''}")

    # One store failing must not cost the other its numbers: whatever was read
    # is still posted, and the run is marked failed afterwards so it gets seen.
    daily: dict[str, dict[str, int]] = {}
    gauges: dict[str, int] = {}
    failed: list[str] = []
    try:
        a = apple(days, verbose=dry)
        if a:
            daily["store_units_ios"] = a
    except SystemExit as e:
        failed.append(str(e))
    try:
        p = play(days, verbose=dry)
        if p:
            if p[0]:
                daily["store_units_android"] = p[0]
            if p[1] is not None:
                gauges["store_active_devices_android"] = p[1]
    except SystemExit as e:
        failed.append(str(e))
    for message in failed:
        print(f"FAILED — {message}")

    if not daily and not gauges:
        print("nothing to post")
        return 1 if failed else 0
    if dry:
        print(json.dumps({"daily": daily, "gauges": gauges}, indent=1, sort_keys=True))
        return 1 if failed else 0

    token = env("STATS_INGEST_TOKEN")
    if not token:
        raise SystemExit("STATS_INGEST_TOKEN is not set")
    url = env("STATS_INGEST_URL", "https://api.bishare.app/api/v1/stats/ingest")
    status, body = http(url, data=json.dumps({"daily": daily, "gauges": gauges}).encode(),
                        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    print(f"ingest: HTTP {status} {body[:400].decode('utf8', 'replace')}")
    return 0 if status == 200 and not failed else 1


if __name__ == "__main__":
    sys.exit(main())
