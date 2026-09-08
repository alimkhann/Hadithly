#!/usr/bin/env python3
"""F3 Playwright gate for the canonical web fallback.

Serves the static site locally (with /hadith/* mapped to the fallback page),
mocks the public Convex resolver endpoint per scenario, and asserts the full
gate matrix: licensed text, unlicensed suppression, malformed, stale, and
unsupported-locale links.

Run:  python3 scripts/test-canonical-fallback.py
"""

import json
import threading
from functools import partial
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, unquote

from playwright.sync_api import sync_playwright

SITE = Path(__file__).resolve().parent.parent / "site"
PORT = 8765
BASE = f"http://localhost:{PORT}"

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json",
}


def site_file(path: str):
    parsed = urlparse(path)
    route = unquote(parsed.path)
    if route.startswith("/hadith/") or route == "/hadith":
        route = "/hadith/index.html"
    if route.endswith("/"):
        route += "index.html"
    candidate = (SITE / route.lstrip("/")).resolve()
    if not str(candidate).startswith(str(SITE)) or not candidate.is_file():
        return None
    return candidate


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        file = site_file(self.path)
        if file is None:
            self.send_response(404)
            self.end_headers()
            return
        body = file.read_bytes()
        self.send_response(200)
        self.send_header(
            "Content-Type",
            CONTENT_TYPES.get(file.suffix, "application/octet-stream"),
        )
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def serve():
    server = HTTPServer(("localhost", PORT), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def resolver_mock(payload):
    def handle(route):
        route.fulfill(
            status=200,
            content_type="application/json",
            body=json.dumps({"status": "success", "value": payload}),
        )

    return handle


LICENSED_HADITH = {
    "status": "resolved",
    "canonicalId": "sunnah_now:bukhari:57",
    "collectionSlug": "bukhari",
    "collectionName": "Sahih al-Bukhari",
    "providerHadithId": "57",
    "referenceDisplay": "Bukhari · Hadith 57",
    "narrator": "Umar ibn al-Khattab",
    "sourceName": "Licensed Source",
    "sourceUrl": "https://licensed.example",
    "authenticity": {
        "kind": "collection_scope",
        "normalizedGrade": "sahih",
        "claimScope": "collection",
        "sourceLabel": "Documented Sahih collection",
        "sourceName": "Sunnah.com",
        "sourceUrl": "https://sunnah.com/bukhari/about",
        "verificationMethod": "manual_collection_mapping",
    },
    "license": {
        "kind": "verified",
        "licenseName": "Test Display License",
        "licenseUrl": "https://licensed.example/license",
        "permitsDisplay": True,
        "permitsRedistribution": True,
        "permitsOfflineDistribution": False,
        "verifiedAt": 1759900000000,
    },
    "contentVersion": 77,
    "text": {
        "visible": True,
        "arabicText": "نَحْوُ نَصٍّ عَرَبِيٍّ",
        "providerEnglish": "A provider English rendering.",
        "translation": None,
        "translationFallback": False,
        "translationRequested": False,
    },
}


def licensed_with_translation(**over):
    result = json.loads(json.dumps(LICENSED_HADITH))
    result["text"]["translation"] = {
        "language": "ur",
        "content": "اردو ترجمہ",
        "sourceKind": "official",
        "sourceLabel": "Official",
        "isRTL": True,
    }
    result["text"]["translationRequested"] = True
    result["text"]["translationFallback"] = False
    result["text"].update(over)
    return result


def with_page(browser, url, mock):
    context = browser.new_context()
    context.route("**/api/query", mock)
    page = context.new_page()
    page.goto(url)
    page.wait_for_load_state("networkidle")
    return page


def expect_visible(page, selector):
    element = page.locator(selector)
    assert element.is_visible(), f"{selector} should be visible"


def hidden(page, selector):
    element = page.locator(selector)
    assert element.count() == 0 or not element.is_visible(), (
        f"{selector} should be hidden"
    )


def main():
    server = serve()
    failures = []

    def check(name, fn):
        try:
            fn()
            print(f"PASS {name}")
        except AssertionError as error:
            failures.append(name)
            print(f"FAIL {name}: {error}")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)

        def licensed_text():
            page = with_page(
                browser,
                f"{BASE}/hadith/bukhari/57?locale=ur",
                resolver_mock(licensed_with_translation()),
            )
            expect_visible(page, "#canonical-resolved")
            assert page.locator("#canonical-reference").inner_text() == (
                "Bukhari · Hadith 57"
            )
            expect_visible(page, "#canonical-scope")
            assert "Documented Sahih collection" in page.locator(
                "#canonical-scope"
            ).inner_text()
            expect_visible(page, "#canonical-arabic")
            arabic = page.locator("#canonical-arabic")
            assert arabic.get_attribute("dir") == "rtl"
            expect_visible(page, "#canonical-translation-block")
            translation = page.locator("#canonical-translation")
            assert translation.get_attribute("dir") == "rtl"
            assert translation.get_attribute("lang") == "ur"
            expect_visible(page, "#canonical-app-actions")
            assert page.locator("#canonical-open-app").get_attribute("href") == (
                f"{BASE}/hadith/bukhari/57?locale=ur"
            )

        check("licensed link renders arabic + translation", licensed_text)

        def provider_english_default():
            page = with_page(
                browser,
                f"{BASE}/hadith/bukhari/57",
                resolver_mock(LICENSED_HADITH),
            )
            expect_visible(page, "#canonical-translation-block")
            translation = page.locator("#canonical-translation")
            assert translation.get_attribute("lang") == "en"
            assert translation.get_attribute("dir") == "ltr"
            expect_visible(page, "#canonical-english-note")

        check("no locale requested shows labeled provider English", provider_english_default)

        def unsupported_locale():
            payload = json.loads(json.dumps(LICENSED_HADITH))
            payload["text"]["translationRequested"] = True
            payload["text"]["translationFallback"] = True
            page = with_page(
                browser,
                f"{BASE}/hadith/bukhari/57?locale=zz",
                resolver_mock(payload),
            )
            expect_visible(page, "#canonical-fallback-note")
            assert page.locator("#canonical-translation").get_attribute(
                "lang"
            ) == "en"

        check("unsupported locale degrades with a visible label", unsupported_locale)

        def unlicensed():
            payload = json.loads(json.dumps(LICENSED_HADITH))
            payload["text"] = {"visible": False, "translationRequested": False}
            page = with_page(
                browser,
                f"{BASE}/hadith/bukhari/57",
                resolver_mock(payload),
            )
            expect_visible(page, "#canonical-unlicensed")
            hidden(page, "#canonical-arabic")
            expect_visible(page, "#canonical-scope")
            expect_visible(page, "#canonical-app-actions")

        check("unverified license hides all text", unlicensed)

        def ai_label():
            payload = licensed_with_translation()
            payload["text"]["translation"] = {
                "language": "tr",
                "content": "AI çeviri",
                "sourceKind": "gemini_ai",
                "sourceLabel": "AI",
                "isRTL": False,
            }
            page = with_page(
                browser,
                f"{BASE}/hadith/bukhari/57?locale=tr",
                resolver_mock(payload),
            )
            expect_visible(page, "#canonical-fallback-note")
            note = page.locator("#canonical-fallback-note").inner_text()
            assert "AI-generated" in note, note

        check("AI translation is labeled", ai_label)

        def malformed():
            page = with_page(browser, f"{BASE}/hadith/Bukhari/57/extra", None)
            expect_visible(page, "#canonical-invalid")
            hidden(page, "#canonical-resolved")
            page = with_page(browser, f"{BASE}/hadith/bukhari", None)
            expect_visible(page, "#canonical-invalid")
            page = with_page(browser, f"{BASE}/hadith/bukhari/x57", None)
            expect_visible(page, "#canonical-invalid")
            page = with_page(browser, f"{BASE}/hadith/bukhari/57//", None)
            expect_visible(page, "#canonical-invalid")

        check("malformed links render the invalid state", malformed)

        def stale():
            page = with_page(
                browser,
                f"{BASE}/hadith/bukhari/9999",
                resolver_mock(
                    {
                        "status": "not_found",
                        "route": {
                            "collectionSlug": "bukhari",
                            "providerHadithId": "9999",
                        },
                    }
                ),
            )
            expect_visible(page, "#canonical-notfound")
            hidden(page, "#canonical-resolved")

        check("stale/removed hadith renders the not-found state", stale)

        def resolver_downgrade():
            # When the resolver is unreachable, the page must degrade to a
            # quiet message, never render a wrong state or crash.
            def failing(route):
                route.abort()

            page = with_page(
                browser, f"{BASE}/hadith/bukhari/57", failing
            )
            assert "could not load" in page.locator("#canonical-status").inner_text()
            hidden(page, "#canonical-resolved")

        check("resolver outage degrades safely", resolver_downgrade)

        browser.close()

    server.shutdown()
    if failures:
        raise SystemExit(f"{len(failures)} failing scenarios: {failures}")
    print("All F3 Playwright scenarios passed.")


if __name__ == "__main__":
    main()
