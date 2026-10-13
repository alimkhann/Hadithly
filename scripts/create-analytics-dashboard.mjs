#!/usr/bin/env node
import fs from 'node:fs';

const environment = process.argv.includes('--production') ? 'production' : 'development';
const settledWindow = "if(toDate(properties.day) >= today() - 8, 'Latest 7 settled days', 'Previous 7 settled days')";
const window = environment === 'development' ? `if(toDate(properties.day) >= today() - 1, 'Unsettled development verification', ${settledWindow})` : settledWindow;
const filter = `properties.environment = '${environment}' AND timestamp >= today() - 15 AND timestamp < ${environment === 'development' ? 'today() + 1' : 'today() - 1'}`;
const recoveryVariants = {
  onboarding_step: ['authentication', 'authentication_recovered'], reader_open_result: ['reader', 'reader_recovered'],
  offline_activation_result: ['offline', 'offline_recovered'], translation_result: ['translation', 'translation_recovered'],
  paywall_result: ['purchase', 'purchase_recovered'],
};
const chart = (families) => {
 const recovery = recoveryVariants[families[0]] ?? [];
 const familyFilter = `(${families.map(x => `event = '${x}'`).join(' OR ')}${recovery.length ? ` OR (event = 'recoverable_error' AND properties.variant IN (${recovery.map(x => `'${x}'`).join(',')}))` : ''})`;
 return { kind: 'DataVisualizationNode', display: 'ActionsTable', source: { kind: 'HogQLQuery', query:
  `WITH counts AS (SELECT properties.platform AS platform, ${window} AS period, event AS family, properties.variant AS outcome, sum(toFloat(properties.count)) AS outcomes FROM events WHERE ${filter} AND ${familyFilter} GROUP BY platform, period, family, outcome), denominators AS (SELECT platform, period, family,
    sumIf(outcomes, outcome = 'started') AS starts,
    sumIf(outcomes, outcome = 'guest_started') AS guest_starts,
    sumIf(outcomes, outcome = 'account_started') AS account_starts,
    sumIf(outcomes, outcome = 'ordered_started') AS onboarding_starts,
    sumIf(outcomes, outcome = 'shown') AS offers,
    sumIf(outcomes, outcome = 'available') AS available_offers,
    sumIf(outcomes, outcome = 'purchase_started') AS store_starts,
    sumIf(outcomes, outcome IN ('monthly_started','annual_started')) AS purchases,
    sumIf(outcomes, outcome = 'restore_started') AS restores,
    sumIf(outcomes, outcome IN ('guest','account_new','account_existing','account_unknown')) AS entries
    FROM counts GROUP BY platform, period, family)
    SELECT c.platform AS platform, c.period AS period, c.family AS family, c.outcome AS outcome, c.outcomes AS total,
    multiIf(c.family = 'onboarding_completed' AND c.outcome != 'first_reader_success', d.entries,
      c.family = 'onboarding_step' AND startsWith(c.outcome,'ordered_'), d.onboarding_starts,
      c.family = 'reader_open_result' AND startsWith(c.outcome,'guest_'), d.guest_starts,
      c.family = 'reader_open_result' AND startsWith(c.outcome,'account_'), d.account_starts,
      c.family = 'reader_open_result', d.guest_starts + d.account_starts,
      c.family = 'paywall_result' AND c.outcome IN ('selected_monthly','selected_annual'), 0,
      c.family = 'paywall_result' AND c.outcome = 'confirmed', d.store_starts,
      c.family = 'paywall_result' AND c.outcome = 'purchase_started', d.available_offers,
      c.family = 'paywall_result', d.offers,
      c.family = 'purchase_result' AND startsWith(c.outcome,'restore_'), d.restores,
      c.family = 'purchase_result', d.purchases, d.starts) AS opportunities,
    if(opportunities >= 20 AND c.outcomes <= opportunities, round(100 * c.outcomes / opportunities, 1), NULL) AS percent,
    multiIf(opportunities = 0, 'Descriptive outcome total', opportunities < 20, 'Too little data to judge', c.outcomes > opportunities, 'Measurement inconsistent; investigate clipping', 'Review outcomes') AS interpretation
    FROM counts AS c JOIN denominators AS d ON c.platform = d.platform AND c.period = d.period AND c.family = d.family
    ORDER BY platform, family, outcome, period` } }; };
const panels = [
  ['First experience', ['onboarding_step', 'onboarding_completed'], 'Ordered stages share the same local start-hour cohort: started -> language -> demo -> entry -> completed -> first reader. Divide ordered outcomes only. Window is 30 minutes and ends on process death. Demo/auth interactions may repeat; views are local sequence signals. Account outcomes use the completed Clerk resource; unknown hosted completion is explicit. These are flows, not distinct accounts.'],
  ['Reading reliability', ['reader_open_result', 'restoration_result'], 'Successful opens / started opens, split by platform and guest/account. Exact restores / started restores; fallback freezes at the initial acknowledged landing; closing while pending is abandonment. Inspect failures before redesigning.'],
  ['Offline and notifications', ['offline_activation_result', 'notification_open_result'], 'Verified activations / admitted downloads; exact opens / notification-open attempts. No delivered-notification denominator exists, so this is not click-through rate.'],
  ['Translation demand', ['translation_result'], 'Explicit requests only. Compare cache/generated/quota/failure outcomes. Reader page loading does not generate translations. Cache reading remains free.'],
  ['Purchase journey', ['paywall_result', 'purchase_result'], 'Ordered offer available -> purchase started -> confirmed backend access in one uninterrupted local 30-minute flow. Selection taps are descriptive. Purchase events do not prove revenue. Inspect pending/syncing/failed and restore outcomes. RevenueCat is the financial source of truth.'],
  ['Measurement health', ['recoverable_error'], 'Latest reported admission and export budgets plus fixed recoverable operation counts. A stale or missing reported hour means check Convex before interpreting the other panels. It is not a current real-time billing readback.'],
];
const specification = { name: 'Hadithly launch health', description:
  `Private grouped statistics. Environment: ${environment}. UTC days settle after 24h. Small buckets below 10 summaries are suppressed; summaries are not distinct people. Caps/expiry/process death can remove observations. Below 20 opportunities: too little data to judge. Check Convex analytics:health for current admission/export budget and lag. No revenue, retention, duration or per-reader history is measured.`,
  panels: panels.map(([name, families, description]) => ({ name: `LA2 · ${name}`, description, query: name === 'Measurement health'
    ? { kind: 'DataVisualizationNode', display: 'ActionsTable', source: { kind: 'HogQLQuery', query:
      `SELECT properties.measurement_month AS month, max(toFloat(properties.admitted_monthly)) AS admitted_summaries, max(toFloat(properties.exported_monthly)) AS reserved_export_envelopes, max(toFloat(properties.export_failures)) AS export_failures, max(toFloat(properties.rejected_monthly)) AS rejected_summaries_month, argMax(toFloat(properties.suppressed_buckets), toFloat(properties.observed_hour)) AS suppressed_buckets_last_report, coalesce(sumIf(toFloat(properties.count), event = 'recoverable_error' AND properties.variant = 'measurement_clipped'), 0) AS clipping_markers_in_window, toDateTime(max(toFloat(properties.observed_hour)) * 3600) AS last_reported_utc FROM events WHERE ${filter} GROUP BY month ORDER BY month DESC` } }
    : chart(families) })) };

if (!process.argv.includes('--apply')) {
  process.stdout.write(JSON.stringify(specification, null, 2) + '\n');
} else {
  const key = process.env.POSTHOG_PERSONAL_API_KEY;
  const project = process.env.POSTHOG_PROJECT_ID;
  if (!key || !project || !/^[1-9][0-9]*$/.test(project)) throw new Error('Set private POSTHOG_PERSONAL_API_KEY and POSTHOG_PROJECT_ID locally');
  const base = `https://eu.posthog.com/api/projects/${project}`;
  const request = async (path, method = 'GET', body) => {
    const result = await fetch(base + path, { method, redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) });
    if (!result.ok) throw new Error(`PostHog operation failed with HTTP ${result.status}`);
    return result.json();
  };
  const listAll = async path => {
    const rows = [];
    for (let page = 0; path && page < 100; page++) {
      const body = await request(path); rows.push(...(body.results ?? []));
      if (!body.next) return rows;
      const next = new URL(body.next, base);
      if (next.origin !== 'https://eu.posthog.com' || !next.pathname.startsWith(`/api/projects/${project}/`)) throw new Error('Unsafe pagination destination');
      path = next.pathname.slice(`/api/projects/${project}`.length) + next.search;
    }
    throw new Error('Dashboard pagination exceeded bound');
  };
  const dashboards = await listAll('/dashboards/?limit=100');
  const match = dashboards.find(item => item.name === specification.name);
  const dashboard = match ? await request(`/dashboards/${match.id}/`, 'PATCH', { description: specification.description })
    : await request('/dashboards/', 'POST', { name: specification.name, description: specification.description });
  const existing = await listAll(`/insights/?dashboard=${dashboard.id}&limit=100`);
  for (const panel of specification.panels) {
    const found = existing.find(item => item.name === panel.name);
    const body = { ...panel, saved: true, dashboards: [...new Set([...(found?.dashboards ?? []), dashboard.id])] };
    if (found) await request(`/insights/${found.id}/`, 'PATCH', body);
    else await request('/insights/', 'POST', body);
  }
  const readback = await request(`/dashboards/${dashboard.id}/`);
  const placement = new Map([
    ['LA2 · Measurement health', { x: 0, y: 0, w: 12, h: 6 }],
    ['LA2 · Reading reliability', { x: 0, y: 6, w: 12, h: 10 }],
    ['LA2 · Purchase journey', { x: 0, y: 16, w: 12, h: 10 }],
    ['LA2 · First experience', { x: 0, y: 26, w: 12, h: 10 }],
    ['LA2 · Offline and notifications', { x: 0, y: 36, w: 12, h: 8 }],
    ['LA2 · Translation demand', { x: 0, y: 44, w: 12, h: 8 }],
  ]);
  // Include every existing tile: omitted tiles would be removed by this endpoint.
  await request(`/dashboards/${dashboard.id}/`, 'PATCH', { tiles: readback.tiles.map(tile => {
    const box = placement.get(tile.insight?.name);
    return box ? { id: tile.id, layouts: { sm: box } } : { id: tile.id };
  }) });
  // Query execution is separate from configuration. Do not call configuration a pass.
  for (const panel of specification.panels) await request('/query/', 'POST', { query: panel.query.source });
  console.log(`Dashboard ${dashboard.id}: configured and queried six ${environment} panels. Verify dashboard readback and native journeys before declaring LA2 passed.`);
}
