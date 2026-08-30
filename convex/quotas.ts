import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const canGenerateAi = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return false;
    return user.aiGenerationsThisMonth < user.aiGenerationLimit;
  },
});

export const incrementAiGeneration = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) throw new Error("User not found");
    if (user.aiGenerationsThisMonth >= user.aiGenerationLimit) {
      throw new Error("AI generation quota exceeded");
    }
    await ctx.db.patch(args.userId, {
      aiGenerationsThisMonth: user.aiGenerationsThisMonth + 1,
      updatedAt: Date.now(),
    });
  },
});

export const resetMonthlyAiUsage = mutation({
  args: {},
  handler: async (ctx) => {
    const users = await ctx.db.query("users").collect();
    await Promise.all(
      users.map((user) =>
        ctx.db.patch(user._id, {
          aiGenerationsThisMonth: 0,
          updatedAt: Date.now(),
        }),
      ),
    );
    return users.length;
  },
});
