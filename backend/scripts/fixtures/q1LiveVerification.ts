// Temporary internal verification module. The controller installs it only on
// development and removes it after cleanup. It is never a mobile API.
import { internalMutation } from "./_generated/server";
import { v } from "convex/values";
function developmentOnly() {
  if (!["https://festive-cobra-664.eu-west-1.convex.cloud", "https://festive-cobra-664.convex.cloud"].includes(process.env.CONVEX_CLOUD_URL ?? "")) throw new Error("Development only");
}
export const seed = internalMutation({
  args: { runId: v.string(), providerIds: v.array(v.string()) },
  handler: async (ctx, args) => {
    developmentOnly();
    if (!/^[a-f0-9-]{36}$/.test(args.runId) || args.providerIds.length > 12 || args.providerIds.some(id => !/^9[0-9]{9}$/.test(id))) throw new Error("Invalid fixture");
    const now = Date.now(), collectionSlug = "q1_fixture";
    const licenseRecordId = await ctx.db.insert("licenseRecords", { sourceKey: `q1-fixture:${args.runId}`, sourceName: "Self-authored verification", sourceUrl: "https://example.test/q1-fixture",
      terms: { kind: "verified", licenseName: "Self-authored disposable fixture", licenseUrl: "https://example.test/q1-fixture", permitsDisplay: true, permitsRedistribution: false, permitsOfflineDistribution: false, verifiedAt: now }, createdAt: now, updatedAt: now });
    const targets = [];
    for (const providerHadithId of args.providerIds) {
      const canonicalId = `local_dump:${collectionSlug}:${providerHadithId}`;
      if (await ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", canonicalId)).unique()) throw new Error("Existing fixture");
      const hadith = { provider: "local_dump" as const, canonicalId, collectionSlug, providerHadithId, volumeId: "1",
        arabicText: "هذه جملة اختبار كتبها المطور وليست حديثا: يقرأ القارئ بعناية ويتحقق من المصدر.",
        englishText: "This is a self-authored test sentence, not a hadith: the reader reads carefully and checks the source.",
        referenceDisplay: "Q1 synthetic verification", collectionName: "Q1 synthetic verification", licenseRecordId,
        authenticity: { kind: "unverified" as const, claimScope: "none" as const, sourceLabel: "Self-authored fixture", sourceName: "Self-authored fixture", sourceUrl: "https://example.test/q1-fixture", verificationMethod: "unavailable" as const },
        createdAt: now, sourceUpdatedAt: now };
      const _id = await ctx.db.insert("hadiths", hadith);
      targets.push({ _id, ...hadith });
    }
    return { runId: args.runId, licenseRecordId, targets };
  },
});
export const cleanup = internalMutation({
  args: { runId: v.string(), providerIds: v.array(v.string()) },
  handler: async (ctx, args) => {
    developmentOnly();
    const license = await ctx.db.query("licenseRecords").withIndex("by_source_key", q => q.eq("sourceKey", `q1-fixture:${args.runId}`)).unique();
    if (!license) return { removed: 0 };
    let removed = 0;
    for (const providerHadithId of args.providerIds) {
      const hadith = await ctx.db.query("hadiths").withIndex("by_provider_ref", q => q.eq("provider", "local_dump").eq("collectionSlug", "q1_fixture").eq("providerHadithId", providerHadithId)).unique();
      if (!hadith || hadith.licenseRecordId !== license._id) continue;
      for (const row of await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", hadith._id)).collect()) await ctx.db.delete(row._id);
      const keys = await ctx.db.query("aiGenerationJobs").withIndex("by_key").collect();
      for (const job of keys) if (job.hadithId === hadith._id) {
        if (job.status === "pending" && job.expiresAt > Date.now()) throw new Error("Fixture still running");
        const event = await ctx.db.query("aiUsageEvents").withIndex("by_key", q => q.eq("generationKey", job.generationKey)).unique();
        if (event) for (const charge of await ctx.db.query("aiUsageCharges").collect()) {
          if (charge.eventId === event._id) await ctx.db.delete(charge._id);
        }
        await ctx.db.patch(job._id, { userId: undefined });
      }
      for (const row of await ctx.db.query("generationChallenges").collect()) if (row.hadithId === hadith._id) await ctx.db.delete(row._id);
      await ctx.db.delete(hadith._id); removed++;
    }
    await ctx.db.delete(license._id);
    return { removed };
  },
});
