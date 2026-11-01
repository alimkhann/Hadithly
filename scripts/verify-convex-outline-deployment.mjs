#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFile } from "node:child_process";
import { isDeepStrictEqual, promisify } from "node:util";
import { parseArgs } from "node:util";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const { getDocumentSize, jsonToConvex } = createRequire(resolve(root, "backend/package.json"))("convex/values");
const execute = promisify(execFile);
const { values } = parseArgs({ options: { mode: { type: "string" }, deployment: { type: "string" },
  baseline: { type: "string" }, output: { type: "string" } } });
assert.equal(values.deployment, "festive-cobra-664", "This approved rollout targets development only");
assert.ok(["baseline", "convert"].includes(values.mode));
assert.ok(values.baseline && values.output);
const baselinePath = resolve(values.baseline);
try {
  await access(resolve(values.output));
  throw new Error("Choose a new evidence output path");
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
const baselineRelative = relative(root, baselinePath);
assert.ok(baselineRelative.startsWith("../") || isAbsolute(baselineRelative), "Private baseline must stay outside git");
const slugs = ["ibn-majah", "bukhari", "muslim", "tirmidhi", "sunan-nasai", "abu-dawood", "mishkat-al-masabih"];
const cli = resolve(root, "backend/node_modules/convex/bin/main.js");
const stamp = () => new Date().toISOString();
const canonical = value => Array.isArray(value) ? value.map(canonical) :
  value !== null && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const digest = value => createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");
async function run(args) {
  try {
    const { stdout } = await execute(process.execPath, [cli, "run", "--deployment", values.deployment,
      "--codegen", "disable", ...args], { cwd: resolve(root, "backend"), timeout: 45000, maxBuffer: 16 * 1024 * 1024 });
    return JSON.parse(stdout);
  } catch { throw new Error("Development outline command failed; raw response withheld"); }
}
const query = slug => run(["collections:getOutline", JSON.stringify({ collectionSlug: slug })]);
const stored = () => run(["--inline-query", 'return await ctx.db.query("collectionOutlines").take(8);']);
async function save(output) {
  await writeFile(resolve(values.output), JSON.stringify(output, null, 2) + "\n", { flag: "wx" });
}
if (values.mode === "baseline") {
  const startedAtUtc = stamp();
  const rows = await stored();
  assert.equal(rows.length, 7);
  assert.deepEqual(rows.map(row => row.collectionSlug).sort(), [...slugs].sort());
  assert.ok(rows.every(row => !row.packedVolumes), "Baseline must precede conversion");
  const outlines = [];
  for (const slug of slugs) {
    const publicDocument = await query(slug);
    const storedDocument = rows.find(row => row.collectionSlug === slug);
    assert.ok(isDeepStrictEqual(publicDocument, storedDocument), "Public baseline differs from stored outline; raw content withheld");
    outlines.push({ slug, publicDocument, storedDocumentBytes: getDocumentSize(jsonToConvex(storedDocument)) });
  }
  const baseline = { deployment: values.deployment, startedAtUtc, completedAtUtc: stamp(), outlines };
  await writeFile(baselinePath, JSON.stringify(baseline), { flag: "wx", mode: 0o600 });
  await save({ deployment: values.deployment, scope: "read-only live public outline baseline", startedAtUtc,
    completedAtUtc: baseline.completedAtUtc, outlines: outlines.map(row => ({ collectionSlug: row.slug,
      storedDocumentBytes: row.storedDocumentBytes, publicPayloadSha256: digest(row.publicDocument) })) });
  process.stdout.write("Captured seven private live public outlines; no user records or provider calls\n");
} else {
  const baseline = JSON.parse(await readFile(baselinePath, "utf8"));
  assert.equal(baseline.deployment, values.deployment);
  assert.deepEqual(baseline.outlines.map(row => row.slug), slugs);
  const evidence = { deployment: values.deployment, scope: "approved live outline conversion and full public response readback",
    startedAtUtc: stamp(), completedAtUtc: null, allPublicPayloadsIdentical: false, results: [] };
  // Check every response before any mutation, so an outdated baseline stops the rollout.
  for (const row of baseline.outlines) assert.ok(isDeepStrictEqual(await query(row.slug), row.publicDocument), "Live outline changed since baseline; raw content withheld");
  for (const row of baseline.outlines) {
    const args = JSON.stringify({ collectionSlug: row.slug, format: "packed" });
    assert.deepEqual(await run(["migrations:rewriteCollectionOutlineStorage", args]), { status: "packed" });
    assert.deepEqual(await run(["migrations:rewriteCollectionOutlineStorage", args]), { status: "already_packed" });
    const queryStartedAtUtc = stamp();
    const result = await query(row.slug);
    const repeated = await query(row.slug);
    const queryCompletedAtUtc = stamp();
    assert.ok(isDeepStrictEqual(result, row.publicDocument), "Converted public response differs; raw content withheld");
    assert.ok(isDeepStrictEqual(repeated, row.publicDocument), "Repeated public response differs; raw content withheld");
    evidence.results.push({ collectionSlug: row.slug, publicPayloadSha256: digest(result),
      publicPayloadIdentical: true, identityAndFreshnessIdentical: true, conversionIdempotent: true,
      queryStartedAtUtc, queryCompletedAtUtc, legacyStoredDocumentBytes: row.storedDocumentBytes });
    // Keep verified partial progress reviewable if a later collection fails.
    await writeFile(resolve(values.output), JSON.stringify(evidence, null, 2) + "\n");
    process.stdout.write(row.slug + ": converted; exact public response and retry verified\n");
  }
  const rows = await stored();
  assert.equal(rows.length, 7);
  for (const result of evidence.results) {
    const row = rows.find(row => row.collectionSlug === result.collectionSlug);
    assert.equal(row.packedVolumes.format, "gzip-convex-json-v1");
    result.packedStoredDocumentBytes = getDocumentSize(jsonToConvex(row));
    assert.ok(result.packedStoredDocumentBytes < result.legacyStoredDocumentBytes);
  }
  evidence.completedAtUtc = stamp();
  evidence.allPublicPayloadsIdentical = true;
  await writeFile(resolve(values.output), JSON.stringify(evidence, null, 2) + "\n");
}
