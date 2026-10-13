(function () {
  "use strict";
  var consentKey = "hadithly.page-error-consent";
  var count = 0;
  function consent() {
    try { return localStorage.getItem(consentKey) === "yes"; } catch (_) { return false; }
  }
  function setConsent(enabled) {
    try { localStorage.setItem(consentKey, enabled ? "yes" : "no"); } catch (_) {}
  }
  function report(operation) {
    if (!consent() || count >= 1 || !/^(canonical_resolver|synthetic)$/.test(operation)
        || !/^hadithly@[a-f0-9]{12}$/.test(window.HADITHLY_DIAGNOSTICS_RELEASE || "")) return Promise.resolve();
    if (operation === "synthetic" && window.HADITHLY_DIAGNOSTICS_ENVIRONMENT !== "development") return Promise.resolve();
    count += 1;
    return fetch(window.HADITHLY_DIAGNOSTICS_API + "/diagnostics/web", {
      method: "POST", credentials: "omit", referrerPolicy: "no-referrer", redirect: "error",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ operation: operation, release: window.HADITHLY_DIAGNOSTICS_RELEASE,
        environment: window.HADITHLY_DIAGNOSTICS_ENVIRONMENT }),
      signal: AbortSignal.timeout(3000)
    }).then(function () {}, function () {});
  }
  window.HadithlyDiagnostics = { failure: function () { return report("canonical_resolver"); },
    synthetic: function () { return report("synthetic"); }, setConsent: setConsent, hasConsent: consent };
  var control = document.getElementById("page-error-consent");
  if (control) {
    control.checked = consent();
    control.addEventListener("change", function () { setConsent(control.checked); });
  }
})();
