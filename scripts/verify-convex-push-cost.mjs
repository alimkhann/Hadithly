#!/usr/bin/env node
import { mkdtemp, cp, writeFile, symlink, rm, readFile, lstat, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { parseArgs } from "node:util";
import assert from "node:assert/strict";

const { values } = parseArgs({ options: {
  "baseline-ref": { type: "string" }, output: { type: "string" },
} });
if (!values["baseline-ref"] || !values.output) {
  throw new Error("Pass --baseline-ref and --output explicitly");
}
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dir = await mkdtemp(join(tmpdir(), "hadithly-push-cost-"));
const cli = join(root, "backend/node_modules/convex/bin/main.js");
const env = { PATH: process.env.PATH, HOME: process.env.HOME,
  CONVEX_AGENT_MODE: "anonymous", CONVEX_DISABLE_METRICS: "1", DISABLE_BEACON: "1" };
const changed = ["library.ts", "actions/daily.ts", "lib/notifyContent.ts"];
let server;
const commands = new Set();
let cleanupPromise;
let interrupted = false;
function execute(command, args, options = {}) {
  return new Promise((done, reject) => {
    const child = spawn(command, args, { cwd: dir, env, ...options, detached: true, stdio: ["ignore", "pipe", "pipe"] });
    commands.add(child);
    const timer = setTimeout(() => {
      try { process.kill(-child.pid, "SIGKILL"); } catch (error) { if (error.code !== "ESRCH") reject(error); }
    }, 60000);
    let stdout = "";
    child.stdout.on("data", data => { stdout += data; });
    child.stderr.resume();
    child.on("error", error => { commands.delete(child); clearTimeout(timer); reject(error); });
    child.on("exit", code => {
      commands.delete(child);
      clearTimeout(timer);
      code === 0 ? done(stdout.trim()) : reject(new Error(`Local command failed (${code}); raw output withheld`));
    });
  });
}
const run = args => execute(process.execPath, [cli, ...args]);
async function startServer() {
  server = spawn(process.execPath, [cli, "dev", "--typecheck", "disable", "--tail-logs", "disable"], { cwd: dir, env, detached: true });
  await new Promise((done, reject) => {
    let output = "";
    const timer = setTimeout(() => reject(new Error("Anonymous local backend startup timed out; raw output withheld")), 180000);
    const observe = data => {
      output += data;
      if (/Convex functions ready/.test(output)) { clearTimeout(timer); done(); }
    };
    server.stdout.on("data", observe); server.stderr.on("data", observe);
    server.on("error", error => { clearTimeout(timer); reject(error); });
    server.on("exit", code => { clearTimeout(timer); reject(new Error(`Local backend stopped (${code}); raw output withheld`)); });
  });
}
async function stopServer() {
  if (!server?.pid) return;
  const groupExists = () => {
    try { process.kill(-server.pid, 0); return true; }
    catch (error) { if (error.code === "ESRCH") return false; throw error; }
  };
  if (!groupExists()) return;
  process.kill(-server.pid, "SIGINT");
  const deadline = Date.now() + 5000;
  while (groupExists() && Date.now() < deadline) await new Promise(done => setTimeout(done, 50));
  if (groupExists()) process.kill(-server.pid, "SIGKILL");
  const killDeadline = Date.now() + 2000;
  while (groupExists() && Date.now() < killDeadline) await new Promise(done => setTimeout(done, 50));
  if (groupExists()) throw new Error("Owned local backend process group did not stop; retaining temporary state");
}
function cleanup() {
  cleanupPromise ??= (async () => {
    for (const child of commands) {
      try { process.kill(-child.pid, "SIGKILL"); }
      catch (error) { if (error.code !== "ESRCH") throw error; }
    }
    await stopServer();
    await rm(dir, { recursive: true, force: true });
  })();
  return cleanupPromise;
}
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, async () => {
    if (interrupted) return;
    interrupted = true;
    try { await cleanup(); }
    catch { process.stderr.write("Local process cleanup failed; temporary state retained\n"); process.exit(1); }
    process.exit(signal === "SIGINT" ? 130 : 143);
  });
}
const fixture = `
import { internalMutation } from "./_generated/server";
import { v } from "convex/values";
const NOW = Date.parse("2026-09-18T03:05:00Z");
export const seed = internalMutation({ args: { scenario: v.string() }, handler: async (ctx, { scenario }) => {
  for (const table of ["pushTokens", "dailySelections", "hadiths", "users"])
    for (const row of await ctx.db.query(table).collect()) await ctx.db.delete(row._id);
  if (scenario === "empty") return;
  const userId = await ctx.db.insert("users", { clerkId: "fixture-push-cost", preferredLanguage: "en",
    subscriptionTier: "free", aiGenerationsThisMonth: 0, aiGenerationLimit: 5, createdAt: 1, updatedAt: 1 });
  const hadithId = await ctx.db.insert("hadiths", { provider: "sunnah_now", canonicalId: "sunnah_now:bukhari:57",
    providerHadithId: "57", collectionSlug: "bukhari", collectionName: "Sahih al-Bukhari", volumeId: "2",
    arabicText: "Synthetic local fixture", englishText: "Synthetic local English text.", referenceDisplay: "Fixture 57",
    authenticity: { kind: "collection_scope", normalizedGrade: "sahih", claimScope: "collection",
      sourceLabel: "Documented Sahih collection", sourceName: "Sunnah.com", sourceUrl: "https://sunnah.com/bukhari/about",
      verificationMethod: "manual_collection_mapping" }, createdAt: 1000 });
  await ctx.db.insert("dailySelections", { localDate: "2026-09-18", timezone: "Asia/Almaty", hadithId, createdAt: NOW });
  const count = scenario === "sparse" ? 205 : scenario === "cap" ? 501 : 201;
  for (let i = 0; i < count; i++) {
    const due = scenario === "stale" && i === 200 || scenario === "permanent" || scenario === "cap";
    const dailyTime = due ? "08:00" : scenario === "invalid-page" && i < 200 ? "00:07" :
      scenario === "invalid-page" ? "08:00" : i % 2 === 0 || scenario === "stale" ? "00:00" : "23:45";
    await ctx.db.insert("pushTokens", { userId, token: "fixture-" + i, platform: "android", dailyTime,
      deliveryBucket: dailyTime, timezone: "Asia/Almaty", enabled: true, updatedAt: NOW,
      lastSeenAt: scenario === "stale" && !due ? NOW - 31 * 86400000 : NOW });
  }
} });
`;
const measureFixture = `
"use node";
import { internalAction } from "../_generated/server";
import { getFunctionName } from "convex/server";
import { runDuePushes } from "./daily";
import { createHash } from "node:crypto";
const NOW = Date.parse("2026-09-18T03:05:00Z");
import { v } from "convex/values";
export const measure = internalAction({ args: { permanent: v.boolean() }, handler: async (ctx, args) => {
  let tokenQueries = 0, tokenRows = 0, sends = 0;
  const deliveryHash = createHash("sha256");
  const io = { runQuery: async (...args) => {
    const result = await ctx.runQuery(...args);
    const name = getFunctionName(args[0]);
    if (["library:listBucketPage", "library:listPushDeliveryPage"].includes(name)) {
      tokenQueries++; tokenRows += result.rows.length;
    }
    return result;
  }, runMutation: (...args) => ctx.runMutation(...args),
    runAction: () => { throw new Error("Provider generation is disabled in this fixture"); } };
  const send = async (token, payload) => {
    if (!token.startsWith("fixture-")) throw new Error("Non-fixture token");
    sends++;
    deliveryHash.update(JSON.stringify([token, payload.body ?? payload.alert?.body]));
    if (args.permanent) throw new Error("FCM rejected push (404): unregistered");
  };
  const result = await runDuePushes(io, NOW, { sendApns: send, sendFcm: send }, { hasApns: true, hasFcm: true });
  return { tokenQueries, tokenRows, sends, deliveryDigest: deliveryHash.digest("hex"), result };
} });
`;
try {
  const legacy = join(process.env.HOME, ".convex/anonymous-convex-backend-state/anonymous-agent");
  if (await lstat(legacy).catch(error => { if (error.code === "ENOENT") return null; throw error; }))
    throw new Error("Unrelated legacy anonymous deployment exists; refusing to reuse it");
  await cp(join(root, "backend/convex"), join(dir, "convex"), { recursive: true,
    filter: path => !path.endsWith("auth.config.ts") && !path.endsWith("crons.ts") && !path.endsWith(".test.ts") });
  await symlink(join(root, "backend/node_modules"), join(dir, "node_modules"));
  const pkg = JSON.parse(await readFile(join(root, "backend/node_modules/convex/package.json"), "utf8"));
  await writeFile(join(dir, "package.json"), JSON.stringify({ private: true, type: "module", dependencies: { convex: pkg.version } }));
  await writeFile(join(dir, "convex.json"), JSON.stringify({ aiFiles: { enabled: false } }));
  await writeFile(join(dir, "convex/crons.ts"), 'import { cronJobs } from "convex/server"; export default cronJobs();\n');
  await writeFile(join(dir, "convex/pushCostFixture.js"), fixture);
  await writeFile(join(dir, "convex/actions/pushCostMeasure.js"), measureFixture);
  for (const file of changed) {
    const original = await execute("git", ["show", values["baseline-ref"] + ":backend/convex/" + file], { cwd: root });
    await writeFile(join(dir, "convex", file), original + "\n");
  }
  await startServer();
  const state = join(dir, ".convex/local/default");
  assert.ok((await realpath(state)).startsWith(await realpath(dir) + "/"));
  const config = JSON.parse(await readFile(join(state, "config.json"), "utf8"));
  assert.equal(config.deploymentName, "anonymous-agent");
  assert.equal(config.cloudProjectId, undefined);
  assert.ok(Number.isSafeInteger(config.ports?.cloud));
  const measurements = {};
  for (const phase of ["before", "after"]) {
    if (phase === "after") {
      await stopServer();
      for (const file of changed) await cp(join(root, "backend/convex", file), join(dir, "convex", file));
      await startServer();
    }
    measurements[phase] = {};
    for (const scenario of ["empty", "sparse", "stale", "permanent", "cap", "invalid-page"]) {
      await run(["run", "--codegen", "disable", "pushCostFixture:seed", JSON.stringify({ scenario })]);
      const result = JSON.parse(await run(["run", "--codegen", "disable", "actions/pushCostMeasure:measure", JSON.stringify({ permanent: scenario === "permanent" })]));
      assert.equal(result.sends, scenario === "stale" || scenario === "invalid-page" ? 1 : scenario === "permanent" ? 201 : scenario === "cap" ? 500 : 0);
      assert.equal(result.result.failed, scenario === "permanent" ? 201 : 0);
      assert.equal(result.result.removedStale, scenario === "stale" ? 200 : scenario === "permanent" ? 201 : 0);
      assert.equal(result.tokenRows, scenario === "empty" ? 0 : scenario === "sparse" ? 205 : scenario === "cap" ? 501 : scenario === "invalid-page" ? 1 : 201);
      measurements[phase][scenario] = result;
      if (phase === "after") {
        assert.deepEqual(result.result, measurements.before[scenario].result);
        assert.equal(result.deliveryDigest, measurements.before[scenario].deliveryDigest);
      }
      process.stdout.write(phase + " " + scenario + ": " + result.tokenQueries + " token queries\n");
    }
  }
  assert.equal(measurements.before.empty.tokenQueries, 96);
  assert.equal(measurements.after.empty.tokenQueries, 1);
  assert.equal(measurements.after.sparse.tokenQueries, 2);
  assert.equal(measurements.after.stale.tokenQueries, 2);
  assert.equal(measurements.after.permanent.tokenQueries, 2);
  assert.equal(measurements.after.cap.tokenQueries, 3);
  assert.equal(measurements.after["invalid-page"].tokenQueries, 2);
  const evidence = { capturedAtUtc: new Date().toISOString(), baselineRef: values["baseline-ref"],
    scope: "real isolated anonymous local Convex, synthetic data, record-only senders, no provider calls",
    billedUsageMeasured: false, nativeJourneyMeasured: false, cloudDeployed: false,
    convexVersion: pkg.version, measurements };
  await writeFile(resolve(root, values.output), JSON.stringify(evidence, null, 2) + "\n");
} finally {
  await cleanup();
}
