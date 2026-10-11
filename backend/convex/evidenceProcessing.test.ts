/// <reference types="vite/client" />

import { createHash } from "node:crypto";
import { convexTest } from "convex-test";
import { JWT } from "google-auth-library";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const identity = (subject: string) => ({ subject, tokenIdentifier: `https://clerk.example|${subject}` });
const htmlBytes = new TextEncoder().encode("<p>quoted source</p>");
const htmlSha = createHash("sha256").update(htmlBytes).digest("hex");

async function fixture(kind: "url" | "file" = "url") {
  const t = convexTest(schema, modules);
  const owner = t.withIdentity(identity("e2_owner"));
  const outsider = t.withIdentity(identity("e2_outsider"));
  await owner.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  await outsider.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  const hadithId = await t.run(ctx => ctx.db.insert("hadiths", {
    provider: "sunnah_now", canonicalId: "sunnah_now:bukhari:1", providerHadithId: "1", collectionSlug: "bukhari",
    arabicText: "نص", englishText: "Text", referenceDisplay: "Bukhari · Hadith 1", collectionName: "Sahih al-Bukhari", createdAt: 1,
  }));
  const bytes = new Uint8Array([1, 2, 3]);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const draft = await owner.mutation(api.evidence.createEvidenceDraft, {
    hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "e2_draft_key",
    items: kind === "url" ? [{ kind: "url", clientItemKey: "e2_item_key", url: "https://example.org/source" }] :
      [{ kind: "file", clientItemKey: "e2_item_key", declaredMime: "image/png", declaredSize: bytes.length, declaredSha256: sha256, displayName: "image.png" }],
  });
  const itemId = draft.items[0]!.itemId;
  await t.run(async ctx => {
    await ctx.db.patch(draft.submissionId, { status: "awaiting_processing", expiresAt: Date.now() + 60_000 });
    if (kind === "file") {
      const storageId = await ctx.storage.store(new Blob([bytes], { type: "image/png" }));
      await ctx.db.patch(itemId, { state: "quarantined_unscanned", source: { kind: "file", declaredMime: "image/png", declaredSize: bytes.length, declaredSha256: sha256, displayName: "image.png", storageId, verifiedMime: "image/png", sha256, size: bytes.length } });
    }
  });
  return { t, owner, outsider, draft, itemId, sha256 };
}

describe("E2 processing state and privacy", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => { vi.useRealTimers(); vi.unstubAllEnvs(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });

  test("a clean result becomes private untrusted text with source offsets", async () => {
    const { t, owner, outsider, draft, itemId } = await fixture();
    const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    const sourceStorageId = await t.run(ctx => ctx.storage.store(new Blob([htmlBytes], { type: "application/x-hadithly-evidence-source" })));
    expect(claim?.source.kind).toBe("url");
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId, token: claim!.token, result: {
      kind: "ready", mime: "text/html", sha256: htmlSha, finalUrl: "https://example.org/source", sourceStorageId,
      text: "quoted source", spans: [{ start: 0, end: 13, source: { kind: "html_chars", start: 3, end: 16 } }],
    } })).toBe(true);
    const extraction = await t.run(ctx => ctx.db.query("evidenceExtractions").withIndex("by_item", q => q.eq("evidenceItemId", itemId)).unique());
    expect(extraction).toMatchObject({ trust: "untrusted", text: "quoted source", spans: [{ source: { start: 3, end: 16 } }] });
    const retained = await t.run(async ctx => (await ctx.storage.get(sourceStorageId))?.text());
    expect(retained?.slice(3, 16)).toBe(extraction?.text);
    const own = await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId });
    expect(own.status).toBe("evidence_ready");
    expect(own.items[0]?.state).toBe("ready");
    expect(JSON.stringify(own)).not.toContain("quoted source");
    expect(JSON.stringify(await owner.query(api.users.exportCurrentUserData, {}))).not.toContain("quoted source");
    await expect(outsider.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId })).rejects.toThrow();
    await owner.mutation(api.evidence.deleteEvidenceDraft, { submissionId: draft.submissionId });
    expect(await t.run(ctx => ctx.db.query("evidenceExtractions").collect())).toHaveLength(0);
    expect(await t.run(ctx => ctx.storage.get(sourceStorageId))).toBeNull();
  });

  test("infection is terminal, deletes quarantined bytes, and never creates extraction", async () => {
    const { t, owner, draft, itemId } = await fixture("file");
    const storageId = await t.run(async ctx => {
      const item = await ctx.db.get(itemId);
      return item?.source.kind === "file" ? item.source.storageId : undefined;
    });
    const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId, token: claim!.token, result: { kind: "infected" } })).toBe(true);
    expect((await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId })).status).toBe("infected");
    expect(await t.run(ctx => ctx.storage.get(storageId!))).toBeNull();
    expect(await t.run(ctx => ctx.db.query("evidenceExtractions").collect())).toHaveLength(0);
    await expect(owner.mutation(api.evidenceProcessing.retryOwnEvidenceProcessing, { submissionId: draft.submissionId, itemId })).rejects.toThrow("cannot be retried");
  });

  test("withdrawal rejects a late clean result", async () => {
    const { t, owner, draft, itemId } = await fixture();
    const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    await owner.mutation(api.evidence.deleteEvidenceDraft, { submissionId: draft.submissionId });
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId, token: claim!.token, result: { kind: "infected" } })).toBe(false);
    expect(await t.run(ctx => ctx.db.query("evidenceExtractions").collect())).toHaveLength(0);
  });

  test("account deletion removes a completed private extraction", async () => {
    const { t, owner, itemId } = await fixture();
    const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    const sourceStorageId = await t.run(ctx => ctx.storage.store(new Blob([htmlBytes], { type: "application/x-hadithly-evidence-source" })));
    await t.mutation(internal.evidenceProcessing.finish, { itemId, token: claim!.token, result: {
      kind: "ready", mime: "text/html", sha256: htmlSha, finalUrl: "https://example.org/source", sourceStorageId,
      text: "quoted source", spans: [{ start: 0, end: 13, source: { kind: "html_chars", start: 3, end: 16 } }],
    } });
    expect(await t.run(ctx => ctx.db.query("evidenceExtractions").collect())).toHaveLength(1);
    await owner.mutation(api.users.deleteCurrentUser, {});
    expect(await t.run(ctx => ctx.db.query("evidenceExtractions").collect())).toHaveLength(0);
  });

  test("failure and stale lease are bounded, and retry is owner only", async () => {
    const { t, owner, outsider, draft, itemId } = await fixture();
    const first = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId, token: "wrong", result: { kind: "infected" } })).toBe(false);
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId, token: first!.token, result: { kind: "failed", retryable: true } })).toBe(true);
    await expect(outsider.mutation(api.evidenceProcessing.retryOwnEvidenceProcessing, { submissionId: draft.submissionId, itemId })).rejects.toThrow("not found");
    expect(await owner.mutation(api.evidenceProcessing.retryOwnEvidenceProcessing, { submissionId: draft.submissionId, itemId })).toBe(true);
    await expect(owner.mutation(api.evidenceProcessing.retryOwnEvidenceProcessing, { submissionId: draft.submissionId, itemId })).rejects.toThrow("cannot be retried");
    const second = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    expect(second).not.toBeNull();
    await t.run(ctx => ctx.db.patch(itemId, { processingLease: { token: second!.token, deadline: Date.now() - 1 } }));
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId, token: second!.token, result: { kind: "infected" } })).toBe(false);
    expect(await t.mutation(internal.evidenceProcessing.recoverStalled, {})).toBe(1);
    expect((await t.run(ctx => ctx.db.get(itemId)))?.state).toBe("failed");
    await owner.mutation(api.evidenceProcessing.retryOwnEvidenceProcessing, { submissionId: draft.submissionId, itemId });
    const third = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    expect(third).not.toBeNull();
    await t.mutation(internal.evidenceProcessing.finish, { itemId, token: third!.token, result: { kind: "failed", retryable: true } });
    expect((await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId })).status).toBe("processing_failed");
    await expect(owner.mutation(api.evidenceProcessing.retryOwnEvidenceProcessing, { submissionId: draft.submissionId, itemId })).rejects.toThrow("cannot be retried");
  });

  test("file extraction must match the quarantined checksum", async () => {
    const { t, itemId } = await fixture("file");
    const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    await expect(t.mutation(internal.evidenceProcessing.finish, { itemId, token: claim!.token, result: {
      kind: "ready", mime: "image/png", sha256: "0".repeat(64), text: "text", spans: [{ start: 0, end: 4, source: { kind: "page_box", page: 1, x: 0, y: 0, width: 10, height: 10 } }],
    } })).rejects.toThrow("Invalid processor result");
    expect(await t.run(ctx => ctx.db.query("evidenceExtractions").collect())).toHaveLength(0);
  });

  test("the action sends private bytes to the IAM processor and commits only its bounded result", async () => {
    const { t, owner, draft, itemId, sha256 } = await fixture("file");
    vi.stubEnv("EVIDENCE_PROCESSOR_URL", "");
    vi.stubEnv("EVIDENCE_PROCESSOR_GOOGLE_CREDENTIALS", "");
    await t.action(internal.actions.evidenceProcessing.processItem, { itemId });
    expect(await t.run(ctx => ctx.db.get(itemId))).toMatchObject({ state: "quarantined_unscanned" });
    expect((await t.run(ctx => ctx.db.get(itemId)))?.processingAttempts).toBeUndefined();
    vi.stubEnv("EVIDENCE_PROCESSOR_URL", "https://hadithly-evidence-example.run.app");
    vi.stubEnv("EVIDENCE_PROCESSOR_GOOGLE_CREDENTIALS", JSON.stringify({ client_email: "invoker@example.iam.gserviceaccount.com", private_key: "test-only-key" }));
    vi.spyOn(JWT.prototype, "fetchIdToken").mockResolvedValue("test-only-id-token");
    const externalFetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      expect(String(url)).toBe("https://hadithly-evidence-example.run.app/process");
      expect(init?.headers).toMatchObject({ Authorization: "Bearer test-only-id-token" });
      const body = JSON.parse(String(init?.body));
      expect(body).toMatchObject({ kind: "file", mime: "image/png", sha256, bytesBase64: "AQID", language: "ur" });
      expect(JSON.stringify(body)).not.toContain("storageId");
      return Response.json({ kind: "ready", mime: "image/png", sha256, text: "source", spans: [{ start: 0, end: 6, source: { kind: "page_box", page: 1, x: 0, y: 0, width: 20, height: 10 } }] });
    });
    vi.stubGlobal("fetch", externalFetch);
    await t.action(internal.actions.evidenceProcessing.processItem, { itemId });
    expect(externalFetch).toHaveBeenCalledTimes(1);
    expect((await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId })).status).toBe("evidence_ready");
    expect((await t.run(ctx => ctx.db.query("evidenceExtractions").collect()))[0]?.text).toBe("source");
    expect(await t.run(ctx => ctx.db.query("translations").collect())).toHaveLength(0);
  });

  test("expired leases are found beyond 25 active processing rows", async () => {
    const { t, itemId } = await fixture();
    const expiredId = await t.run(async ctx => {
      const item = await ctx.db.get(itemId);
      if (!item) throw new Error("Missing fixture");
      const { _id, _creationTime, ...row } = item;
      for (let i = 0; i < 30; i++) await ctx.db.insert("evidenceItems", { ...row, clientItemKey: `active_${i}`, state: "processing", processingAttempts: 1, processingLease: { token: `active_${i}`, deadline: Date.now() + 60_000 } });
      return await ctx.db.insert("evidenceItems", { ...row, clientItemKey: "expired_item", state: "processing", processingAttempts: 1, processingLease: { token: "expired", deadline: Date.now() - 1 } });
    });
    expect(await t.mutation(internal.evidenceProcessing.recoverStalled, {})).toBe(1);
    expect(await t.run(ctx => ctx.db.get(expiredId))).toMatchObject({ state: "failed", retryable: true });
  });

  test("URL processing retains the exact private source bytes for its offsets", async () => {
    const { t, owner, draft, itemId } = await fixture();
    vi.stubEnv("EVIDENCE_PROCESSOR_URL", "https://hadithly-evidence-example.run.app");
    vi.stubEnv("EVIDENCE_PROCESSOR_GOOGLE_CREDENTIALS", JSON.stringify({ client_email: "invoker@example.iam.gserviceaccount.com", private_key: "test-only-key" }));
    vi.spyOn(JWT.prototype, "fetchIdToken").mockResolvedValue("test-only-id-token");
    vi.stubGlobal("fetch", vi.fn(async (url: string) => url.endsWith("/health") ? Response.json({ accessPolicyVersion: "e3-v1" }) : Response.json({ kind: "ready", mime: "text/html", accessChain: ["https://example.org/source"], sha256: htmlSha, finalUrl: "https://example.org/source", sourceBytesBase64: Buffer.from(htmlBytes).toString("base64"), text: "quoted source", spans: [{ start: 0, end: 13, source: { kind: "html_chars", start: 3, end: 16 } }] })));
    await t.action(internal.actions.evidenceProcessing.processItem, { itemId });
    const extraction = await t.run(ctx => ctx.db.query("evidenceExtractions").withIndex("by_item", q => q.eq("evidenceItemId", itemId)).unique());
    expect(extraction?.sourceStorageId).toBeDefined();
    expect(await t.run(async ctx => (await ctx.storage.get(extraction!.sourceStorageId!))?.text())).toBe("<p>quoted source</p>");
    expect(JSON.stringify(await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId }))).not.toContain("sourceStorageId");
  });

  test("an infected item cancels in-flight siblings and removes their private bytes", async () => {
    const { t, itemId, draft } = await fixture("file");
    const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    const sibling = await t.run(async ctx => {
      const item = await ctx.db.get(itemId);
      if (!item || item.source.kind !== "file") throw new Error("Missing fixture");
      const storageId = await ctx.storage.store(new Blob(["sibling"]));
      const { _id, _creationTime, ...row } = item;
      const siblingId = await ctx.db.insert("evidenceItems", { ...row, clientItemKey: "sibling_item", source: { ...item.source, storageId }, state: "processing", processingAttempts: 1, processingLease: { token: "sibling", deadline: Date.now() + 60_000 } });
      return { siblingId, storageId };
    });
    await t.mutation(internal.evidenceProcessing.finish, { itemId, token: claim!.token, result: { kind: "infected" } });
    expect(await t.run(ctx => ctx.db.get(sibling.siblingId))).toMatchObject({ state: "failed", retryable: false });
    expect(await t.run(ctx => ctx.storage.get(sibling.storageId))).toBeNull();
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId: sibling.siblingId, token: "sibling", result: { kind: "infected" } })).toBe(false);
    expect((await t.run(ctx => ctx.db.get(draft.submissionId)))?.status).toBe("infected");
  });

  test("the one-slot worker queue preserves a waiting item without spending an attempt", async () => {
    const { t, itemId } = await fixture();
    const siblingId = await t.run(async ctx => {
      const item = await ctx.db.get(itemId);
      if (!item) throw new Error("Missing fixture");
      const { _id, _creationTime, ...row } = item;
      return ctx.db.insert("evidenceItems", { ...row, clientItemKey: "queued_sibling", processingQueued: true });
    });
    const first = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    expect(await t.mutation(internal.evidenceProcessing.claim, { itemId: siblingId })).toBeNull();
    expect(await t.run(ctx => ctx.db.get(siblingId))).toMatchObject({ state: "pending_safe_fetch", processingQueued: true });
    expect((await t.run(ctx => ctx.db.get(siblingId)))?.processingAttempts).toBeUndefined();
    await t.mutation(internal.evidenceProcessing.finish, { itemId, token: first!.token, result: { kind: "failed", retryable: false } });
    expect(await t.mutation(internal.evidenceProcessing.claim, { itemId: siblingId })).not.toBeNull();
    expect((await t.run(ctx => ctx.db.get(siblingId)))?.processingAttempts).toBe(1);
  });

  test("withdrawal holds the worker slot until the discarded result returns", async () => {
    const { t, owner, itemId, draft } = await fixture();
    const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId });
    await owner.mutation(api.evidence.deleteEvidenceDraft, { submissionId: draft.submissionId });
    expect(await t.run(ctx => ctx.db.query("evidenceWorkerLease").collect())).toHaveLength(1);
    expect(await t.mutation(internal.evidenceProcessing.finish, { itemId, token: claim!.token, result: { kind: "failed", retryable: true } })).toBe(false);
    expect(await t.run(ctx => ctx.db.query("evidenceWorkerLease").collect())).toHaveLength(0);
  });
});
