import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
const execute = promisify(execFile);
const deployment = 'festive-cobra-664';
async function cli(args) {
  const { stdout } = await execute('npx', ['convex', ...args, '--deployment', deployment], { timeout: 120000, maxBuffer: 8000000 });
  return JSON.parse(stdout);
}
async function rows(table) { return cli(['data', table, '--format', 'json', '--limit', '500']); }
async function run(name, args = {}) { return cli(['run', name, JSON.stringify(args)]); }
async function rollout() {
  const users = await rows('users');
  const protectedTables = ['savedItems', 'savedFolders', 'readingProgress', 'translations'];
  const before = Object.fromEntries(await Promise.all(protectedTables.map(async table => [table, await rows(table)])));
  let cursor = null, erased = 0;
  do {
    const page = await run('migrations:migrateQ1Users', { paginationOpts: { cursor, numItems: 25 } });
    erased += page.erased;
    if (page.isDone) break;
    cursor = page.continueCursor;
  } while (true);
  const after = await rows('users');
  assert.deepEqual(after.map(row => row._id).sort(), users.map(row => row._id).sort());
  for (const original of users) {
    const expected = { ...original }; delete expected.aiGenerationsThisMonth; delete expected.aiGenerationLimit;
    assert.deepEqual(after.find(row => row._id === original._id), expected);
  }
  const repeated = await run('migrations:migrateQ1Users', { paginationOpts: { cursor: null, numItems: 25 } });
  assert.equal(repeated.erased, 0);
  const counts = await run('migrations:materializeQ1CollectionCounts');
  assert.equal((await run('migrations:materializeQ1CollectionCounts')).written, 0);
  for (const table of protectedTables) assert.deepEqual(await rows(table), before[table]);
  const outlines = await rows('collectionOutlines'), compact = await rows('collectionCounts');
  for (const outline of outlines) assert.equal(compact.find(row => row.collectionSlug === outline.collectionSlug)?.totalHadiths,
    outline.volumes.reduce((sum, volume) => sum + volume.hadithCount, 0));
  const outlineBytes = Buffer.byteLength(JSON.stringify(outlines)), compactBytes = Buffer.byteLength(JSON.stringify(compact));
  console.log(JSON.stringify({ deployment, erasedMonthlyAggregates: erased, materializedCollections: counts.written,
    unchangedAccountEntitlements: true, preservedSavedProgressTranslations: true, repeatMigrationChangedZero: true,
    outlineBytes, compactBytes, compactReductionPercent: Math.round((1 - compactBytes / outlineBytes) * 10000) / 100 }));
}
rollout().catch(() => { console.error('Q1 migration or preservation check failed; no private data printed.'); process.exitCode = 1; });
