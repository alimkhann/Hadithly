import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const execute = promisify(execFile);
const deployment = 'festive-cobra-664';
const identity = JSON.stringify({ subject: `e2_fixture_${randomUUID()}`, issuer: 'https://e2-verification.invalid' });
async function cli(args) {
  const { stdout } = await execute('npx', ['convex', ...args, '--deployment', deployment], { timeout: 180000, maxBuffer: 2000000 });
  return stdout.trim().startsWith('[') || stdout.trim().startsWith('{') || /^(true|false|null|"|\d)/.test(stdout.trim()) ? JSON.parse(stdout) : null;
}
async function run(name, args = {}) {
  return cli(['run', name, JSON.stringify(args), '--identity', identity]);
}
async function rows(table) { return (await cli(['data', table, '--format', 'json', '--limit', '100'])) ?? []; }
async function terminal(submissionId) {
  const deadline = Date.now() + 160000;
  while (Date.now() < deadline) {
    const snapshot = await run('evidence:getOwnEvidenceDraft', { submissionId });
    if (snapshot.status !== 'awaiting_processing') return snapshot;
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error('Processing deadline exceeded');
}
async function draft(url) {
  const created = await run('evidence:createEvidenceDraft', {
    hadithInternalId: 'sunnah_now:bukhari:1', language: 'en', proposedContent: 'Disposable E2 fixture, never publish.',
    draftKey: randomUUID(), items: [{ kind: 'url', clientItemKey: 'e2_url_fixture', url }],
  });
  await run('evidence:finalizeEvidenceDraft', { submissionId: created.submissionId });
  return created;
}
async function verify() {
  const tables = ['communitySubmissions', 'evidenceItems', 'evidenceExtractions', 'evidenceWorkerLease', 'translations', 'users'];
  const before = Object.fromEntries(await Promise.all(tables.map(async table => [table, (await rows(table)).map(row => row._id).sort()])));
  await run('users:ensureCurrentUser', { preferredLanguage: 'en' });
  try {
    const clean = await draft('https://example.org/');
    const ready = await terminal(clean.submissionId);
    assert.equal(ready.status, 'evidence_ready');
    assert.equal(ready.items[0].state, 'ready');
    for (const key of ['text', 'extractedText', 'storageId', 'sourceStorageId', 'scanner', 'signature']) {
      assert.ok(!(key in ready));
      assert.ok(!(key in ready.items[0]));
    }
    const extracted = (await rows('evidenceExtractions')).find(row => row.evidenceItemId === clean.items[0].itemId);
    assert.ok(extracted);
    assert.equal(extracted.trust, 'untrusted');
    assert.ok(extracted.sourceStorageId);
    assert.match(extracted.sha256, /^[a-f0-9]{64}$/);
    assert.ok(extracted.spans.length > 0);
    assert.ok(extracted.spans.every(span => span.start >= 0 && span.end <= extracted.text.length && span.source.kind === 'html_chars'));
    await run('evidence:deleteEvidenceDraft', { submissionId: clean.submissionId });
    console.log('Real Convex action → private Cloud Run → untrusted extraction → owned coarse state → withdrawal passed');

    const blocked = await draft('https://metadata.google.internal/latest');
    const failure = await terminal(blocked.submissionId);
    assert.equal(failure.status, 'processing_failed');
    assert.equal(failure.items[0].retryable, false);
    await run('evidence:deleteEvidenceDraft', { submissionId: blocked.submissionId });
    console.log('Real private destination fails closed without a retry passed');

    const unavailable = await draft('https://e2-verification.invalid/');
    for (let attempt = 1; attempt <= 3; attempt++) {
      const failed = await terminal(unavailable.submissionId);
      assert.equal(failed.status, 'processing_failed');
      assert.equal(failed.items[0].retryable, attempt < 3);
      if (attempt < 3) await run('evidenceProcessing:retryOwnEvidenceProcessing', { submissionId: unavailable.submissionId, itemId: unavailable.items[0].itemId });
    }
    await assert.rejects(run('evidenceProcessing:retryOwnEvidenceProcessing', { submissionId: unavailable.submissionId, itemId: unavailable.items[0].itemId }));
    await run('evidence:deleteEvidenceDraft', { submissionId: unavailable.submissionId });
    console.log('Real manual retry exhaustion passed');
  } finally {
    await run('users:deleteCurrentUser');
  }
  for (const table of tables) assert.deepEqual((await rows(table)).map(row => row._id).sort(), before[table]);
  console.log('Disposable rows removed; existing submissions, translations and users preserved');
}
verify().catch(error => { console.error('Convex verification failed:', error?.name === 'AssertionError' ? error.message : 'fixture or transport failure'); process.exitCode = 1; });
