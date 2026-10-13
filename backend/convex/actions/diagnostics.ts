"use node";
import { randomUUID } from "node:crypto";
import { v } from "convex/values";
import { internalAction } from "../_generated/server";
import { operation, surface, safeEvent, sentryDestination } from "../lib/diagnosticsPolicy";

export const send = internalAction({
  args: { operation, surface, release: v.optional(v.string()) },
  handler: async (_ctx, args): Promise<"sent" | "dropped"> => {
    const destination = sentryDestination(args.surface === "web" ? process.env.DIAGNOSTICS_SENTRY_WEB_DSN : process.env.DIAGNOSTICS_SENTRY_DSN);
    if (process.env.DIAGNOSTICS_ENABLED !== "1" || !destination) return "dropped";
    const event = safeEvent({ ...args, eventId: randomUUID().replaceAll("-", "") });
    console.info(JSON.stringify(event));
    try {
      const response = await fetch(destination.url, { method: "POST", redirect: "error",
        headers: { "Content-Type": "application/x-sentry-envelope", "X-Sentry-Auth": destination.authorization },
        body: `${JSON.stringify({ event_id: event.event_id })}\n${JSON.stringify({ type: "event" })}\n${JSON.stringify(event)}\n`,
        signal: AbortSignal.timeout(3000) });
      await response.body?.cancel();
      return response.ok ? "sent" : "dropped";
    } catch { return "dropped"; }
  },
});
