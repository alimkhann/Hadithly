(() => {
  const config = window.HADITHLY_OPERATIONS;
  const form = document.getElementById("support-form"), result = document.getElementById("form-result");
  if (!config?.enabled || !config.turnstileSiteKey || !form || !result) return;
  let endpoint;
  try { endpoint = new URL(config.endpoint); } catch { return; }
  if (endpoint.protocol !== "https:" || !["festive-cobra-664.eu-west-1.convex.site", "giddy-ox-648.eu-west-1.convex.site"].includes(endpoint.hostname)
    || endpoint.pathname !== "/support/request" || endpoint.search || endpoint.hash || endpoint.username || endpoint.password || endpoint.port) return;
  form.hidden = false;
  document.getElementById("form-unavailable").hidden = true;
  let token = "", widget;
  const requestId = crypto.randomUUID();
  window.onSupportTurnstile = () => {
    widget = window.turnstile.render("#support-challenge", { sitekey: config.turnstileSiteKey, action: "support",
      callback: value => { token = value; }, "expired-callback": () => { token = ""; }, "error-callback": () => { token = ""; } });
  };
  const script = document.createElement("script");
  script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onSupportTurnstile&render=explicit";
  script.async = true; script.defer = true;
  script.onerror = () => { result.textContent = "The security check is unavailable. Please email support."; };
  document.head.append(script);
  form.addEventListener("submit", async event => {
    event.preventDefault();
    if (!token) { result.textContent = "Complete the security check before sending."; return; }
    const button = document.getElementById("send-request"); button.disabled = true;
    const values = new FormData(form);
    result.textContent = "Sending…";
    try {
      const response = await fetch(endpoint.href, { method: "POST", credentials: "omit", redirect: "error", signal: AbortSignal.timeout(15_000),
        headers: { "Content-Type": "application/json" }, body: JSON.stringify({ requestId, token,
          email: values.get("email"), topic: values.get("topic"), platform: values.get("platform"), message: values.get("message"), website: values.get("website") }) });
      if (response.status === 202) {
        form.reset(); form.hidden = true;
        result.textContent = `Request accepted. Reference: ${requestId}. We aim to reply within two business days. For urgent account access, use Clerk's recovery options. This receipt does not confirm email delivery.`;
        return;
      }
      result.textContent = response.status === 429 ? "The request limit was reached. Please email support or try tomorrow."
        : "The request could not be accepted. Your text is still here. Retry the security check or email support.";
    } catch { result.textContent = "Delivery could not be confirmed. Your text is still here. Retry the security check or email support."; }
    finally { token = ""; if (widget !== undefined) window.turnstile.reset(widget); button.disabled = false; }
  });
})();
