import { execFile } from "node:child_process";
import { promisify } from "node:util";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
const execute = promisify(execFile);
const cwd = fileURLToPath(new URL("..", import.meta.url));
async function cli(args) {
  const { stdout } = await execute("npx", ["convex", ...args, "--deployment", "festive-cobra-664"], { cwd, timeout: 180_000, maxBuffer: 2_000_000 });
  return stdout.trim() ? JSON.parse(stdout) : [];
}
const run = (name, args = {}) => cli(["run", name, JSON.stringify(args)]);
const rows = table => cli(["data", table, "--format", "json", "--limit", "100"]);
const tables = ["communitySubmissions", "evidenceItems", "evidenceExtractions", "evidenceReviewJobs", "evidenceReviewPasses", "evidenceProvenance", "evidenceLicenseAssessments", "evidencePermissionGrants", "evidencePublicationRevisions", "evidenceAppeals", "evidenceCases", "evidenceReviewSpendEvents", "translationReports", "translations", "users"];
async function verify() {
const before = await run("e4Verification:baseline");
let completed = false;
try {
  await run("e3Verification:seed");
  await run("evidenceReview:dispatch");
  process.stdout.write("E4 synthetic fixtures ready. Run the two opt-in native integration tests now.\n");
  const deadline = Date.now() + 720_000;
  while (Date.now() < deadline) {
    await run("e3Verification:prepareReady");
    await run("e4Verification:prepareAppeals");
    const states = await run("e4Verification:readback");
    if (states.length >= 2 && states.every(row => row.status === "approved" && row.appeal === "published" && row.reportResolved && row.passes >= 6)) {
      completed = true;
      process.stdout.write(JSON.stringify({ acceptedPasses: states.reduce((sum,row)=>sum+row.passes,0), attemptedPasses: states.reduce((sum,row)=>sum+row.attemptedPasses,0) })+"\n");
      process.stdout.write("Two native JWT uploads, real OCR, automatic report rechecks, revoked-publication readback, and automatic appeals passed. Accepted independent review passes are recorded above.\n");
      await new Promise(resolve => setTimeout(resolve, 12_000));
      break;
    }
    await new Promise(resolve => setTimeout(resolve, 1500));
  }
  assert.ok(completed, "E4 native integration deadline exceeded");
} finally {
  await run("e3Verification:cleanup");
  for (const table of tables) assert.deepEqual((await rows(table)).map(row => row._id).sort(), before[table], `${table}: existing IDs changed`);
  process.stdout.write("Disposable fixtures removed; existing user, evidence, translation and case IDs preserved. Only detached audit facts, daily admission counters, and anonymous global spend events remain.\n");
}

}
verify().catch(() => { process.stderr.write("E4 live verification failed; inspect the coarse native result and fixture state.\n"); process.exitCode = 1; });
