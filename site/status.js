(() => {
  const freshness = document.getElementById("status-freshness"), components = document.getElementById("components"), incidents = document.getElementById("incidents");
  const states = { operational: "Operational", degraded: "Degraded", outage: "Unavailable", unknown: "Not assessed" };
  fetch("/status/data.json", { cache: "no-store", credentials: "omit", signal: AbortSignal.timeout(5000) }).then(async response => {
    if (!response.ok) throw new Error("status unavailable");
    const data = await response.json();
    if (!Array.isArray(data.components) || data.components.length !== 5 || !Array.isArray(data.incidents) || data.incidents.length > 20) throw new Error("invalid status");
    const time = Date.parse(data.updatedAt), age = Date.now() - time;
    const stale = !Number.isFinite(time) || age < 0 || age > 30 * 60_000;
    freshness.textContent = stale ? "This assessment is stale. Current availability is unknown."
      : `Operator update: ${new Date(time).toLocaleString()}.`;
    for (const component of data.components) {
      if (typeof component.name !== "string" || !Object.hasOwn(states, component.state)) throw new Error("invalid component");
      const item = document.createElement("li");
      item.textContent = `${component.name}: ${stale ? states.unknown : states[component.state]}`; components.append(item);
    }
    for (const incident of data.incidents) {
      if (!["investigating", "identified", "monitoring", "resolved"].includes(incident.state)
        || typeof incident.exercise !== "boolean" || ["title", "impact", "mitigation", "resolution", "startedAt"].some(key => typeof incident[key] !== "string")) throw new Error("invalid incident");
      const article = document.createElement("article"); article.className = "card";
      const heading = document.createElement("h3"); heading.textContent = `${incident.exercise ? "Exercise · " : ""}${incident.title}`; article.append(heading);
      for (const line of [`${incident.state} · Started ${incident.startedAt}${incident.resolvedAt ? ` · Resolved ${incident.resolvedAt}` : ""}`, incident.impact, incident.mitigation, incident.resolution]) {
        const p = document.createElement("p"); p.textContent = line; article.append(p);
      }
      incidents.append(article);
    }
  }).catch(() => { components.replaceChildren(); incidents.replaceChildren(); freshness.textContent = "Status updates could not be loaded. Current availability is unknown. Please contact support."; });
})();
