import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";

/** Internal: check whether a user still has AI quota remaining. */
export const canGenerateAi = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return false;
    return user.aiGenerationsThisMonth < user.aiGenerationLimit;
  },
});

/** Internal: consume one AI generation. Throws when the quota is exhausted. */
export const incrementAiGeneration = internalMutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) throw new Error("User not found");
    if (user.aiGenerationsThisMonth >= user.aiGenerationLimit) {
      throw new Error("AI_GENERATION_QUOTA_EXCEEDED");
    }
    await ctx.db.patch(args.userId, {
      aiGenerationsThisMonth: user.aiGenerationsThisMonth + 1,
      updatedAt: Date.now(),
    });
  },
});

/** Internal: reset monthly AI usage. Runs via a scheduled cron. */
export const resetMonthlyAiUsage = internalMutation({
  args: {},
  handler: async (ctx) => {
    const users = await ctx.db.query("users").collect();
    const now = Date.now();
    for (const user of users) {
      if (user.aiGenerationsThisMonth > 0) {
        await ctx.db.patch(user._id, {
          aiGenerationsThisMonth: 0,
          updatedAt: now,
        });
      }
    }
    return users.length;
  },
});
