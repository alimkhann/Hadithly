#!/usr/bin/env node
// Real Convex ZIP export/restore against an isolated, anonymous local backend.
import { mkdtemp, cp, writeFile, symlink, rm, readFile, lstat, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dir = await mkdtemp(join(tmpdir(), "hadithly-la3-drill-"));
const cli = join(root, "backend/node_modules/convex/bin/main.js");
const env = { PATH: process.env.PATH, HOME: process.env.HOME, CONVEX_AGENT_MODE: "anonymous", CONVEX_DISABLE_METRICS: "1" };
let server;
function run(args) {
  return new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, [cli, ...args], { cwd: dir, env });
    let stdout = "", stderr = "";
    child.stdout.on("data", data => { stdout += data; }); child.stderr.on("data", data => { stderr += data; });
    child.on("exit", code => code === 0 ? resolveResult(stdout.trim()) : reject(new Error(`Local Convex ${args[0]} failed: ${stderr.slice(-2500)}`)));
  });
}
try {
  const legacy = join(process.env.HOME, ".convex/anonymous-convex-backend-state/anonymous-agent");
  const existingLegacy = await lstat(legacy).catch(error => { if (error.code === "ENOENT") return null; throw error; });
  if (existingLegacy) throw new Error("Refusing drill: an unrelated legacy anonymous-agent deployment exists. No data was changed.");
  await cp(join(root, "backend/convex"), join(dir, "convex"), { recursive: true, filter: path => !path.endsWith("auth.config.ts") && !path.endsWith("crons.ts") });
  await symlink(join(root, "backend/node_modules"), join(dir, "node_modules"));
  await writeFile(join(dir, "package.json"), JSON.stringify({ private: true, type: "module", dependencies: { convex: "1.46.0" } }));
  await writeFile(join(dir, "convex.json"), JSON.stringify({ aiFiles: { enabled: false } }));
  await writeFile(join(dir, "convex/crons.ts"), 'import { cronJobs } from "convex/server"; export default cronJobs();\n');
  await writeFile(join(dir, "convex/recoveryFixture.ts"), `
import { internalMutation, internalQuery, internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
export const seed = internalMutation({ args: {}, handler: async ctx => {
  const userId = await ctx.db.insert("users", { clerkId: "synthetic-la3", email: "fixture@example.invalid", preferredLanguage: "en", subscriptionTier: "free", createdAt: 1, updatedAt: 1 });
  const hadithId = await ctx.db.insert("hadiths", { provider: "local_dump", providerHadithId: "1", collectionSlug: "synthetic", arabicText: "Synthetic fixture", referenceDisplay: "Synthetic 1", collectionName: "Synthetic", createdAt: 1 });
  const folderId = await ctx.db.insert("savedFolders", { userId, name: "Synthetic folder", normalizedName: "synthetic folder", createdAt: 1, updatedAt: 1 });
  await ctx.db.insert("savedItems", { userId, hadithId, folderId, bookmarkCreatedAt: 1, noteContent: "Synthetic note", createdAt: 1, updatedAt: 1 });
  await ctx.db.insert("readingProgress", { userId, hadithId, collectionSlug: "synthetic", scrollOffset: 42, updatedAt: 1 });
} });
export const seedFile = internalAction({ args: {}, handler: async ctx => {
  await ctx.runMutation(internal.recoveryFixture.seed, {});
  return ctx.storage.store(new Blob(["Synthetic LA3 storage fixture"], { type: "text/plain" }));
} });
export const snapshot = internalQuery({ args: {}, handler: async ctx => {
  const users = await ctx.db.query("users").collect(), hadiths = await ctx.db.query("hadiths").collect(), folders = await ctx.db.query("savedFolders").collect(), saved = await ctx.db.query("savedItems").collect(), progress = await ctx.db.query("readingProgress").collect();
  const files = await ctx.db.system.query("_storage").collect();
  return { users, hadiths, folders, saved, progress, files };
} });
export const wipe = internalMutation({ args: {}, handler: async ctx => {
  for (const table of ["savedItems", "savedFolders", "readingProgress", "hadiths", "users"] as const)
    for (const row of await ctx.db.query(table).collect()) await ctx.db.delete(row._id);
  for (const file of await ctx.db.system.query("_storage").collect()) await ctx.storage.delete(file._id);
} });
export const fileUrl = internalQuery({ args: {}, handler: async ctx => {
  const file = await ctx.db.system.query("_storage").first();
  return file ? ctx.storage.getUrl(file._id) : null;
} });
`);
  let readyOutput = "";
  server = spawn(process.execPath, [cli, "dev", "--typecheck", "disable", "--tail-logs", "disable"], { cwd: dir, env });
  const ready = new Promise((resolveReady, reject) => {
    const timer = setTimeout(() => reject(new Error("Isolated local backend did not start in three minutes")), 180_000);
    const observe = data => { readyOutput += data; if (/Convex functions ready/.test(readyOutput)) { clearTimeout(timer); resolveReady(); } };
    server.stdout.on("data", observe); server.stderr.on("data", observe);
    server.on("exit", code => { clearTimeout(timer); reject(new Error(`Local backend stopped (${code}): ${readyOutput.slice(-1800)}`)); });
  });
  await ready;
  const localState = join(dir, ".convex/local/default");
  const actualState = await realpath(localState), actualDir = await realpath(dir);
  if (!actualState.startsWith(actualDir + "/")) throw new Error("Local deployment state must be inside the new temporary project");
  const config = JSON.parse(await readFile(join(localState, "config.json"), "utf8"));
  if (config.deploymentName !== "anonymous-agent" || config.cloudProjectId !== undefined || !Number.isSafeInteger(config.ports?.cloud))
    throw new Error("Refusing drill: expected a project-local anonymous backend");
  const start = Date.now();
  await run(["run", "recoveryFixture:seedFile", "{}"]);
  const before = JSON.parse(await run(["run", "recoveryFixture:snapshot", "{}"]));
  if (Object.values(before).some(rows => rows.length !== 1)) throw new Error("Synthetic seed does not match fixture");
  await run(["export", "--include-file-storage", "--path", join(dir, "snapshot.zip")]);
  const zip = await readFile(join(dir, "snapshot.zip"));
  await run(["run", "recoveryFixture:wipe", "{}"]);
  const empty = JSON.parse(await run(["run", "recoveryFixture:snapshot", "{}"]));
  if (Object.values(empty).some(rows => rows.length !== 0)) throw new Error("Wipe did not remove synthetic fixtures");
  const restoreStart = Date.now();
  await run(["import", "--replace-all", "--yes", join(dir, "snapshot.zip")]);
  const after = JSON.parse(await run(["run", "recoveryFixture:snapshot", "{}"]));
  if (JSON.stringify(before) !== JSON.stringify(after)) throw new Error("Restored documents, IDs, relationships or storage checksums differ");
  const url = JSON.parse(await run(["run", "recoveryFixture:fileUrl", "{}"]));
  if (typeof url !== "string" || new URL(url).hostname !== "127.0.0.1") throw new Error("Restore URL must be local");
  const stored = await fetch(url, { signal: AbortSignal.timeout(5000) });
  if (!stored.ok || await stored.text() !== "Synthetic LA3 storage fixture") throw new Error("Restored file bytes differ");
  const evidence = { recordedAt: new Date().toISOString(), scope: "isolated anonymous local Convex, current Hadithly schema, synthetic data only",
    tables: ["users", "hadiths", "savedFolders", "savedItems", "readingProgress"], documents: 5, storageFiles: 1,
    snapshotBytes: zip.length, snapshotSha256: createHash("sha256").update(zip).digest("hex"),
    exactRestoredDocumentsAndStorageMetadata: true, restoredFileBytesVerified: true, restoreMs: Date.now() - restoreStart, drillMs: Date.now() - start,
    productionRestoreTested: false, configSecretsSchedulesIncluded: false };
  await writeFile(join(root, "docs/LA3_RECOVERY_EVIDENCE.json"), JSON.stringify(evidence, null, 2) + "\n");
  process.stdout.write(JSON.stringify(evidence, null, 2) + "\n");
} finally {
  if (server && server.exitCode === null) {
    server.kill("SIGINT");
    await new Promise(done => { server.once("exit", done); setTimeout(done, 5000); });
    if (server.exitCode === null) server.kill("SIGKILL");
  }
  await rm(dir, { recursive: true, force: true });
}
