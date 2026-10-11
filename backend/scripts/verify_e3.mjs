import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const backendDirectory = fileURLToPath(new URL('..', import.meta.url));
const execute = promisify(execFile);
async function cli(args) {
  const {stdout} = await execute('npx', ['convex', ...args, '--deployment', 'festive-cobra-664'], {timeout: 180000, maxBuffer: 2000000, cwd: backendDirectory});
  return stdout.trim() ? JSON.parse(stdout) : [];
}
const run = (name, args = {}) => cli(['run', name, JSON.stringify(args)]);
const tables = ['communitySubmissions','evidenceItems','evidenceExtractions','evidenceReviewJobs','evidenceReviewPasses','evidenceProvenance','evidenceLicenseAssessments','evidencePermissionGrants','evidencePublicationRevisions','translations','users'];
const rows = table => cli(['data', table, '--format', 'json', '--limit', '100']);
const before = Object.fromEntries(await Promise.all(tables.map(async table => [table, (await rows(table)).map(row=>row._id).sort()])));
// Start both opt-in native E3 tests after this line appears. Existing Clerk sessions are required.
await run('e3Verification:seed');
console.log('E3 synthetic fixture ready. Run the two opt-in native tests now.');
let completed = false;
try {
  const deadline = Date.now() + 480000;
  while (Date.now() < deadline) {
    const prepared = await run('e3Verification:prepareReady');
    if (prepared.prepared) console.log(`Prepared ${prepared.prepared} self-authored native evidence fixture(s)`);
    const readback = await run('e3Verification:readback');
    if (readback.submissions.some(row=>['rejected','review_unavailable','processing_failed','infected'].includes(row.status) || row.status==='held' && row.reviewPassCount > 0)) throw new Error('Actual processing or independent review did not pass; fixture remains private');
    if (readback.submissions.filter(row=>row.status==='approved').length >= 2) {
      assert.equal(readback.passes.length, 4);
      assert.ok(readback.passes.every(pass=>pass.confidence>0.95 && !pass.injection && pass.consistent));
      assert.equal(new Set(readback.passes.map(pass=>pass.modelVersion)).size, 2);
      console.log('Two native uploads → real private OCR → four independent model passes → two publication revisions passed');
      console.log(JSON.stringify({modelVersions:[...new Set(readback.passes.map(pass=>pass.modelVersion))], confidence:readback.passes.map(pass=>pass.confidence)}));
      completed = true;
      // Give native subscriptions time to read the materialized result before cleanup.
      await new Promise(resolve=>setTimeout(resolve,12000));
      break;
    }
    await new Promise(resolve=>setTimeout(resolve,1500));
  }
  assert.ok(completed,'Native E3 verification deadline exceeded');
} finally {
  await run('e3Verification:cleanup');
  for (const table of tables) assert.deepEqual((await rows(table)).map(row=>row._id).sort(), before[table], `${table}: existing rows changed`);
  console.log('Synthetic fixtures removed; existing users, evidence and translations preserved');
}
