/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { PDFDocument } from "pdf-lib";
import { createHash } from "node:crypto";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { MAX_EVIDENCE_BYTES } from "./lib/evidencePolicy";
import { verifyEvidenceFile } from "./lib/evidenceFiles";

const modules = import.meta.glob("./**/*.ts");
const asIdentity = (subject: string) => ({ subject, tokenIdentifier: `https://clerk.example|${subject}` });
const png = new Uint8Array(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lXcAAAAASUVORK5CYII=", "base64"));
const pngSha256 = createHash("sha256").update(png).digest("hex");

async function fixture() {
  const t = convexTest(schema, modules);
  const owner = t.withIdentity(asIdentity("evidence_owner"));
  const outsider = t.withIdentity(asIdentity("evidence_outsider"));
  await owner.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  await outsider.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  const canonicalId = "sunnah_now:bukhari:1";
  const hadithId = await t.run(ctx => ctx.db.insert("hadiths", {
    provider: "sunnah_now", canonicalId, providerHadithId: "1", collectionSlug: "bukhari",
    arabicText: "نص", englishText: "Text", referenceDisplay: "Bukhari · Hadith 1",
    collectionName: "Sahih al-Bukhari", createdAt: 1,
  }));
  return { t, owner, outsider, hadithId, canonicalId };
}

const urlItem = { kind: "url" as const, clientItemKey: "url_item_1", url: "https://example.org/source#section" };
const fileItem = { kind: "file" as const, clientItemKey: "file_item_1", declaredMime: "image/png" as const, declaredSize: png.length, declaredSha256: pngSha256, displayName: "evidence.png" };

describe("E1 private evidence intake", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());
  test("resolves the reader's canonical hadith target to its stored row", async () => {
    const { t, owner, hadithId, canonicalId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, {
      hadithInternalId: canonicalId, language: "ur", proposedContent: "Faithful translation",
      draftKey: "canonical_target_1", items: [urlItem],
    });
    expect((await t.run(ctx => ctx.db.get(draft.submissionId)))?.hadithId).toBe(hadithId);
  });

  test("resolves a canonical reader target against legacy rows without a stored canonical ID", async () => {
    const { t, owner, hadithId, canonicalId } = await fixture();
    await t.run(ctx => ctx.db.patch(hadithId, { canonicalId: undefined }));
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, {
      hadithInternalId: canonicalId, language: "ur", proposedContent: "Faithful translation",
      draftKey: "legacy_canonical_target_1", items: [urlItem],
    });
    expect((await t.run(ctx => ctx.db.get(draft.submissionId)))?.hadithId).toBe(hadithId);
  });

  test("creates a private URL draft, normalizes its source, and only finalizes to processing", async () => {
    const { t, owner, outsider, hadithId } = await fixture();
    const args = { hadithInternalId: hadithId, language: "ur", proposedContent: "Faithful translation", draftKey: "draft_key_1", items: [urlItem] };
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, args);
    expect(draft.items[0]?.url).toBe("https://example.org/source");
    expect((await owner.mutation(api.evidence.createEvidenceDraft, args)).submissionId).toBe(draft.submissionId);
    await expect(outsider.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId })).rejects.toThrow();
    expect(await owner.mutation(api.evidence.finalizeEvidenceDraft, { submissionId: draft.submissionId })).toEqual({ status: "awaiting_processing" });
    const saved = await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId });
    expect(saved.status).toBe("awaiting_processing");
    expect(JSON.stringify(saved)).not.toContain("storageId");
    await t.finishInProgressScheduledFunctions();
  });

  test("rejects missing, duplicate, unsupported, and oversized evidence before storage", async () => {
    const { owner, hadithId } = await fixture();
    const base = { hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_key_2" };
    await expect(owner.mutation(api.evidence.createEvidenceDraft, { ...base, items: [] })).rejects.toThrow("One to three");
    await expect(owner.mutation(api.evidence.createEvidenceDraft, { ...base, items: [urlItem, { ...urlItem, clientItemKey: "url_item_2", url: "https://example.org/source" }] })).rejects.toThrow("Duplicate");
    await expect(owner.mutation(api.evidence.createEvidenceDraft, { ...base, items: [{ ...fileItem, declaredSize: MAX_EVIDENCE_BYTES + 1 }] })).rejects.toThrow("10 MB");
    await expect(owner.mutation(api.evidence.createEvidenceDraft, { ...base, items: [{ ...urlItem, url: "http://example.org" }] })).rejects.toThrow("HTTPS");
  });

  test("caps new drafts per account while idempotent retries remain free", async () => {
    const { owner, hadithId } = await fixture();
    const base = { hadithInternalId: hadithId, language: "ur", proposedContent: "Text", items: [urlItem] };
    for (let index = 0; index < 5; index++) {
      const args = { ...base, draftKey: `draft_limit_${index}` };
      const first = await owner.mutation(api.evidence.createEvidenceDraft, args);
      expect((await owner.mutation(api.evidence.createEvidenceDraft, args)).submissionId).toBe(first.submissionId);
    }
    await expect(owner.mutation(api.evidence.createEvidenceDraft, { ...base, draftKey: "draft_limit_6" })).rejects.toThrow("Daily evidence submission limit");
  });

  test("the raw HTTP upload validates ownership, bytes, and keeps storage private", async () => {
    const { t, owner, outsider, hadithId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, { hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_key_3", items: [fileItem] });
    const headers = { "content-type": "image/png", "x-evidence-submission-id": draft.submissionId, "x-evidence-item-id": draft.items[0]!.itemId };
    const forbidden = await outsider.fetch("/evidence/upload", { method: "POST", headers, body: png });
    expect(forbidden.status).toBe(400);
    const interrupted = await owner.fetch("/evidence/upload", { method: "POST", headers, body: png.slice(0, 12) });
    expect(interrupted.status).toBe(400);
    const result = await owner.fetch("/evidence/upload", { method: "POST", headers, body: png });
    expect(result.status).toBe(200);
    expect(await result.json()).toMatchObject({ state: "quarantined_unscanned", size: png.length });
    const privateView = await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId });
    expect(privateView.items[0]?.state).toBe("quarantined_unscanned");
    expect(JSON.stringify(privateView)).not.toContain("storageId");
    expect(JSON.stringify(privateView)).not.toContain("downloadUrl");
    const storedId = await t.run(async ctx => (await ctx.db.get(draft.items[0]!.itemId))?.source);
    expect(storedId?.kind).toBe("file");
    await owner.mutation(api.evidence.finalizeEvidenceDraft, { submissionId: draft.submissionId });
    const translations = await t.run(ctx => ctx.db.query("translations").collect());
    expect(translations).toHaveLength(0);
    await t.finishInProgressScheduledFunctions();
  });

  test("a changed file is rejected against the preflight checksum", async () => {
    const { owner, hadithId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, {
      hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_hash_1",
      items: [{ ...fileItem, declaredSha256: "0".repeat(64) }],
    });
    const response = await owner.fetch("/evidence/upload", {
      method: "POST",
      headers: { "content-type": "image/png", "x-evidence-submission-id": draft.submissionId, "x-evidence-item-id": draft.items[0]!.itemId },
      body: png,
    });
    expect(response.status).toBe(400);
    expect((await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId })).items[0]?.state).toBe("reserved");
  });

  test("concurrent uploads bind one slot once and duplicate files do not attach twice", async () => {
    const { t, owner, hadithId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, {
      hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_race_1",
      items: [fileItem, { ...fileItem, clientItemKey: "file_item_2" }],
    });
    const headers = (itemId: string) => ({ "content-type": "image/png", "x-evidence-submission-id": draft.submissionId, "x-evidence-item-id": itemId });
    const firstId = draft.items[0]!.itemId;
    const responses = await Promise.all([
      owner.fetch("/evidence/upload", { method: "POST", headers: headers(firstId), body: png }),
      owner.fetch("/evidence/upload", { method: "POST", headers: headers(firstId), body: png }),
    ]);
    expect(responses.some(response => response.status === 200)).toBe(true);
    const second = await owner.fetch("/evidence/upload", { method: "POST", headers: headers(draft.items[1]!.itemId), body: png });
    expect(second.status).toBe(400);
    const rows = await t.run(ctx => ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", draft.submissionId)).collect());
    expect(rows.filter(row => row.state === "quarantined_unscanned")).toHaveLength(1);
    expect(rows.filter(row => row.state === "invalid")).toHaveLength(1);
  });

  test("malformed and oversized image or PDF bytes fail before any publication", async () => {
    await expect(verifyEvidenceFile(new Uint8Array([1, 2, 3]), "image/png")).rejects.toThrow();
    await expect(verifyEvidenceFile(png, "image/jpeg")).rejects.toThrow("does not match");
    await expect(verifyEvidenceFile(new TextEncoder().encode("%PDF-not a document"), "application/pdf")).rejects.toThrow("Invalid or encrypted");
    await expect(verifyEvidenceFile(new Uint8Array(MAX_EVIDENCE_BYTES + 1), "image/png")).rejects.toThrow("10 MB");
    const valid = await verifyEvidenceFile(png, "image/png");
    expect(valid).toMatchObject({ mime: "image/png", width: 1, height: 1 });
    const hugeHeader = png.slice();
    hugeHeader.set([0, 0, 50, 200], 16);
    await expect(verifyEvidenceFile(hugeHeader, "image/png")).rejects.toThrow("dimensions");
    const pdf = await PDFDocument.create();
    for (let i = 0; i < 26; i++) pdf.addPage();
    await expect(verifyEvidenceFile(new Uint8Array(await pdf.save()), "application/pdf")).rejects.toThrow("1 to 25");
  });

  test("a completed fifth upload remains idempotent and binding rechecks expiry", async () => {
    const { t, owner, hadithId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, { hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_key_7", items: [fileItem] });
    await t.run(ctx => ctx.db.patch(draft.items[0]!.itemId, { state: "quarantined_unscanned", uploadAttempts: 5 }));
    const headers = { "content-type": "image/png", "x-evidence-submission-id": draft.submissionId, "x-evidence-item-id": draft.items[0]!.itemId };
    expect((await owner.fetch("/evidence/upload", { method: "POST", headers, body: png })).status).toBe(200);
    await t.run(async ctx => {
      await ctx.db.patch(draft.items[0]!.itemId, { state: "reserved", uploadAttempts: 0 });
      await ctx.db.patch(draft.submissionId, { expiresAt: Date.now() - 1 });
    });
    const storageId = await t.run(ctx => ctx.storage.store(new Blob([png], { type: "image/png" })));
    await expect(t.mutation(internal.evidence.bindUpload, { clerkId: "evidence_owner", submissionId: draft.submissionId, itemId: draft.items[0]!.itemId, storageId })).rejects.toThrow("no longer available");
  });

  test("expiry and account deletion remove quarantined bytes", async () => {
    const { t, owner, hadithId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, { hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_key_4", items: [fileItem] });
    const headers = { "content-type": "image/png", "x-evidence-submission-id": draft.submissionId, "x-evidence-item-id": draft.items[0]!.itemId };
    expect((await owner.fetch("/evidence/upload", { method: "POST", headers, body: png })).status).toBe(200);
    const storageId = await t.run(async ctx => {
      const item = await ctx.db.get(draft.items[0]!.itemId);
      return item?.source.kind === "file" ? item.source.storageId : undefined;
    });
    expect(storageId).toBeDefined();
    await owner.mutation(api.users.deleteCurrentUser, {});
    expect(await t.run(ctx => ctx.storage.get(storageId!))).toBeNull();
    expect(await t.run(ctx => ctx.db.query("evidenceItems").collect())).toHaveLength(0);
  });

  test("the orphan sweep removes an E1 upload but keeps referenced offline storage", async () => {
    const { t, owner, hadithId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, { hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_key_5", items: [fileItem] });
    const { orphanId, offlineId, unrelatedId } = await t.run(async ctx => {
      const orphanId = await ctx.storage.store(new Blob([png], { type: "image/png" }));
      const unrelatedId = await ctx.storage.store(new Blob([new Uint8Array(png.length).fill(1)], { type: "image/png" }));
      const offlineId = await ctx.storage.store(new Blob(["offline"], { type: "application/json" }));
      const licenseRecordId = await ctx.db.insert("licenseRecords", { sourceKey: "test", sourceName: "Test", sourceUrl: "https://example.org", terms: { kind: "unverified" }, createdAt: 1, updatedAt: 1 });
      await ctx.db.insert("offlineArtifacts", { kind: "base", collectionSlug: "bukhari", schemaVersion: 1, contentVersion: "one", storageId: offlineId, sha256: "test", byteSize: 7, minAppVersion: "1", generatedAt: 1, licenseRecordId, compatiblePacks: [], createdAt: 1, updatedAt: 1 });
      return { orphanId, offlineId, unrelatedId };
    });
    await owner.mutation(api.evidence.deleteEvidenceDraft, { submissionId: draft.submissionId });
    const swept = await t.mutation(internal.evidence.sweepStorageOrphans, { nowMs: Date.now() + 3 * 60 * 60 * 1000 });
    expect(swept.deleted).toBe(1);
    expect(await t.run(ctx => ctx.storage.get(orphanId))).toBeNull();
    expect(await t.run(async ctx => (await ctx.storage.get(offlineId)) !== null)).toBe(true);
    expect(await t.run(async ctx => (await ctx.storage.get(unrelatedId)) !== null)).toBe(true);
  });

  test("an abandoned draft expires and cannot be submitted", async () => {
    const { t, owner, hadithId } = await fixture();
    const draft = await owner.mutation(api.evidence.createEvidenceDraft, { hadithInternalId: hadithId, language: "ur", proposedContent: "Text", draftKey: "draft_key_6", items: [urlItem] });
    await t.run(ctx => ctx.db.patch(draft.submissionId, { expiresAt: Date.now() - 1 }));
    expect(await t.mutation(internal.evidence.expireEvidence, {})).toBe(1);
    expect((await owner.query(api.evidence.getOwnEvidenceDraft, { submissionId: draft.submissionId })).status).toBe("expired");
    await expect(owner.mutation(api.evidence.finalizeEvidenceDraft, { submissionId: draft.submissionId })).rejects.toThrow("closed");
  });

  test("legacy rows cannot use old AI or admin publication paths", async () => {
    const { t, owner, hadithId, canonicalId } = await fixture();
    const userId = await t.run(async ctx => (await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", "evidence_owner")).unique())!._id);
    const legacyId = await t.run(ctx => ctx.db.insert("communitySubmissions", { hadithId, language: "ur", submittedBy: userId, proposedContent: "Old", aiReview: { model: "old", score: 1, riskFlags: [], recommendation: "approve" }, status: "pending", createdAt: 1 }));
    await t.mutation(internal.evidence.migrateLegacySubmissions, { paginationOpts: { numItems: 10, cursor: null } });
    const legacy = await t.run(ctx => ctx.db.get(legacyId));
    expect(legacy?.status).toBe("legacy_evidence_missing");
    expect(await owner.query(api.evidence.getOwnLegacyProposal, { hadithInternalId: hadithId, language: "ur" })).toMatchObject({ submissionId: legacyId, proposedContent: "Old" });
    expect(await owner.query(api.evidence.getOwnLegacyProposal, { hadithInternalId: canonicalId, language: "ur" })).toMatchObject({ submissionId: legacyId });
    await expect(owner.action(api.actions.ai.submitTranslation, { hadithInternalId: hadithId, language: "ur", proposedContent: "No source" })).rejects.toThrow("Evidence is required");
    await expect(owner.mutation(api.community.approveSubmission, { submissionId: legacyId })).rejects.toThrow("evidence review");
    await expect(owner.mutation(api.community.rejectSubmission, { submissionId: legacyId })).rejects.toThrow("exception pipeline");
    expect(await t.run(ctx => ctx.db.query("translations").collect())).toHaveLength(0);
    const upgraded = await owner.mutation(api.evidence.createEvidenceDraft, {
      hadithInternalId: hadithId, language: "ur", proposedContent: "Old",
      legacySubmissionId: legacyId, draftKey: "legacy_upgrade_1", items: [urlItem],
    });
    expect(upgraded.submissionId).toBe(legacyId);
    expect(await owner.mutation(api.evidence.finalizeEvidenceDraft, { submissionId: legacyId })).toEqual({ status: "awaiting_processing" });
    expect((await t.run(ctx => ctx.db.get(legacyId)))?.aiReview?.model).toBe("old");
    expect(await t.run(ctx => ctx.db.query("translations").collect())).toHaveLength(0);
    await t.finishInProgressScheduledFunctions();
  });

  test("historical live community text stays live while its evidence gap is flagged", async () => {
    const { t, hadithId } = await fixture();
    const translationId = await t.run(ctx => ctx.db.insert("translations", {
      hadithId, language: "ur", content: "Historical text", source: "community",
      sourceLabel: "Community", status: "live", isDefault: true,
      groundingUsed: false, createdAt: 1, updatedAt: 1,
    }));
    const args = { paginationOpts: { numItems: 10, cursor: null } };
    expect((await t.mutation(internal.evidence.markLegacyCommunityTranslations, args)).flagged).toBe(1);
    expect((await t.mutation(internal.evidence.markLegacyCommunityTranslations, args)).flagged).toBe(0);
    expect(await t.run(ctx => ctx.db.get(translationId))).toMatchObject({
      content: "Historical text", status: "live", legacyEvidenceMissing: true,
    });
  });
});
