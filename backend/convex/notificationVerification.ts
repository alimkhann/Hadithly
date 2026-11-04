import { v } from "convex/values";
import { internalQuery } from "./_generated/server";
import { isNamedDevelopmentDeployment } from "./generationIntegrity";
import { availableDefault } from "./translations";

export const getVerificationTarget = internalQuery({
  args: { tokenId: v.id("pushTokens") },
  handler: async (ctx, { tokenId }) => {
    if (!isNamedDevelopmentDeployment()) return null;
    const token = await ctx.db.get(tokenId);
    if (!token || token.platform !== "ios" || !token.enabled) return null;
    const hadith = await ctx.db.query("hadiths").withIndex("by_provider_ref", q =>
      q.eq("provider", "sunnah_now").eq("collectionSlug", "bukhari").eq("providerHadithId", "7")).unique();
    if (!hadith?.licenseRecordId) return null;
    const license = await ctx.db.get(hadith.licenseRecordId);
    if (license?.terms.kind !== "verified" || !license.terms.permitsDisplay) return null;
    const translation = await availableDefault(ctx, hadith, "ru");
    if (!translation?.content.trim()) return null;
    return { token: token.token, hadithId: hadith._id, collectionName: hadith.collectionName,
      collectionSlug: hadith.collectionSlug, providerHadithId: hadith.providerHadithId,
      referenceDisplay: hadith.referenceDisplay, volumeId: hadith.volumeId,
      translation: translation.content, isAI: translation.source === "gemini_ai" };
  },
});
