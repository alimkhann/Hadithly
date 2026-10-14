"use node";
import { createHmac } from "node:crypto";
import { internalAction } from "../_generated/server";
import { internal } from "../_generated/api";
import { v } from "convex/values";
import { boundedText, noticeText, record } from "../lib/supportPolicy";

export const verifyChallenge = internalAction({ args: { token: v.string(), email: v.string() }, handler: async (_, args): Promise<string | null> => {
  const secret = process.env.SUPPORT_TURNSTILE_SECRET, salt = process.env.SUPPORT_RATE_SECRET;
  if (!secret || !salt || salt.length < 32) return null;
  try {
    const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", redirect: "error",
      signal: AbortSignal.timeout(5000), headers: { "Content-Type": "application/json" }, body: JSON.stringify({ secret, response: args.token }) });
    const text = await boundedText(response, 8192);
    const result: unknown = text && response.ok ? JSON.parse(text) : null;
    if (!record(result) || result.success !== true || result.hostname !== "hadithly.app" || result.action !== "support") return null;
    return createHmac("sha256", salt).update(args.email).digest("hex");
  } catch { return null; }
} });
export const sendNotice = internalAction({ args: { mailId: v.id("operationsMail") }, handler: async (ctx, args): Promise<void> => {
  const claim = await ctx.runMutation(internal.support.claimMail, args);
  if (!claim) return;
  try {
    const response = await fetch("https://api.resend.com/emails", { method: "POST", redirect: "error", signal: AbortSignal.timeout(10_000),
      headers: { "Authorization": `Bearer ${process.env.RESEND_API_KEY}`, "Content-Type": "application/json", "Idempotency-Key": `la3-${args.mailId}` },
      body: JSON.stringify({ from: "Hadithly operations <operations@updates.hadithly.app>", to: [process.env.OPERATIONS_EMAIL],
        subject: "Hadithly operational notice", text: noticeText(claim.kind, claim.reference) }) });
    const text = await boundedText(response, 4096);
    const raw: unknown = text && response.ok ? JSON.parse(text) : null;
    if (record(raw) && typeof raw.id === "string" && /^[a-zA-Z0-9-]{1,100}$/.test(raw.id))
      await ctx.runMutation(internal.support.finishMail, { ...args, providerId: raw.id });
  } catch { /* Attempt remains consumed. A timeout must not duplicate mail. */ }
} });
