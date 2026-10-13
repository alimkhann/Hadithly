"use node";
import { reportFailure } from "../lib/reportFailure";

import { createHash } from "node:crypto";
import { JWT } from "google-auth-library";
import { v } from "convex/values";
import { internalAction } from "../_generated/server";
import { internal } from "../_generated/api";
import type { Id } from "../_generated/dataModel";

type Source = { kind: "html_chars"; start: number; end: number } |
  { kind: "page_box"; page: number; x: number; y: number; width: number; height: number };
type Result = { kind: "infected" } | { kind: "failed"; retryable: boolean } |
  { kind: "ready"; mime: string; sha256: string; finalUrl?: string; accessChain?: string[]; sourceBytesBase64?: string; text: string; spans: Array<{ start: number; end: number; source: Source }> };

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function finiteInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value);
}

function parseResult(value: unknown): Result {
  const row = record(value);
  if (!row) throw new Error("Invalid processor response");
  if (row.kind === "infected") return { kind: "infected" };
  if (row.kind === "failed" && typeof row.retryable === "boolean") return { kind: "failed", retryable: row.retryable };
  if (row.kind !== "ready" || typeof row.mime !== "string" || typeof row.sha256 !== "string" ||
      typeof row.text !== "string" || !Array.isArray(row.spans) || row.text.length > 100_000 || row.spans.length > 3_000) throw new Error("Invalid processor response");
  const spans: Array<{ start: number; end: number; source: Source }> = [];
  for (const entry of row.spans) {
    const parsed = record(entry);
    const source = record(parsed?.source);
    if (!parsed || !source || !finiteInteger(parsed.start) || !finiteInteger(parsed.end)) throw new Error("Invalid processor span");
    if (source.kind === "html_chars" && finiteInteger(source.start) && finiteInteger(source.end)) {
      spans.push({ start: parsed.start, end: parsed.end, source: { kind: "html_chars", start: source.start, end: source.end } });
    } else if (source.kind === "page_box" && finiteInteger(source.page) && finiteInteger(source.x) && finiteInteger(source.y) && finiteInteger(source.width) && finiteInteger(source.height)) {
      spans.push({ start: parsed.start, end: parsed.end, source: { kind: "page_box", page: source.page, x: source.x, y: source.y, width: source.width, height: source.height } });
    } else throw new Error("Invalid processor source");
  }
  if (row.finalUrl !== undefined && row.finalUrl !== null && typeof row.finalUrl !== "string") throw new Error("Invalid processor URL");
  if (row.sourceBytesBase64 !== undefined && (typeof row.sourceBytesBase64 !== "string" || row.sourceBytesBase64.length > 13_333_336 || !/^[A-Za-z0-9+/]*={0,2}$/.test(row.sourceBytesBase64))) throw new Error("Invalid source snapshot");
  if (row.accessChain !== undefined && (!Array.isArray(row.accessChain) || row.accessChain.length < 1 || row.accessChain.length > 4 || !row.accessChain.every((url): url is string => typeof url === "string" && url.length <= 2048))) throw new Error("Invalid access chain");
  return { kind: "ready", mime: row.mime, sha256: row.sha256, text: row.text, spans, ...(typeof row.finalUrl === "string" ? { finalUrl: row.finalUrl } : {}), ...(Array.isArray(row.accessChain) ? { accessChain: row.accessChain } : {}), ...(typeof row.sourceBytesBase64 === "string" ? { sourceBytesBase64: row.sourceBytesBase64 } : {}) };
}

function processorConfig(): { url: string; credentials: { client_email: string; private_key: string } } {
  const rawUrl = process.env.EVIDENCE_PROCESSOR_URL;
  const rawCredentials = process.env.EVIDENCE_PROCESSOR_GOOGLE_CREDENTIALS;
  if (!rawUrl || !rawCredentials) throw new Error("Evidence processor is not configured");
  const url = new URL(rawUrl);
  if (url.protocol !== "https:" || !url.hostname.endsWith(".run.app") || url.username || url.password || url.pathname !== "/" || url.search || url.hash) throw new Error("Invalid evidence processor URL");
  const credentials = record(JSON.parse(rawCredentials));
  if (!credentials || typeof credentials.client_email !== "string" || typeof credentials.private_key !== "string") throw new Error("Invalid evidence processor identity");
  return { url: url.origin, credentials: { client_email: credentials.client_email, private_key: credentials.private_key } };
}

async function privateProcess(payload: object, config: ReturnType<typeof processorConfig>): Promise<Result> {
  const client = new JWT({ email: config.credentials.client_email, key: config.credentials.private_key });
  client.transporter.defaults.timeout = 5_000;
  client.transporter.defaults.retry = false;
  const idToken = await client.fetchIdToken(config.url);
  if ("kind" in payload && payload.kind === "url") {
    const health = await fetch(`${config.url}/health`, { redirect: "error", signal: AbortSignal.timeout(15_000), headers: { Authorization: `Bearer ${idToken}` } });
    if (!health.ok) throw new Error("Processor unavailable");
    const capability: unknown = await health.json();
    if (!record(capability) || record(capability)?.accessPolicyVersion !== "e3-v1") throw new Error("Processor access policy unavailable");
  }
  const response = await fetch(`${config.url}/process`, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(115_000),
    headers: { "Authorization": `Bearer ${idToken}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok || !response.body) throw new Error("Evidence processor unavailable");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    total += next.value.length;
    if (total > 15_000_000) { await reader.cancel(); throw new Error("Evidence processor response too large"); }
    chunks.push(next.value);
  }
  const body = Buffer.concat(chunks.map(chunk => Buffer.from(chunk))).toString("utf8");
  return parseResult(JSON.parse(body));
}

export const processItem = internalAction({
  args: { itemId: v.id("evidenceItems") },
  handler: async (ctx, args): Promise<void> => {
    let config: ReturnType<typeof processorConfig>;
    try { config = processorConfig(); } catch { return; }
    const claim = await ctx.runMutation(internal.evidenceProcessing.claim, args);
    if (!claim) return;
    let result: Result;
    try {
      if (claim.source.kind === "url") {
        const accessRules = await ctx.runQuery(internal.evidenceReview.accessRules, {});
        result = await privateProcess({ kind: "url", url: claim.source.url, language: claim.language, ...accessRules }, config);
        if (result.kind === "ready" && !result.accessChain) throw new Error("Missing access chain");
      } else {
        if (!claim.source.storageId || !claim.source.sha256 || !claim.source.verifiedMime) throw new Error("Evidence upload unavailable");
        const blob = await ctx.storage.get(claim.source.storageId);
        if (!blob || blob.size > 10_000_000) throw new Error("Evidence upload unavailable");
        const bytes = Buffer.from(await blob.arrayBuffer());
        if (createHash("sha256").update(bytes).digest("hex") !== claim.source.sha256) throw new Error("Evidence upload checksum changed");
        result = await privateProcess({ kind: "file", mime: claim.source.verifiedMime, sha256: claim.source.sha256, bytesBase64: bytes.toString("base64"), language: claim.language }, config);
      }
    } catch {
      result = { kind: "failed", retryable: true };
    }
    let sourceStorageId: Id<"_storage"> | undefined;
    let attached = false;
    try {
      if (result.kind === "ready") {
        const { sourceBytesBase64, ...extracted } = result;
        if (claim.source.kind === "url") {
          if (!sourceBytesBase64) throw new Error("Missing source snapshot");
          const sourceBytes = Buffer.from(sourceBytesBase64, "base64");
          if (sourceBytes.length > 10_000_000 || createHash("sha256").update(sourceBytes).digest("hex") !== result.sha256) throw new Error("Source snapshot mismatch");
          sourceStorageId = await ctx.storage.store(new Blob([sourceBytes], { type: "application/x-hadithly-evidence-source" }));
        } else if (sourceBytesBase64 !== undefined) throw new Error("Unexpected source snapshot");
        attached = await ctx.runMutation(internal.evidenceProcessing.finish, { itemId: args.itemId, token: claim.token, result: { ...extracted, sourceStorageId } });
      } else attached = await ctx.runMutation(internal.evidenceProcessing.finish, { itemId: args.itemId, token: claim.token, result });
    } catch {
      await reportFailure(ctx, "evidence_processing");
      await ctx.runMutation(internal.evidenceProcessing.finish, { itemId: args.itemId, token: claim.token, result: { kind: "failed", retryable: true } }).catch(() => undefined);
    } finally {
      if (sourceStorageId && !attached) await ctx.storage.delete(sourceStorageId);
    }
  },
});
