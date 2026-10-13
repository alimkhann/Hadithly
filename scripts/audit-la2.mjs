#!/usr/bin/env node
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

execFileSync('python3', ['scripts/generate-analytics-catalog.py', '--check']);
execFileSync('python3', ['scripts/generate-la2-copy.py', '--check']);
const catalog = JSON.parse(fs.readFileSync('docs/analytics-catalog.json', 'utf8'));
const dashboard = JSON.parse(fs.readFileSync('docs/LA2_DASHBOARD.json', 'utf8'));
const generated = JSON.parse(execFileSync(process.execPath, ['scripts/create-analytics-dashboard.mjs'], { encoding: 'utf8' }));
assert.deepEqual(dashboard, generated);
assert.equal(Object.keys(catalog.families).length, 10);
assert.equal(dashboard.panels.length, 6);
const metrics = new Set(Object.entries(catalog.families).flatMap(([family, variants]) => variants.map(variant => `${family}.${variant}`)));
const allowed = new Set(['$geoip_disable', '$process_person_profile', 'count', 'day', 'distinct_id', 'environment', 'platform', 'schema_version', 'variant',
  'measurement_month', 'admitted_monthly', 'exported_monthly', 'export_failures', 'rejected_monthly', 'suppressed_buckets', 'observed_hour']);

if (process.argv.includes('--dev-ingress')) {
  const summary = { version: 1, platform: 'ios', batchId: randomUUID(), hour: Math.floor(Date.now() / 3_600_000), counters: [{ metric: 'onboarding_completed.guest', count: 1 }] };
  const endpoint = 'https://festive-cobra-664.eu-west-1.convex.site/analytics/summary';
  for (const key of ['text', 'translation', 'notes', 'evidence', 'search', 'canonicalId', 'email', 'token', 'locale', 'harmless_unknown']) {
    const response = await fetch(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, redirect: 'error',
      signal: AbortSignal.timeout(5000), body: JSON.stringify({ ...summary, [key]: 'LA2_FORBIDDEN_CANARY' }) });
    assert.equal(response.status, 400, `Ingress must reject ${key}`);
  }
  const expired = await fetch(endpoint, { method: 'POST', headers: { 'Content-Type': 'application/json' }, redirect: 'error',
    signal: AbortSignal.timeout(5000), body: JSON.stringify({ ...summary, hour: summary.hour - 24 }) });
  assert.equal(expired.status, 400);
  console.log('Live development ingress rejected ten unknown keys and expired summary.');
}
if (process.argv.includes('--live')) {
  const project = process.env.POSTHOG_PROJECT_ID, key = process.env.POSTHOG_PERSONAL_API_KEY;
  assert.ok(project && /^[1-9][0-9]*$/.test(project) && key, 'Provide a private scoped PostHog credential locally');
  const dashboardResponse = await fetch(`https://eu.posthog.com/api/projects/${project}/dashboards/1020618/`, {
    redirect: 'error', signal: AbortSignal.timeout(10_000), headers: { Authorization: `Bearer ${key}` } });
  assert.equal(dashboardResponse.status, 200);
  const remoteDashboard = await dashboardResponse.json();
  for (const panel of dashboard.panels) {
    const tile = remoteDashboard.tiles.find(tile => tile.insight?.name === panel.name);
    assert.ok(tile, `Missing dashboard panel: ${panel.name}`);
    assert.equal(tile.insight.query?.source?.query, panel.query.source.query, 'Stored dashboard query must match approved definition');
    assert.equal(tile.layouts?.sm?.w, 12, 'Tables must remain readable at full width');
  }
  const response = await fetch(`https://eu.posthog.com/api/projects/${project}/query/`, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10_000),
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: { kind: 'HogQLQuery',
      query: "SELECT event, properties FROM events WHERE properties.environment = 'development' ORDER BY timestamp DESC LIMIT 1000" } }) });
  assert.equal(response.status, 200, 'Provider query must succeed');
  const data = await response.json(); assert.ok(Array.isArray(data.results) && data.results.length > 0, 'Provider evidence is required');
  const grouped = new Map(), observedKeys = new Set();
  for (const [family, rawProperties] of data.results) {
    const properties = typeof rawProperties === 'string' ? JSON.parse(rawProperties) : rawProperties;
    const keys = Object.keys(properties);
    keys.forEach(key => { assert.ok(allowed.has(key), `Unapproved stored provider property: ${key}`); observedKeys.add(key); });
    assert.equal(properties.schema_version, 1);
    assert.equal(properties.$process_person_profile, false); assert.equal(properties.$geoip_disable, true);
    assert.equal(properties.environment, 'development');
    assert.ok(['ios', 'android'].includes(properties.platform));
    assert.equal(properties.distinct_id, `aggregate:${properties.day}:${properties.platform}:development`);
    const metric = `${family}.${properties.variant}`;
    assert.ok(metrics.has(metric)); assert.ok(Number.isSafeInteger(properties.count) && properties.count > 0);
    const groupKey = `${properties.platform}:${properties.day}:${metric}`;
    grouped.set(groupKey, (grouped.get(groupKey) ?? 0) + properties.count);
  }
  const rows = [...grouped].map(([key, count]) => { const [platform, day, metric] = key.split(':'); return { platform, day, metric, count }; });
  for (const platform of ['ios', 'android']) {
    assert.equal(new Set(rows.filter(row => row.platform === platform).map(row => row.metric.split('.')[0])).size, 10);
    assert.ok(rows.some(row => row.platform === platform && row.metric === 'onboarding_step.ordered_first_reader' && row.count >= 5));
  }
  const native = JSON.parse(fs.readFileSync('docs/evidence/la2/native-counts.json','utf8'));
  for (const bucket of native.buckets) {
    const observed = rows.filter(row => row.platform === bucket.platform && row.day === bucket.day)
      .map(({metric,count})=>({metric,count})).sort((a,b)=>a.metric.localeCompare(b.metric));
    assert.deepEqual(observed, [...bucket.counters].sort((a,b)=>a.metric.localeCompare(b.metric)), 'Vendor totals must exactly match frozen native ingress counters');
  }
  const report = { matchedNativeCounts: true, checkedAt: new Date().toISOString(), environment: 'development', projectId: project, dashboardId: 1020618,
    propertyKeys: [...observedKeys].sort(), families: 10, rows: rows.sort((a,b) => `${a.platform}:${a.metric}`.localeCompare(`${b.platform}:${b.metric}`)),
    interpretation: 'Five synthetic native reducer/transport fixtures per platform plus real guest onboarding and reader verification traffic. Purchase, restoration, offline and notification fixture outcomes do not close live/device/store gates.' };
  fs.writeFileSync('docs/evidence/la2/provider-readback.json', JSON.stringify(report, null, 2) + '\n');
  console.log(`Provider readback passed: ${rows.length} grouped metric rows across both native platforms; no unknown properties.`);
}
execFileSync('npm', ['test', '--', 'convex/analytics.test.ts'], { cwd: 'backend', stdio: 'pipe' });
console.log(`LA2 audit passed: ${metrics.size} variants, ten families, six matching dashboard panels, strict payload/expiry/cap/retry tests.`);
