/**
 * Canonical hadith link fallback (F3).
 *
 * Renders `https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}`
 * with licensed text, source identity, authenticity scope, and app actions.
 * The route is parsed and validated in the browser (the same contract as
 * backend/convex/lib/canonicalLinks.ts), then one public Convex query fills
 * the page. Nothing here generates AI content or reads private positions.
 */
(function () {
  "use strict";

  var PREFIX = "/hadith/";
  var COLLECTION_SLUG_PATTERN = /^[a-z][a-z0-9-]{1,31}$/;
  var PROVIDER_HADITH_ID_PATTERN = /^[1-9][0-9]{0,11}(\.[0-9]{1,12})*$/;

  var status = document.getElementById("canonical-status");
  var resolvedEl = document.getElementById("canonical-resolved");
  var invalidEl = document.getElementById("canonical-invalid");
  var notFoundEl = document.getElementById("canonical-notfound");
  var appActionsEl = document.getElementById("canonical-app-actions");

  function show(element) {
    element.removeAttribute("hidden");
  }

  function parsePath(path) {
    var trimmed = path.replace(/\/+$/, "");
    if (trimmed.indexOf(PREFIX) !== 0) return null;
    var rest = trimmed.slice(PREFIX.length);
    var segments = rest.split("/").filter(function (s) { return s.length > 0; });
    if (segments.length !== 2) return null;
    if (!COLLECTION_SLUG_PATTERN.test(segments[0])) return null;
    if (!PROVIDER_HADITH_ID_PATTERN.test(segments[1])) return null;
    return { collectionSlug: segments[0], providerHadithId: segments[1] };
  }

  function parseLink(href) {
    var parsed = null;
    try {
      parsed = new URL(href);
    } catch (err) {
      return null;
    }
    // This page is only ever served from its own origin, so the path is the
    // trust boundary here; full host+scheme validation belongs to the native
    // link routers (backend/convex/lib/canonicalLinks.ts owns the contract).
    return parsePath(parsed.pathname);
  }

  function escapeHTML(value) {
    var div = document.createElement("div");
    div.textContent = value;
    return div.innerHTML;
  }

  function setElementText(id, text) {
    document.getElementById(id).textContent = text;
  }

  function showInvalid() {
    status.setAttribute("hidden", "");
    show(invalidEl);
  }

  function showNotFound() {
    status.setAttribute("hidden", "");
    show(notFoundEl);
    setElementText(
      "canonical-reference",
      "That hadith is not available."
    );
  }

  function renderResolved(result, request) {
    status.setAttribute("hidden", "");
    show(resolvedEl);

    setElementText("canonical-reference", result.referenceDisplay);
    var meta = result.collectionName;
    if (result.narrator) meta += " · Narrated by " + result.narrator;
    meta += " · Source: " + result.sourceName;
    setElementText("canonical-meta", meta);

    var scope = document.getElementById("canonical-scope");
    scope.textContent = result.authenticity.sourceLabel + " · " + result.sourceName;
    scope.setAttribute("title", result.authenticity.sourceUrl);

    var text = result.text;
    var textSection = document.getElementById("canonical-text");
    var unlicensed = document.getElementById("canonical-unlicensed");
    var openApp = document.getElementById("canonical-open-app");
    openApp.setAttribute("href", request.href);

    if (text.visible) {
      setElementText("canonical-arabic", text.arabicText);
      var translationBlock = document.getElementById("canonical-translation-block");
      var englishNote = document.getElementById("canonical-english-note");
      var fallbackNote = document.getElementById("canonical-fallback-note");
      var translationEl = document.getElementById("canonical-translation");
      if (text.translation) {
        translationEl.textContent = text.translation.content;
        translationEl.setAttribute("dir", text.translation.isRTL ? "rtl" : "ltr");
        translationEl.setAttribute("lang", text.translation.language);
        show(translationBlock);
        if (text.translation.sourceKind === "gemini_ai") {
          fallbackNote.textContent =
            "Translation: " + text.translation.sourceLabel + "-generated text. " +
            "Hadithly never presents AI text as authoritative.";
          show(fallbackNote);
        }
      } else if (text.providerEnglish) {
        translationEl.textContent = text.providerEnglish;
        translationEl.setAttribute("dir", "ltr");
        translationEl.setAttribute("lang", "en");
        show(translationBlock);
        if (text.translationRequested) {
          show(fallbackNote);
        } else {
          show(englishNote);
        }
      }
      show(textSection);
    } else {
      show(unlicensed);
    }

    show(appActionsEl);
  }

  function fetchResult(route, params) {
    var args = {
      collectionSlug: route.collectionSlug,
      providerHadithId: route.providerHadithId,
    };
    var locale = params.get("locale");
    if (locale) args.locale = locale;
    var pos = params.get("pos");
    if (pos) args.pos = pos;
    return fetch(window.HADITHLY_CONVEX_URL + "/api/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        path: "hadiths:resolveCanonicalLink",
        args: args,
        format: "json",
      }),
    }).then(function (response) {
      if (!response.ok) throw new Error("resolver " + response.status);
      return response.json();
    });
  }

  function run() {
    var request = { href: null };
    var href = window.location.href;
    request.href = href;

    var route = parseLink(href);
    if (!route) {
      showInvalid();
      return;
    }

    var params = new URLSearchParams(window.location.search);
    fetchResult(route, params).then(function (payload) {
      var result = payload && payload.value;
      if (!result) throw new Error("empty resolver result");
      if (result.status === "not_found") {
        showNotFound();
      } else {
        renderResolved(result, request);
      }
    }).catch(function () {
      status.textContent =
        "This page could not load the hadith. Try again, or open the app.";
    });
  }

  run();
})();
