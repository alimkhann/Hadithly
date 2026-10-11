/// <reference types="vite/client" />
import { createHash } from "node:crypto";
import { convexTest } from "convex-test";
import { api, internal } from "../convex/_generated/api";
import schema from "../convex/schema";
import { CONSENT_VERSION } from "../convex/evidenceReview";
import { REVIEW_MODELS, textDigest } from "../convex/lib/evidenceReviewPolicy";
import type { PermissionGrant, ReviewPacket, ReviewPass } from "../convex/lib/evidenceReviewPolicy";
const modules = import.meta.glob("../convex/**/*.ts");
export const text = "Actions follow intentions.";
export function isRecord(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === "object" && !Array.isArray(value); }
export function passes(packet: ReviewPacket, confidence = 0.99): ReviewPass[] {
  return REVIEW_MODELS.map((model, index) => ({ model, modelVersion: model, requestId: `request-${index}`, pass: index === 0 ? "meaning" : "challenge", verdict: {
    confidence, consistent: true, contradiction: false, unsupportedClaims: false, injection: false, abuseFlags: [],
    supports: packet.untrustedData.sources.filter(source => source.kind === "evidence" || source.kind === "sunnah_com").map(source => ({ sourceId: source.id, spanId: source.spans[0]?.id ?? "missing", quote: source.spans[0]?.text ?? "missing" })),
    comparisons: packet.untrustedData.sources.filter(source => source.kind !== "evidence" && source.kind !== "sunnah_com").map(source => ({ sourceId: source.id, consistent: true, contradiction: false, unsupportedClaims: false })),
  } }));
}
export async function fixture(options: { grant?: boolean; consent?: boolean; content?: string } = {}) {
  const t = convexTest(schema, modules), owner = t.withIdentity({ subject: "e3_owner", tokenIdentifier: "https://clerk.example|e3_owner" });
  const outsider = t.withIdentity({ subject: "e3_other", tokenIdentifier: "https://clerk.example|e3_other" });
  await owner.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  await outsider.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  const hadithId = await t.run(ctx => ctx.db.insert("hadiths", { provider: "sunnah_now", canonicalId: "sunnah_now:bukhari:1", collectionSlug: "bukhari", providerHadithId: "1", arabicText: "إنما الأعمال بالنيات", referenceDisplay: "Bukhari 1", collectionName: "Bukhari", createdAt: 1 }));
  const bytes = new TextEncoder().encode("fixture bytes"), sha256 = createHash("sha256").update(bytes).digest("hex");
  const draft = await owner.mutation(api.evidence.createEvidenceDraft, { hadithInternalId: hadithId, language: "en", proposedContent: options.content ?? text, draftKey: "e3_fixture_key", items: [{ kind: "file", clientItemKey: "e3_fixture_item", declaredMime: "image/png", declaredSize: bytes.length, declaredSha256: sha256, displayName: "fixture.png" }] });
  await t.run(ctx => ctx.db.patch(draft.submissionId, { auditReceipt: "00000001-0000-0000-0000-000000000000" }));
  const item = draft.items[0]; if (!item) throw new Error("Missing item");
  await t.run(async ctx => {
    const storageId = await ctx.storage.store(new Blob([bytes], { type: "image/png" }));
    const row = await ctx.db.get(item.itemId); if (!row || row.source.kind !== "file") throw new Error("Missing file");
    await ctx.db.patch(row._id, { source: { ...row.source, storageId, verifiedMime: "image/png", sha256, size: bytes.length }, state: "quarantined_unscanned" });
  });
  await owner.mutation(api.evidence.finalizeEvidenceDraft, { submissionId: draft.submissionId, contributionConsentVersion: options.consent === false ? undefined : CONSENT_VERSION });
  const claim = await t.mutation(internal.evidenceProcessing.claim, { itemId: item.itemId }); if (!claim) throw new Error("Missing processing claim");
  await t.mutation(internal.evidenceProcessing.finish, { itemId: item.itemId, token: claim.token, result: { kind: "ready", mime: "image/png", sha256, text: options.content ?? text, spans: [{ start: 0, end: (options.content ?? text).length, source: { kind: "page_box", page: 1, x: 0, y: 0, width: 100, height: 30 } }] } });
  const grant: PermissionGrant = { sourceKind: "evidence", sourceUrl: "", artifactSha256: sha256, textSha256: await textDigest(options.content ?? text), canonicalId: "sunnah_now:bukhari:1", language: "en",
    citation: { url: "https://example.org/fixture", title: "Fixture author", location: "p. 1" }, rightsHolder: "Fixture author", permissionUrl: "https://example.org/fixture-permission", permissionSha256: "c".repeat(64), licenseName: "Fixture permission", attribution: "Fixture author",
    access: true, comparison: true, modelProcessing: true, adaptation: true, display: true, redistribution: true, offline: false, conditions: "attribution_only", verifiedAt: 1 };
  const grantId = options.grant === false ? null : await t.mutation(internal.evidenceReview.recordPermission, { grant, submissionId: draft.submissionId });
  const arabicText = "إنما الأعمال بالنيات", arabicSha = await textDigest(arabicText);
  await t.mutation(internal.evidenceReview.recordPermission, { grant: { ...grant, sourceKind: "sunnah_now", sourceUrl: "https://sunnah.now/", artifactSha256: arabicSha, textSha256: arabicSha, language: "ar" } });
  return { t, owner, outsider, draft, itemId: item.itemId, hadithId, grantId, grant };
}

export async function turnIntoUrl(f: Awaited<ReturnType<typeof fixture>>, url: string, content: string, chain = [url]) {
  await f.t.run(async ctx => {
    const item = await ctx.db.get(f.itemId);
    const extraction = await ctx.db.query("evidenceExtractions").withIndex("by_item", q => q.eq("evidenceItemId", f.itemId)).unique();
    if (!item || item.source.kind !== "file" || !item.source.storageId || !extraction) throw new Error("Missing file fixture");
    await ctx.db.patch(item._id, { source: { kind: "url", url: chain[0] ?? url } });
    await ctx.db.patch(extraction._id, { text: content, finalUrl: url, accessChain: chain, sourceStorageId: item.source.storageId,
      spans: [{ start: 0, end: content.length, source: { kind: "page_box", page: 1, x: 0, y: 0, width: 100, height: 30 } }] });
  });
}
function fixtureTerms(g: PermissionGrant) {
  return { rightsHolder: g.rightsHolder, permissionUrl: g.permissionUrl, permissionSha256: g.permissionSha256, licenseName: g.licenseName, attribution: g.attribution,
    access: g.access, comparison: g.comparison, modelProcessing: g.modelProcessing, adaptation: g.adaptation, display: g.display, redistribution: g.redistribution, offline: g.offline, conditions: g.conditions };
}
export async function addPolicy(f: Awaited<ReturnType<typeof fixture>>, origin: string, kind: "evidence" | "sunnah_com" | "sunnah_now" = "evidence", languages = ["en"]) {
  return f.t.mutation(internal.evidenceReview.recordSourcePolicy, { policy: { origin, sourceKind: kind, checkedAt: Date.now(), assessment: { kind: "permitted", pathPrefix: "/", languages, terms: fixtureTerms(f.grant), expiresAt: Date.now() + 1_000_000 } } });
}
export async function reviewClaim(f: Awaited<ReturnType<typeof fixture>>) {
  const claim = await f.t.mutation(internal.evidenceReview.claim, { submissionId: f.draft.submissionId, reviewEnabled: true });
  if (!claim) throw new Error("Missing review claim"); return claim;
}
