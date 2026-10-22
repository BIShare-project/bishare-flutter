#!/usr/bin/env python3
"""Drive subscriptions in App Store Connect and Google Play (drive-plan.md
"Payments and entitlement", phase 7.8).

Eight auto-renewing subscriptions, the ids in bishare-api's
server/modules/vault/plans.ts. Prices are the US price; every other country
gets the store's own conversion (Apple's equalizations, Play's
convertRegionPrices), no local overrides.

  python3 store/products.py                 what exists in both stores (reads only)
  python3 store/products.py --plan          what --apply would create (reads only)
  python3 store/products.py --apply asc     create what is missing in App Store Connect
  python3 store/products.py --apply play    create and activate what is missing in Play

Apple: one group "BIShare Drive"; the same size monthly and yearly share a
level, a bigger size is a higher level, so changing size is an upgrade or a
downgrade and changing period is a crossgrade. Family Sharing off, no trial.
The review screenshot of the purchase screen is added once the app has one.

Play: one subscription per id, each with a single auto-renewing base plan
("monthly" or "yearly"), legacy-compatible.

Credentials as in listing.py: the ASC key, and PLAY_SA_JSON for Play. Nothing
here prints a secret. --apply is a store change: run it only with the owner's
go-ahead.
"""

from __future__ import annotations

import argparse
import sys
import time

sys.argv, _argv = ["listing.py"], sys.argv
import listing as L  # noqa: E402

sys.argv = _argv

GROUP = "BIShare Drive"

# id, size label key, period, US price, Apple group level (1 = most storage)
PRODUCTS = [
    ("drive_100gb_monthly", "100", "month", "2.49", 4),
    ("drive_100gb_yearly", "100", "year", "24.99", 4),
    ("drive_250gb_monthly", "250", "month", "5.99", 3),
    ("drive_250gb_yearly", "250", "year", "59.99", 3),
    ("drive_500gb_monthly", "500", "month", "9.99", 2),
    ("drive_500gb_yearly", "500", "year", "99.99", 2),
    ("drive_1tb_monthly", "1000", "month", "19.99", 1),
    ("drive_1tb_yearly", "1000", "year", "199.99", 1),
]

# Per language: the size written the local way, the store description
# (Apple: 45 characters at most; Play: 80), the period words for Play titles,
# and two Play benefits (40 characters each at most).
TEXT = {
    "en": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} of end-to-end encrypted storage",
        "month": "monthly",
        "year": "yearly",
        "benefits": ["Only your devices hold the key", "Photo backup and the Drive on the web"],
    },
    "id": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "Penyimpanan terenkripsi end-to-end {size}",
        "month": "bulanan",
        "year": "tahunan",
        "benefits": ["Kunci hanya di perangkat Anda", "Cadangan foto dan Drive di web"],
    },
    "es": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} cifrados de extremo a extremo",
        "month": "mensual",
        "year": "anual",
        "benefits": ["Solo tus dispositivos tienen la clave", "Copia de fotos y el Drive en la web"],
    },
    "fr": {
        "size": {"100": "100 Go", "250": "250 Go", "500": "500 Go", "1000": "1 To"},
        "desc": "{size} de stockage chiffré de bout en bout",
        "month": "mensuel",
        "year": "annuel",
        "benefits": ["Seuls vos appareils ont la clé", "Sauvegarde photo et Drive sur le web"],
    },
    "de": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} Ende-zu-Ende-verschlüsselter Speicher",
        "month": "monatlich",
        "year": "jährlich",
        "benefits": ["Nur deine Geräte haben den Schlüssel", "Foto-Backup und das Drive im Web"],
    },
    "pt-BR": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} criptografados de ponta a ponta",
        "month": "mensal",
        "year": "anual",
        "benefits": ["Só seus dispositivos têm a chave", "Backup de fotos e o Drive na web"],
    },
    "ru": {
        "size": {"100": "100 ГБ", "250": "250 ГБ", "500": "500 ГБ", "1000": "1 ТБ"},
        "desc": "{size} хранилища со сквозным шифрованием",
        "month": "помесячно",
        "year": "на год",
        "benefits": ["Ключ есть только у ваших устройств", "Резервные копии фото и Drive в вебе"],
    },
    "ar": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} من التخزين المشفّر من طرف إلى طرف",
        "month": "شهري",
        "year": "سنوي",
        "benefits": ["المفتاح على أجهزتك وحدها", "نسخ الصور احتياطيًا وDrive على الويب"],
    },
    "hi": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} एंड-टू-एंड एन्क्रिप्टेड स्टोरेज",
        "month": "मासिक",
        "year": "वार्षिक",
        "benefits": ["चाबी सिर्फ़ आपके डिवाइस पर", "फ़ोटो बैकअप और वेब पर Drive"],
    },
    "ja": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "エンドツーエンド暗号化ストレージ {size}",
        "month": "月額",
        "year": "年額",
        "benefits": ["鍵はあなたのデバイスだけに", "写真のバックアップと Web 版 Drive"],
    },
    "ko": {
        "size": {"100": "100GB", "250": "250GB", "500": "500GB", "1000": "1TB"},
        "desc": "종단간 암호화 저장 공간 {size}",
        "month": "월간",
        "year": "연간",
        "benefits": ["키는 내 기기에만 있습니다", "사진 백업과 웹에서 쓰는 Drive"],
    },
    "zh-Hans": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} 端到端加密存储空间",
        "month": "按月",
        "year": "按年",
        "benefits": ["密钥只在你的设备上", "照片备份，网页也能用 Drive"],
    },
    "zh-Hant": {
        "size": {"100": "100 GB", "250": "250 GB", "500": "500 GB", "1000": "1 TB"},
        "desc": "{size} 端對端加密儲存空間",
        "month": "按月",
        "year": "按年",
        "benefits": ["金鑰只在你的裝置上", "照片備份，網頁也能用 Drive"],
    },
}

ASC_LANG = {
    "en-US": "en", "en-GB": "en", "id": "id", "es-ES": "es", "es-MX": "es", "fr-FR": "fr", "de-DE": "de",
    "pt-BR": "pt-BR", "ru": "ru", "ar-SA": "ar", "hi": "hi", "ja": "ja", "ko": "ko", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
}
PLAY_LANG = {
    "en-US": "en", "en-IN": "en", "id": "id", "es-ES": "es", "es-419": "es", "fr-FR": "fr", "de-DE": "de",
    "pt-BR": "pt-BR", "ru-RU": "ru", "ar": "ar", "hi-IN": "hi", "ja-JP": "ja", "ko-KR": "ko", "zh-CN": "zh-Hans", "zh-TW": "zh-Hant",
}


def name(lang: str, size: str) -> str:
    return f"BIShare Drive {TEXT[lang]['size'][size]}"


def desc(lang: str, size: str) -> str:
    return TEXT[lang]["desc"].format(size=TEXT[lang]["size"][size])


def check_text() -> int:
    bad = 0
    for lang, t in TEXT.items():
        for size in ("100", "250", "500", "1000"):
            for what, s, limit in (("name", name(lang, size), 30), ("desc", desc(lang, size), 45)):
                if len(s) > limit:
                    print(f"  {lang} {what} {len(s)} > {limit}: {s}")
                    bad += 1
            title = f"{name(lang, size)} ({t['month']})"
            if len(title) > 55:
                print(f"  {lang} play title too long: {title}")
                bad += 1
        for b in t["benefits"]:
            if len(b) > 40:
                print(f"  {lang} benefit {len(b)} > 40: {b}")
                bad += 1
    return bad


# ---------------------------------------------------------------- App Store


def asc_ok(st: int, d: dict, what: str) -> dict:
    if st >= 300:
        errs = "; ".join(e.get("detail", e.get("title", "")) for e in d.get("errors", []))
        raise SystemExit(f"ASC {what}: HTTP {st} {errs}")
    return d


def asc_state() -> tuple[dict | None, dict[str, dict]]:
    """The Drive group (if made) and every subscription of the app by product id."""
    st, d = L.asc("GET", f"/v1/apps/{L.APP}/subscriptionGroups?include=subscriptions&limit=50")
    asc_ok(st, d, "groups")
    group = next((g for g in d.get("data", []) if g["attributes"].get("referenceName") == GROUP), None)
    subs = {s["attributes"]["productId"]: s for s in d.get("included", []) if s["type"] == "subscriptions"}
    return group, subs


def asc_points(sub_id: str, territory: str) -> dict[str, str]:
    """customerPrice -> price point id, every page."""
    out: dict[str, str] = {}
    path = f"/v1/subscriptions/{sub_id}/pricePoints?filter[territory]={territory}&limit=200"
    while path:
        st, d = L.asc("GET", path)
        asc_ok(st, d, "price points")
        out.update({p["attributes"]["customerPrice"]: p["id"] for p in d.get("data", [])})
        nxt = d.get("links", {}).get("next")
        path = nxt.replace("https://api.appstoreconnect.apple.com", "") if nxt else ""
    return out


def asc_equalized(point_id: str) -> list[tuple[str, str]]:
    """(territory, price point id) for every other territory, at Apple's conversion."""
    out: list[tuple[str, str]] = []
    path = f"/v1/subscriptionPricePoints/{point_id}/equalizations?limit=200&include=territory"
    while path:
        st, d = L.asc("GET", path)
        asc_ok(st, d, "equalizations")
        out += [(p["relationships"]["territory"]["data"]["id"], p["id"]) for p in d.get("data", [])]
        nxt = d.get("links", {}).get("next")
        path = nxt.replace("https://api.appstoreconnect.apple.com", "") if nxt else ""
    return out


def apply_asc(dry: bool) -> int:
    group, subs = asc_state()
    if group is None:
        print(f"create group {GROUP!r} + {len(ASC_LANG)} localizations")
        if not dry:
            st, d = L.asc("POST", "/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups", "attributes": {"referenceName": GROUP}, "relationships": {"app": {"data": {"type": "apps", "id": L.APP}}}}})
            group = asc_ok(st, d, "create group")["data"]
            for locale in ASC_LANG:
                st, d = L.asc("POST", "/v1/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations", "attributes": {"locale": locale, "name": "BIShare Drive"}, "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": group["id"]}}}}})
                asc_ok(st, d, f"group localization {locale}")
    for pid, size, period, usd, level in PRODUCTS:
        if pid in subs:
            print(f"  {pid}: exists ({subs[pid]['attributes'].get('state')})")
            continue
        print(f"  {pid}: create, {period}, US ${usd}, level {level}, {len(ASC_LANG)} localizations, all territories")
        if dry:
            continue
        attrs = {
            "name": f"Drive {TEXT['en']['size'][size]} {TEXT['en'][period]}",
            "productId": pid,
            "familySharable": False,
            "subscriptionPeriod": "ONE_MONTH" if period == "month" else "ONE_YEAR",
            "groupLevel": level,
            "reviewNote": "End-to-end encrypted storage for BIShare Drive. Bought in the app's Drive tab after signing in; the server checks the signed transaction and raises the vault's quota.",
        }
        st, d = L.asc("POST", "/v1/subscriptions", {"data": {"type": "subscriptions", "attributes": attrs, "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group["id"]}}}}})
        sub = asc_ok(st, d, f"create {pid}")["data"]
        for locale, lang in ASC_LANG.items():
            st, d = L.asc("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations", "attributes": {"locale": locale, "name": name(lang, size), "description": desc(lang, size)}, "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub["id"]}}}}})
            asc_ok(st, d, f"{pid} localization {locale}")
        us = asc_points(sub["id"], "USA").get(usd)
        if not us:
            raise SystemExit(f"{pid}: no US price point at ${usd}")
        prices = [("USA", us)] + asc_equalized(us)
        for territory, point in prices:
            st, d = L.asc("POST", "/v1/subscriptionPrices", {"data": {"type": "subscriptionPrices", "attributes": {"preserveCurrentPrice": False}, "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub["id"]}}, "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point}}, "territory": {"data": {"type": "territories", "id": territory}}}}})
            asc_ok(st, d, f"{pid} price {territory}")
        st, d = L.asc("POST", "/v1/subscriptionAvailabilities", {"data": {"type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True}, "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub["id"]}}, "availableTerritories": {"data": [{"type": "territories", "id": t} for t, _ in prices]}}}})
        asc_ok(st, d, f"{pid} availability")
        print(f"    done: {len(prices)} territories")
        time.sleep(1)
    return 0


# ---------------------------------------------------------------- Play


def play_state(token: str) -> dict[str, dict]:
    st, d = L.call("GET", f"{L.PLAY}/{L.PACKAGE}/subscriptions?pageSize=100", token)
    if st >= 300:
        raise SystemExit(f"Play subscriptions: HTTP {st} {d.get('error', {}).get('message', '')}")
    return {s["productId"]: s for s in d.get("subscriptions", [])}


def money(usd: str) -> dict:
    units, cents = usd.split(".")
    return {"currencyCode": "USD", "units": units, "nanos": int(cents.ljust(9, "0"))}


def apply_play(dry: bool) -> int:
    token = L.play_token()
    have = play_state(token)
    for pid, size, period, usd, _ in PRODUCTS:
        if pid in have:
            print(f"  {pid}: exists ({', '.join(b.get('state', '?') for b in have[pid].get('basePlans', []))})")
            continue
        plan_id = "monthly" if period == "month" else "yearly"
        print(f"  {pid}: create, base plan {plan_id}, US ${usd}, {len(PLAY_LANG)} listings, every region")
        if dry:
            continue
        st, conv = L.call("POST", f"{L.PLAY}/{L.PACKAGE}/pricing:convertRegionPrices", token, json_body({"price": money(usd)}))
        if st >= 300:
            raise SystemExit(f"{pid} convert prices: HTTP {st} {conv.get('error', {}).get('message', '')}")
        regional = [{"regionCode": code, "price": p["price"], "newSubscriberAvailability": True} for code, p in conv.get("convertedRegionPrices", {}).items()]
        other = conv.get("convertedOtherRegionsPrice", {})
        listings = [
            {"languageCode": code, "title": f"{name(lang, size)} ({TEXT[lang][period]})", "benefits": TEXT[lang]["benefits"], "description": desc(lang, size)}
            for code, lang in PLAY_LANG.items()
        ]
        body = {
            "packageName": L.PACKAGE,
            "productId": pid,
            "listings": listings,
            "basePlans": [
                {
                    "basePlanId": plan_id,
                    "autoRenewingBasePlanType": {
                        "billingPeriodDuration": "P1M" if period == "month" else "P1Y",
                        "resubscribeState": "RESUBSCRIBE_STATE_ACTIVE",
                        "prorationMode": "SUBSCRIPTION_PRORATION_MODE_CHARGE_ON_NEXT_BILLING_DATE",
                        "legacyCompatible": True,
                    },
                    "regionalConfigs": regional,
                    "otherRegionsConfig": {"usdPrice": other.get("usdPrice"), "eurPrice": other.get("eurPrice"), "newSubscriberAvailability": True},
                }
            ],
        }
        st, d = L.call("POST", f"{L.PLAY}/{L.PACKAGE}/subscriptions?productId={pid}&regionsVersion.version=2022/02", token, json_body(body))
        if st >= 300:
            raise SystemExit(f"{pid} create: HTTP {st} {d.get('error', {}).get('message', '')}")
        st, d = L.call("POST", f"{L.PLAY}/{L.PACKAGE}/subscriptions/{pid}/basePlans/{plan_id}:activate", token, json_body({}))
        if st >= 300:
            raise SystemExit(f"{pid} activate: HTTP {st} {d.get('error', {}).get('message', '')}")
        print(f"    done: {len(regional)} regions, active")
    return 0


def json_body(obj: dict) -> bytes:
    import json

    return json.dumps(obj, ensure_ascii=False).encode()


def status() -> int:
    group, subs = asc_state()
    print(f"App Store: group {GROUP!r} {'exists' if group else 'missing'}")
    for pid, *_ in PRODUCTS:
        print(f"  {pid}: {subs[pid]['attributes'].get('state') if pid in subs else 'missing'}")
    old = sorted(p for p in subs if p not in dict((x[0], 1) for x in PRODUCTS))
    if old:
        print(f"  other products in the app: {', '.join(old)}")
    try:
        have = play_state(L.play_token())
    except KeyError:
        print("Play: PLAY_SA_JSON not set")
        return 0
    print("Play:")
    for pid, *_ in PRODUCTS:
        print(f"  {pid}: {', '.join(b.get('state', '?') for b in have[pid].get('basePlans', [])) if pid in have else 'missing'}")
    old = sorted(p for p in have if p not in dict((x[0], 1) for x in PRODUCTS))
    if old:
        print(f"  other products in the app: {', '.join(old)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="show what --apply would create")
    ap.add_argument("--apply", choices=["asc", "play"], help="create what is missing in one store")
    a = ap.parse_args()
    if check_text():
        print("store text over the limits; fix TEXT first")
        return 1
    if a.apply:
        return apply_asc(dry=False) if a.apply == "asc" else apply_play(dry=False)
    if a.plan:
        print("App Store:")
        apply_asc(dry=True)
        print("Play:")
        apply_play(dry=True)
        return 0
    return status()


if __name__ == "__main__":
    sys.exit(main())
