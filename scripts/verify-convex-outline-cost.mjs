#!/usr/bin/env node
import { mkdtemp, cp, writeFile, symlink, rm, readFile, lstat, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { parseArgs } from "node:util";
import assert from "node:assert/strict";

const { values } = parseArgs({ options: {
  snapshot: { type: "string" }, output: { type: "string" },
} });
if (!values.snapshot || !values.output) {
  throw new Error("Pass --snapshot and --output explicitly");
}
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dir = await mkdtemp(join(tmpdir(), "hadithly-outline-cost-"));
const cli = join(root, "backend/node_modules/convex/bin/main.js");
const env = { PATH: process.env.PATH, HOME: process.env.HOME,
  CONVEX_AGENT_MODE: "anonymous", CONVEX_DISABLE_METRICS: "1", DISABLE_BEACON: "1" };
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
async function executionLogs() {
  return await new Promise((done, reject) => {
    const child = spawn(process.execPath, [cli, "logs", "--history", "2000", "--jsonl"], {
      cwd: dir, env, detached: true, stdio: ["ignore", "pipe", "ignore"],
    });
    commands.add(child);
    let output = "";
    child.stdout.on("data", data => { output += data; });
    const stop = signal => { try { process.kill(-child.pid, signal); } catch (error) { if (error.code !== "ESRCH") reject(error); } };
    const timer = setTimeout(() => stop("SIGTERM"), 3000);
    const deadline = setTimeout(() => stop("SIGKILL"), 8000);
    child.on("error", error => { commands.delete(child); clearTimeout(timer); clearTimeout(deadline); reject(error); });
    child.on("exit", () => {
      commands.delete(child); clearTimeout(timer); clearTimeout(deadline);
      done(output.split("\n").flatMap(line => {
        try { const event = JSON.parse(line); return event.kind === "Completion" ? [event] : []; }
        catch { return []; }
      }));
    });
  });
}
const fixture = `
import { internalMutation, internalQuery } from "./_generated/server";
import { getDocumentSize, v } from "convex/values";
import snapshots from "./outlineCostSnapshot.json";
export const seed = internalMutation({ args: {}, handler: async ctx => {
  for (const row of snapshots) {
    await ctx.db.insert("collectionOutlines", row);
    await ctx.db.insert("collectionCounts", { collectionSlug: row.collectionSlug, indexedAt: row.indexedAt,
      totalHadiths: row.volumes.reduce((total, volume) => total + volume.hadithCount, 0) });
  }
} });
export const size = internalQuery({ args: { collectionSlug: v.string() }, handler: async (ctx, args) => {
  const row = await ctx.db.query("collectionOutlines").withIndex("by_collection_slug", q => q.eq("collectionSlug", args.collectionSlug)).unique();
  if (!row) throw new Error("Missing local fixture");
  return { storedDocumentBytes: getDocumentSize(row), packed: "packedVolumes" in row };
} });
`;
const digest = object => createHash("sha256").update(JSON.stringify(object)).digest("hex");
try {
  const snapshot = JSON.parse(await readFile(resolve(values.snapshot), "utf8"));
  assert.equal(snapshot.length, 7, "Expected the seven public cached collection outlines");
  assert.equal(new Set(snapshot.map(row => row.collectionSlug)).size, 7);
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
  await writeFile(join(dir, "convex/outlineCostSnapshot.json"), JSON.stringify(snapshot));
  await writeFile(join(dir, "convex/outlineCostFixture.js"), fixture);
  await startServer();
  const state = join(dir, ".convex/local/default");
  assert.ok((await realpath(state)).startsWith(await realpath(dir) + "/"));
  const config = JSON.parse(await readFile(join(state, "config.json"), "utf8"));
  assert.equal(config.deploymentName, "anonymous-agent");
  assert.equal(config.cloudProjectId, undefined);
  await run(["run", "--codegen", "disable", "outlineCostFixture:seed", "{}"]);
  const results = [];
  for (const row of snapshot) {
    const args = JSON.stringify({ collectionSlug: row.collectionSlug });
    const rewrites = format => run(["run", "--codegen", "disable", "migrations:rewriteCollectionOutlineStorage",
      JSON.stringify({ collectionSlug: row.collectionSlug, format })]).then(JSON.parse);
    const before = {};
    let publicDocument;
    for (const format of ["legacy", "packed"]) {
      if (format === "packed") {
        assert.deepEqual(await rewrites("packed"), { status: "packed" });
        assert.deepEqual(await rewrites("packed"), { status: "already_packed" });
      }
      const startedAt = Date.now() / 1000;
      const cold = JSON.parse(await run(["run", "--codegen", "disable", "collections:getOutline", args]));
      const warm = JSON.parse(await run(["run", "--codegen", "disable", "collections:getOutline", args]));
      assert.deepEqual(warm, cold);
      if (format === "legacy") publicDocument = cold;
      else assert.deepEqual(cold, publicDocument);
      const events = (await executionLogs()).filter(event => event.identifier === "collections:getOutline" && event.timestamp >= startedAt);
      assert.equal(events.length, 2, "Expected exactly two correlated local outline query completions");
      assert.equal(events[0].cachedResult, false, "The first read must be uncached");
      assert.equal(events[1].cachedResult, true, "The repeat read must be cached");
      assert.ok(events.every(event => !event.error), "Query completion failed");
      const size = JSON.parse(await run(["run", "--codegen", "disable", "outlineCostFixture:size", args]));
      before[format] = { ...size, coldDatabaseIoReadBytes: events[0].usageStats.databaseIoReadBytes,
        warmDatabaseIoReadBytes: events[1].usageStats.databaseIoReadBytes,
        coldDatabaseReadDocuments: events[0].usageStats.databaseReadDocuments,
        coldQueryExecutionSeconds: events[0].executionTime, publicPayloadSha256: digest(cold) };
    }
    assert.ok(before.packed.coldDatabaseIoReadBytes < before.legacy.coldDatabaseIoReadBytes);
    assert.equal(before.packed.warmDatabaseIoReadBytes, 0);
    assert.deepEqual(await rewrites("legacy"), { status: "legacy" });
    assert.deepEqual(await rewrites("legacy"), { status: "already_legacy" });
    const restored = JSON.parse(await run(["run", "--codegen", "disable", "collections:getOutline", args]));
    assert.deepEqual(restored, publicDocument);
    results.push({ collectionSlug: row.collectionSlug, volumeCount: row.volumes.length,
      chapterCount: row.volumes.reduce((total, volume) => total + (volume.chapters?.length ?? 0), 0),
      ...before, conversionIdempotent: true, rollbackIdentical: true });
    process.stdout.write(row.collectionSlug + ": " + before.legacy.coldDatabaseIoReadBytes + " -> " + before.packed.coldDatabaseIoReadBytes + " local DB read bytes\n");
  }
  const evidence = { capturedAtUtc: new Date().toISOString(), scope: "real isolated anonymous local Convex using a private snapshot of public cached outlines",
    snapshotSha256: digest(snapshot), cloudDeployed: false, providerCallsInvoked: false,
    publicPayloadsIdentical: true, nativeJourneyMeasured: false, billedUsageMeasured: false,
    convexVersion: pkg.version, results };
  await writeFile(resolve(root, values.output), JSON.stringify(evidence, null, 2) + "\n");
} finally { await cleanup(); }
