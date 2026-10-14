import { v } from "convex/values";
import type { Infer } from "convex/values";

export const DAY = 86_400_000;
export const supportFields = {
  requestId: v.string(), email: v.string(), message: v.string(),
  topic: v.union(v.literal("account"), v.literal("subscription"), v.literal("reading"), v.literal("accessibility"), v.literal("other")),
  platform: v.union(v.literal("ios"), v.literal("android"), v.literal("web")),
};
export const supportInput = v.object({ ...supportFields, token: v.string(), website: v.string() });
export type SupportInput = Infer<typeof supportInput>;
export const noticeKind = v.union(v.literal("support"), v.literal("ai_budget"), v.literal("support_budget"), v.literal("review_budget"), v.literal("test"));
export type NoticeKind = Infer<typeof noticeKind>;
export function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
export function validEmail(value: string): boolean {
  return value.length <= 254 && /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,63}$/.test(value);
}
export function parseSupport(value: unknown): SupportInput | null {
  if (!record(value) || Object.keys(value).sort().join(",") !== "email,message,platform,requestId,token,topic,website") return null;
  const { requestId, email, message, topic, platform, token, website } = value;
  if (typeof requestId !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(requestId)
    || typeof email !== "string" || !validEmail(email) || typeof message !== "string" || message.trim().length < 10
    || message.length > 2000 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(message)
    || (topic !== "account" && topic !== "subscription" && topic !== "reading" && topic !== "accessibility" && topic !== "other")
    || (platform !== "ios" && platform !== "android" && platform !== "web")
    || typeof token !== "string" || token.length < 1 || token.length > 2048 || website !== "") return null;
  return { requestId, email: email.toLowerCase(), message: message.trim(), topic, platform, token, website };
}
export function noticeText(kind: NoticeKind, reference: string): string {
  switch (kind) {
    case "support": return `A support request was accepted. Reference: ${reference}. Read it in the private Convex support inbox. Request contents and contact details are not included in this email.`;
    case "ai_budget": return "The ordinary AI monthly budget reached 80%. Cached and offline reading remain available. Inspect the private usage dashboard before changing any limit.";
    case "support_budget": return "The monthly support form allowance reached 80%. Email support remains available. Review abuse and capacity before changing any limit.";
    case "review_budget": return "The monthly evidence review allowance reached 80%. Pending evidence stays private. Review provider costs before changing any limit.";
    case "test": return "Synthetic Hadithly operational mail test. No real user data. No authentication action is required.";
  }
}
export async function boundedText(request: Request | Response, max: number): Promise<string | null> {
  if (!request.body) return null;
  const reader = request.body.getReader(), chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const next = await reader.read(); if (next.done) break;
    size += next.value.length;
    if (size > max) { await reader.cancel(); return null; }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder().decode(bytes);
}
export async function verifyMailSignature(body: string, headers: Headers, secret: string, now: number): Promise<boolean> {
  const id = headers.get("svix-id"), timestamp = headers.get("svix-timestamp"), signatures = headers.get("svix-signature");
  if (!id || id.length > 200 || !timestamp || !/^\d{10}$/.test(timestamp) || !signatures || signatures.length > 1000
    || Math.abs(now / 1000 - Number(timestamp)) > 300 || !secret.startsWith("whsec_")) return false;
  try {
    const key = await crypto.subtle.importKey("raw", Uint8Array.from(atob(secret.slice(6)), c => c.charCodeAt(0)),
      { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
    const data = new TextEncoder().encode(`${id}.${timestamp}.${body}`);
    for (const signature of signatures.split(" ")) {
      if (!signature.startsWith("v1,")) continue;
      if (await crypto.subtle.verify("HMAC", key, Uint8Array.from(atob(signature.slice(3)), c => c.charCodeAt(0)), data)) return true;
    }
  } catch { return false; }
  return false;
}
