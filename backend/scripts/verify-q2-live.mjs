import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';

const execute = promisify(execFile);
const deployment = 'festive-cobra-664';
const identity = { subject: 'user_q2_verification_20261012', issuer: 'https://q2-verification.invalid' };
const endpoint = 'https://festive-cobra-664.eu-west-1.convex.site/webhooks/revenuecat';
async function cli(args) {
  return (await execute('npx', ['convex', ...args, '--deployment', deployment], { timeout: 60000, maxBuffer: 1000000 })).stdout.trim();
}
async function run(name, args = {}, authenticated = false) {
  const output = await cli(['run', name, JSON.stringify(args), ...(authenticated ? ['--identity', JSON.stringify(identity)] : [])]);
  return output ? JSON.parse(output) : null;
}
async function existingUserIds() {
  return JSON.parse(await cli(['run', '--inline-query', 'return (await ctx.db.query("users").take(500)).map(row => row._id).sort();']));
}
const before = await existingUserIds();
let created = false;
let stage = "fixture lookup";
try {
  const user = await run('users:getCurrentUser', {}, true);
  assert.equal(user, null, 'Refuse to modify an existing account with this fixture identity.');
  stage = 'fixture creation';
  await run('users:ensureCurrentUser', {}, true); created = true;
  stage = 'RevenueCat reconciliation';
  assert.equal(await run('actions/subscriptions:refresh', {}, true), false);
  assert.equal((await run('quotas:getTranslationAllowance', {}, true)).limit, 5);
  console.log('PASS: deployed authenticated action with CLI fixture identity -> real RevenueCat GET -> Free. This is not Clerk/store proof.');
  stage = 'signed webhook';
  const key = await cli(['env', 'get', 'REVENUECAT_WEBHOOK_SECRET']);
  const post = async (id, authorization = key) => fetch(endpoint, {
    method: 'POST', headers: { Authorization: authorization, 'Content-Type': 'application/json' },
    body: JSON.stringify({ event: { id, type: 'INITIAL_PURCHASE', app_id: 'appef5df40f41', environment: 'SANDBOX',
      app_user_id: identity.subject, entitlement_ids: ['pro'], product_id: 'com.hadithly.app.pro.monthly', expiration_at_ms: Date.now() + 60000 } }),
  });
  assert.equal((await post(randomUUID(), 'incorrect-fixture-authorization')).status, 401);
  const id = randomUUID(); assert.equal((await post(id)).status, 200);
  let completed = false;
  for (let i = 0; i < 20; i++) {
    completed = await run('subscriptions:deliveryCompleted', { eventId: id });
    if (completed) break;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert.equal(completed, true, 'Queued webhook must finish real subscriber reconciliation.');
  const state = await run('users:getCurrentUser', {}, true);
  assert.equal((await run('quotas:getTranslationAllowance', {}, true)).limit, 5);
  assert.equal((await post(id)).status, 200);
  const afterReplay = await run('users:getCurrentUser', {}, true);
  assert.equal(afterReplay.subscriptionRefreshRevision, state.subscriptionRefreshRevision);
  console.log('PASS: real signed dev HTTP -> durable queue -> RevenueCat current snapshot -> no fabricated Pro; completed replay changes no revision.');
  for (const phase of ['paid', 'cancelled', 'grace']) {
    const ticket = await run('subscriptions:beginRefresh', { clerkId: identity.subject, deny: false, ownershipConflict: false });
    const until = Date.now() + 60000;
    await run('subscriptions:applySnapshot', { ...ticket, observedAt: Date.now(), ownershipConflict: false,
      purchases: [{ productId: 'com.hadithly.app.pro.monthly', store: 'app_store', paidUntil: phase === 'grace' ? Date.now() - 1 : until, until, phase }] });
    assert.equal((await run('subscriptions:getStatus', {}, true)).phase, phase);
    assert.equal((await run('quotas:getTranslationAllowance', {}, true)).limit, 100);
  }
  assert.equal(await run('actions/subscriptions:refresh', {}, true), false);
  assert.equal((await run('quotas:getTranslationAllowance', {}, true)).limit, 5);
  console.log('PASS: finite fixture paid/cancelled/grace projections share quota authority; real reconciliation removes unsupported fixture grants. Not sandbox purchases.');
} catch (error) {
  const code = String(error?.stderr ?? '').match(/(?:SUBSCRIPTIONS_NOT_CONFIGURED|SUBSCRIPTION_REFRESH_UNAVAILABLE|INVALID_SUBSCRIPTION_SNAPSHOT|SUBSCRIPTION_REFRESH_SUPERSEDED|Could not find function)/)?.[0];
  console.error(stage + ': ' + (error?.code === 'ERR_ASSERTION' ? error.message : code ?? 'verification failed; raw credential diagnostics suppressed'));
  process.exitCode = 1;
} finally {
  if (created) await run('users:deleteCurrentUser', {}, true);
  assert.deepEqual(await existingUserIds(), before, 'Existing account IDs changed.');
  console.log('PASS: private development fixture removed; original accounts preserved. One empty RevenueCat verification profile has no store transactions or personal data.');
}
