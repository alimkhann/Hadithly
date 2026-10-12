import { internalMutation, internalQuery, mutation } from "./_generated/server";
import { ConvexError, v } from "convex/values";
import { requireIdentity } from "./lib/identity";
import { generationIdentity, generationLanguage } from "./lib/generationPolicy";
import { parseInternalHadithId } from "./lib/sunnahNow";
import { admitRate } from "./quotas";

export const integrityProof = v.union(
  v.object({ kind: v.literal("app_attest"), keyId: v.string(), attestation: v.optional(v.string()), assertion: v.optional(v.string()) }),
  v.object({ kind: v.literal("play_integrity"), token: v.string() }),
  v.object({ kind: v.literal("unavailable") }),
);

export function isNamedDevelopmentDeployment(): boolean {
  return ["https://festive-cobra-664.eu-west-1.convex.cloud", "https://festive-cobra-664.convex.cloud"]
    .includes(process.env.CONVEX_CLOUD_URL ?? "");
}

export function allowUnattestedDevelopment(): boolean {
  return process.env.AI_ALLOW_UNATTESTED_DEV === "true" && isNamedDevelopmentDeployment();
}

export const beginChallenge = mutation({
  args: { hadithInternalId: v.string(), targetLanguage: v.string(), keyId: v.optional(v.string()) },
  handler: async (ctx, args) => {
    if (args.hadithInternalId.length > 100 || (args.keyId?.length ?? 0) > 200) throw new Error("AI_INTEGRITY_REJECTED");
    const identity = await requireIdentity(ctx), ref = parseInternalHadithId(args.hadithInternalId);
    const language = generationLanguage(args.targetLanguage), now = Date.now();
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", identity.clerkId)).unique();
    if (!user || !ref) throw new Error("Unauthenticated or invalid hadith");
    const retryAt = await admitRate(ctx, `challenge:${user._id}`, 10, user._id);
    if (retryAt) throw new ConvexError({ code: "AI_RATE_LIMITED", retryAt });
    const hadith = await ctx.db.query("hadiths").withIndex("by_provider_ref", q =>
      q.eq("provider", ref.provider).eq("collectionSlug", ref.collectionSlug).eq("providerHadithId", ref.providerHadithId)).unique();
    if (!hadith) throw new Error("Unknown hadith");
    // Bound abandoned challenge storage without a new periodic scan.
    for (const row of await ctx.db.query("generationChallenges").withIndex("by_user_time", q => q.eq("userId", user._id)).take(20))
      if (row.expiresAt <= now) await ctx.db.delete(row._id);
    const pending = await ctx.db.query("generationChallenges").withIndex("by_user_time", q => q.eq("userId", user._id)).take(10);
    if (pending.length >= 10) throw new ConvexError({ code: "AI_RATE_LIMITED", retryAt: now + 120_000 });
    const { generationKey } = await generationIdentity(hadith, language);
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    const nonce = Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
    const challengeId = await ctx.db.insert("generationChallenges", { userId: user._id, hadithId: hadith._id,
      language, generationKey, nonce, createdAt: now, expiresAt: now + 120_000 });
    const keyId = args.keyId;
    const credential = keyId ? await ctx.db.query("generationCredentials").withIndex("by_key", q => q.eq("keyId", keyId)).unique() : null;
    return { challengeId, payload: `${nonce}:${generationKey}`, keyRegistered: credential?.userId === user._id,
      allowUnavailable: allowUnattestedDevelopment(), playProjectNumber: process.env.PLAY_INTEGRITY_PROJECT_NUMBER ?? null };
  },
});

export const verificationContext = internalQuery({
  args: { challengeId: v.id("generationChallenges"), clerkId: v.string(), hadithId: v.id("hadiths"), language: v.string(), keyId: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const challenge = await ctx.db.get(args.challengeId), hadith = await ctx.db.get(args.hadithId);
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", args.clerkId)).unique();
    if (!challenge || !user || !hadith || challenge.userId !== user._id || challenge.hadithId !== hadith._id ||
      challenge.language !== args.language || challenge.expiresAt <= Date.now() ||
      challenge.generationKey !== (await generationIdentity(hadith, args.language)).generationKey) throw new Error("AI_INTEGRITY_REJECTED");
    const keyId = args.keyId;
    const credential = keyId ? await ctx.db.query("generationCredentials").withIndex("by_key", q => q.eq("keyId", keyId)).unique() : null;
    if (credential && credential.userId !== user._id) throw new Error("AI_INTEGRITY_REJECTED");
    return { challenge, credential };
  },
});

export const consumeVerified = internalMutation({
  args: { challengeId: v.id("generationChallenges"),
    credential: v.optional(v.object({ keyId: v.string(), publicKey: v.string(), signCount: v.number(), previousCount: v.optional(v.number()) })) },
  handler: async (ctx, args) => {
    const challenge = await ctx.db.get(args.challengeId);
    if (!challenge || challenge.expiresAt <= Date.now() || !await ctx.db.get(challenge.userId)) throw new Error("AI_INTEGRITY_REJECTED");
    if (args.credential) {
      const input = args.credential;
      const existing = await ctx.db.query("generationCredentials").withIndex("by_key", q => q.eq("keyId", input.keyId)).unique();
      if (existing) {
        if (existing.userId !== challenge.userId || input.previousCount !== existing.signCount || input.signCount <= existing.signCount || input.publicKey !== existing.publicKey)
          throw new Error("AI_INTEGRITY_REJECTED");
        await ctx.db.patch(existing._id, { signCount: input.signCount });
      } else {
        if (input.previousCount !== undefined || input.signCount !== 0) throw new Error("AI_INTEGRITY_REJECTED");
        await ctx.db.insert("generationCredentials", { userId: challenge.userId, keyId: input.keyId, publicKey: input.publicKey, signCount: 0 });
      }
    }
    await ctx.db.delete(challenge._id);
  },
});
