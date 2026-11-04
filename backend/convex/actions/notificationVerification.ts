"use node";
import { v } from "convex/values";
import { internalAction } from "../_generated/server";
import { internal } from "../_generated/api";
import { isNamedDevelopmentDeployment } from "../generationIntegrity";
import { apnsConfigured, sendApnsPush } from "../lib/apns";
import { buildNotificationPayload } from "../lib/notifyContent";

export const sendCachedBukhariSeven = internalAction({
  args: { tokenId: v.id("pushTokens") },
  handler: async (ctx, args): Promise<"unavailable" | "accepted" | "rejected"> => {
    if (!isNamedDevelopmentDeployment() || !apnsConfigured()) return "unavailable";
    const target = await ctx.runQuery(internal.notificationVerification.getVerificationTarget, args);
    if (!target) return "unavailable";
    const payload = buildNotificationPayload({ ...target, translation: { text: target.translation, language: "ru", isAI: target.isAI } });
    try {
      await sendApnsPush(target.token, { alert: { title: payload.title, body: payload.body }, custom: payload.data });
      return "accepted";
    } catch {
      return "rejected";
    }
  },
});
