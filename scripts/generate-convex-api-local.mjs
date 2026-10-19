#!/usr/bin/env node
// Generate only local API references. This deliberately never initializes the
// Convex CLI's credential/deployment context or calls a deployment.
import { readFile, writeFile, readdir } from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const requireBackend = createRequire(path.join(root, "backend/package.json"));
const sdk = path.dirname(requireBackend.resolve("convex/package.json"));
const loadSdk = relative => import(pathToFileURL(path.join(sdk, "dist/esm", relative)).href);
const [{ apiCodegen }, { compareModulePaths }] = await Promise.all([
  loadSdk("cli/codegen_templates/api.js"), loadSdk("cli/codegen_templates/common.js"),
]);
const prettier = requireBackend("prettier");
const functions = path.join(root, "backend/convex");
// Same file eligibility as this SDK's bundler entryPoints. Use only the pure
// template: the published CLI bundles its other internal dependencies.
const extensions = new Set([".js", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts", ".jsx"]);
async function entryPoints(directory, relative = "") {
  const entries = await readdir(directory, { withFileTypes: true });
  if (entries.some(entry => entry.name === "convex.config.ts")) throw new Error("Component codegen requires the official Convex CLI");
  const points = [];
  for (const entry of entries) {
    if (entry.name.startsWith(".") || entry.name.startsWith("#") || entry.name === "_generated") continue;
    const module = path.join(relative, entry.name);
    if (entry.name === "_deps") throw new Error("Reserved Convex _deps directory");
    if (entry.isDirectory()) { points.push(...await entryPoints(path.join(directory, entry.name), module)); continue; }
    if (!entry.isFile() || !extensions.has(path.extname(entry.name)) || (entry.name.match(/\./g) ?? []).length > 1 || module.includes(" ") || /^schema\.(ts|js)$/.test(entry.name)) continue;
    if (/\.tsx?$/.test(entry.name) && !/^\s{0,100}(import|export)/m.test(await readFile(path.join(directory, entry.name), "utf8"))) continue;
    points.push(module);
  }
  return points;
}
const contents = apiCodegen((await entryPoints(functions)).sort(compareModulePaths), { useTypeScript: false });
const check = process.argv.includes("--check");
for (const [name, source] of [["api.js", contents.JS], ["api.d.ts", contents.DTS]]) {
  if (typeof source !== "string") throw new Error(`Convex SDK did not generate ${name}`);
  const file = path.join(functions, "_generated", name);
  const formatted = await prettier.format(source, { parser: "typescript" });
  if (check) {
    if (await readFile(file, "utf8") !== formatted) throw new Error(`${name} is stale; run node scripts/generate-convex-api-local.mjs`);
  } else await writeFile(file, formatted);
}
console.log(check ? "Local Convex API references verified." : "Generated local Convex API references without deployment access.");
