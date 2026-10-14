#!/usr/bin/env python3
"""Run through with_server.py against the local static site. Only synthetic data."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
BASE = "http://127.0.0.1:8766"
OUT = ROOT / "evidence/la3"
OUT.mkdir(parents=True, exist_ok=True)
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, channel="chrome")
    page = browser.new_page(viewport={"width": 390, "height": 844})
    page.route("**/operations-config.js", lambda route: route.fulfill(content_type="application/javascript", body='window.HADITHLY_OPERATIONS={enabled:false};'))
    page.goto(BASE + "/support/")
    expect(page.locator("#support-form")).to_be_hidden()
    expect(page.get_by_role("link", name="Email support@hadithly.app")).to_have_attribute("href", "mailto:support@hadithly.app")
    page.screenshot(path=str(OUT / "support-fallback.png"), full_page=True)
    page.unroute("**/operations-config.js")
    page.route("**/operations-config.js", lambda route: route.fulfill(content_type="application/javascript", body='window.HADITHLY_OPERATIONS={enabled:true,endpoint:"https://festive-cobra-664.eu-west-1.convex.site/support/request",turnstileSiteKey:"synthetic-sitekey"};'))
    # The widget is a deterministic test double. The backend suite separately
    # exercises Siteverify hostname/action/failure validation and the real HTTP route.
    page.route("https://challenges.cloudflare.com/**", lambda route: route.fulfill(content_type="application/javascript", body='window.turnstile={render:(selector,options)=>{options.callback("synthetic-token");return 1;},reset:()=>{}};window.onSupportTurnstile();'))
    requests = []
    def endpoint(route):
        if route.request.method == "OPTIONS":
            route.fulfill(status=204, headers={"Access-Control-Allow-Origin": BASE, "Access-Control-Allow-Methods": "POST", "Access-Control-Allow-Headers": "Content-Type"})
        else:
            requests.append(route.request.post_data_json)
            route.fulfill(status=202, headers={"Access-Control-Allow-Origin": BASE})
    page.route("https://festive-cobra-664.eu-west-1.convex.site/support/request", endpoint)
    page.reload()
    expect(page.locator("#support-form")).to_be_visible()
    page.get_by_label("Your reply email").fill("synthetic@example.invalid")
    page.get_by_label("How can we help?").fill("Synthetic support request. No real user data.")
    page.screenshot(path=str(OUT / "support-form.png"), full_page=True)
    page.get_by_role("button", name="Send request").click()
    expect(page.locator("#form-result")).to_contain_text("Request accepted.")
    assert len(requests) == 1
    assert set(requests[0]) == {"requestId", "email", "message", "topic", "platform", "token", "website"}
    assert requests[0]["website"] == ""
    assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth")
    page.goto(BASE + "/status/")
    expect(page.get_by_role("heading", name="Exercise · Synthetic translation outage exercise")).to_be_visible()
    expect(page.locator("#components li")).to_have_count(5)
    assert page.evaluate("document.documentElement.scrollWidth <= window.innerWidth")
    page.screenshot(path=str(OUT / "status-exercise.png"), full_page=True)
    data = json.loads((ROOT / "site/status/data.json").read_text())
    data["updatedAt"] = "2000-01-01T00:00:00Z"
    for component in data["components"]:
        component["state"] = "operational"
    page.route("**/status/data.json", lambda route: route.fulfill(json=data))
    page.reload()
    expect(page.locator("#status-freshness")).to_contain_text("stale")
    assert all("Not assessed" in text for text in page.locator("#components li").all_text_contents())
    data["incidents"][0]["title"] = '<img src=x onerror="window.injected=true">'
    page.reload()
    expect(page.locator("#incidents h3")).to_contain_text("<img")
    assert page.locator("#incidents img").count() == 0
    page.route("**/status/data.json", lambda route: route.fulfill(status=503))
    page.reload()
    expect(page.locator("#status-freshness")).to_contain_text("could not be loaded")
    page.goto(BASE + "/support/")
    page.unroute("https://festive-cobra-664.eu-west-1.convex.site/support/request")
    page.route("https://festive-cobra-664.eu-west-1.convex.site/support/request", lambda route: route.fulfill(status=429, headers={"Access-Control-Allow-Origin": BASE, "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Allow-Methods": "POST"}))
    page.get_by_label("Your reply email").fill("synthetic@example.invalid")
    page.get_by_label("How can we help?").fill("Synthetic preserved text after a failed request.")
    page.get_by_role("button", name="Send request").click()
    expect(page.locator("#form-result")).to_contain_text("limit")
    expect(page.get_by_label("How can we help?")).to_have_value("Synthetic preserved text after a failed request.")
    browser.close()
print("LA3 website: disabled fallback, form serialization, receipt, limits, preserved text, five components, synthetic incident, stale state, escaped content, outage and narrow viewport passed. External providers were test doubles.")
