import { v } from "convex/values";
import type { Infer } from "convex/values";

export const POLICY_VERSION = "e4-review-v1";
export const REVIEW_MODELS = ["gemini-3.8-flash", "gemini-3.5-flash-lite"] as const;
export const AUTO_PUBLICATION_THRESHOLD = 0.95;

export const publicCitation = v.object({ url: v.string(), title: v.string(), location: v.string() });
export const permissionGrant = v.object({
  sourceKind: v.union(v.literal("evidence"), v.literal("sunnah_now"), v.literal("sunnah_com"), v.literal("approved_translation"), v.literal("ai_translation")),
  sourceUrl: v.string(), artifactSha256: v.string(), textSha256: v.string(), canonicalId: v.string(), language: v.string(),
  citation: publicCitation,
  rightsHolder: v.string(), permissionUrl: v.string(), permissionSha256: v.string(), licenseName: v.string(), attribution: v.string(),
  access: v.boolean(), comparison: v.boolean(), modelProcessing: v.boolean(),
  adaptation: v.boolean(), display: v.boolean(), redistribution: v.boolean(), offline: v.boolean(),
  // Conditional licenses require a separate compliance implementation before use.
  conditions: v.union(v.literal("attribution_only"), v.literal("unsupported")),
  verifiedAt: v.number(), expiresAt: v.optional(v.number()), revokedAt: v.optional(v.number()),
});
export type PermissionGrant = Infer<typeof permissionGrant>;

// Cache source policy once; artifact provenance still binds each exact text.
export const sourcePolicy = v.object({
  origin: v.string(), sourceKind: v.union(v.literal("sunnah_now"), v.literal("sunnah_com"), v.literal("evidence")),
  assessment: v.union(
    v.object({ kind: v.literal("unknown") }),
    v.object({ kind: v.literal("avoid"), reason: v.string(), termsUrl: v.string() }),
    v.object({ kind: v.literal("permitted"),
      pathPrefix: v.string(), languages: v.array(v.string()),
      terms: v.object({
        rightsHolder: v.string(), permissionUrl: v.string(), permissionSha256: v.string(), licenseName: v.string(), attribution: v.string(),
        access: v.boolean(), comparison: v.boolean(), modelProcessing: v.boolean(), adaptation: v.boolean(), display: v.boolean(), redistribution: v.boolean(), offline: v.boolean(),
        conditions: v.union(v.literal("attribution_only"), v.literal("unsupported")),
      }),
      expiresAt: v.number(),
    }),
  ),
  checkedAt: v.number(),
});
export type SourcePolicy = Infer<typeof sourcePolicy>;
export function pathWithinPolicy(path: string, prefix: string): boolean {
  return path === prefix || path.startsWith(prefix) && (prefix.endsWith("/") || prefix.endsWith(":") || path[prefix.length] === "/");
}

export const reviewVerdict = v.object({
  confidence: v.number(), consistent: v.boolean(), contradiction: v.boolean(), unsupportedClaims: v.boolean(),
  injection: v.boolean(), abuseFlags: v.array(v.string()),
  supports: v.array(v.object({ sourceId: v.string(), spanId: v.string(), quote: v.string() })),
  comparisons: v.array(v.object({ sourceId: v.string(), consistent: v.boolean(), contradiction: v.boolean(), unsupportedClaims: v.boolean() })),
});
export type ReviewVerdict = Infer<typeof reviewVerdict>;
export const reviewPass = v.object({
  model: v.string(), modelVersion: v.string(), requestId: v.string(), pass: v.union(v.literal("meaning"), v.literal("challenge")),
  verdict: reviewVerdict,
});
export type ReviewPass = Infer<typeof reviewPass>;

export type ReviewSource = {
  id: string; kind: "evidence" | "sunnah_now" | "sunnah_com" | "approved_translation" | "related_language" | "ai_translation" | "arabic";
  language: string; text: string; citation: Infer<typeof publicCitation>;
  spans: Array<{ id: string; start: number; end: number; text: string }>;
};
export type ReviewPacket = { policyVersion: string; untrustedData: {
  canonicalId: string; language: string; proposedTranslation: string; sources: ReviewSource[]; concerns?: string[];
} };

export async function textDigest(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

export function assessPermission(input: {
  grant: PermissionGrant | null; artifactSha256: string; textSha256: string; sourceUrl: string;
  canonicalId: string; language: string; publication: boolean; now: number;
}): "affirmative" | "ambiguous" | "denied" {
  const grant = input.grant;
  if (!grant) return "ambiguous";
  if (grant.artifactSha256 !== input.artifactSha256 || grant.textSha256 !== input.textSha256 ||
      grant.sourceUrl !== input.sourceUrl || grant.canonicalId !== input.canonicalId || grant.language !== input.language ||
      grant.verifiedAt > input.now || grant.revokedAt !== undefined || (grant.expiresAt !== undefined && grant.expiresAt <= input.now)) return "ambiguous";
  if (!grant.access || !grant.comparison || !grant.modelProcessing || grant.conditions !== "attribution_only") return "denied";
  return !input.publication || grant.adaptation && grant.display && grant.redistribution ? "affirmative" : "denied";
}

export function injectionSuspected(text: string): boolean {
  const normalized = text.normalize("NFKC").replace(/[\u200b-\u200f\u202a-\u202e\u2060-\u206f]/g, "");
  return /(?:ignore|disregard|forget|override).{0,60}(instruction|prompt|rule)|do\s+not\s+follow.{0,50}(above|prior|previous|instruction)|(?:system|developer|assistant)\s*:|<\/?(?:tool_call|system|assistant)|\[INST\]|(?:set|return|report|output).{0,40}(confidence|score|no\s+flags)|reveal.{0,30}(secret|credential)|игнорируй.{0,40}инструк|تجاهل.{0,40}(التعليمات|القواعد)|(?:ignora|ignorer|ignorez|ignorar).{0,50}(reglas|instrucciones|instructions|règles|regras)|(?:попередні|алдыңғы|мурунку).{0,30}(інструк|нұсқау|көрсөтм)|(?:پچھلی|سابقہ).{0,30}(ہدایات|قواعد)|نظر\s*انداز.{0,30}(ہدایات|قواعد)|忽略.{0,20}指令/is.test(normalized);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function exactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}
export function parseReviewVerdict(raw: unknown): ReviewVerdict | null {
  if (!isRecord(raw) || !exactKeys(raw, ["confidence", "consistent", "contradiction", "unsupportedClaims", "injection", "abuseFlags", "supports", "comparisons"]) ||
      typeof raw.confidence !== "number" || !Number.isFinite(raw.confidence) || raw.confidence < 0 || raw.confidence > 1 ||
      typeof raw.consistent !== "boolean" || typeof raw.contradiction !== "boolean" || typeof raw.unsupportedClaims !== "boolean" || typeof raw.injection !== "boolean" ||
      !Array.isArray(raw.abuseFlags) || raw.abuseFlags.length > 20 || !raw.abuseFlags.every((flag): flag is string => typeof flag === "string" && flag.length <= 200) ||
      !Array.isArray(raw.supports) || raw.supports.length > 30 || !Array.isArray(raw.comparisons) || raw.comparisons.length > 12) return null;
  const supports: ReviewVerdict["supports"] = [];
  for (const row of raw.supports) {
    if (!isRecord(row) || !exactKeys(row, ["sourceId", "spanId", "quote"]) || typeof row.sourceId !== "string" || row.sourceId.length > 100 ||
        typeof row.spanId !== "string" || row.spanId.length > 100 || typeof row.quote !== "string" || !row.quote.trim() || row.quote.length > 10_000) return null;
    supports.push({ sourceId: row.sourceId, spanId: row.spanId, quote: row.quote });
  }
  const comparisons: ReviewVerdict["comparisons"] = [];
  for (const row of raw.comparisons) {
    if (!isRecord(row) || !exactKeys(row, ["sourceId", "consistent", "contradiction", "unsupportedClaims"]) || typeof row.sourceId !== "string" || row.sourceId.length > 100 ||
        typeof row.consistent !== "boolean" || typeof row.contradiction !== "boolean" || typeof row.unsupportedClaims !== "boolean") return null;
    comparisons.push({ sourceId: row.sourceId, consistent: row.consistent, contradiction: row.contradiction, unsupportedClaims: row.unsupportedClaims });
  }
  return { confidence: raw.confidence, consistent: raw.consistent, contradiction: raw.contradiction, unsupportedClaims: raw.unsupportedClaims, injection: raw.injection,
    abuseFlags: raw.abuseFlags, supports, comparisons };
}
export function decidePublication(input: {
  packet: ReviewPacket; passes: ReviewPass[]; clean: boolean; licensed: boolean; provenance: boolean; abuse: boolean;
}): { kind: "publish" | "exception" | "reject"; reasons: string[] } {
  const reasons: string[] = [];
  if (!input.clean) reasons.push("scan");
  if (!input.licensed) reasons.push("license");
  if (!input.provenance) reasons.push("provenance");
  if (input.abuse) reasons.push("abuse");
  if (injectionSuspected(JSON.stringify(input.packet.untrustedData))) reasons.push("injection");
  const [first, second] = input.passes;
  if (input.passes.length !== 2 || !first || !second || first.pass !== "meaning" || second.pass !== "challenge" ||
      first.model !== REVIEW_MODELS[0] || second.model !== REVIEW_MODELS[1] || !first.modelVersion || !second.modelVersion ||
      first.modelVersion === second.modelVersion || !first.requestId || !second.requestId || first.requestId === second.requestId) reasons.push("independence");
  const evidence = input.packet.untrustedData.sources.filter(source => source.kind === "evidence" || source.kind === "sunnah_com");
  const comparisons = input.packet.untrustedData.sources.filter(source => source.kind !== "evidence" && source.kind !== "sunnah_com");
  if (!evidence.length || !comparisons.some(source => source.kind === "arabic")) reasons.push("support");
  for (const pass of input.passes) {
    const verdict = parseReviewVerdict(pass.verdict);
    if (!verdict) { reasons.push("invalid_review"); continue; }
    if (verdict.confidence <= AUTO_PUBLICATION_THRESHOLD) reasons.push("confidence");
    if (!verdict.consistent) reasons.push("consistency");
    if (verdict.contradiction || verdict.comparisons.some(comparison => comparison.contradiction)) reasons.push("contradiction");
    if (verdict.unsupportedClaims || verdict.comparisons.some(comparison => comparison.unsupportedClaims)) reasons.push("unsupported_claims");
    if (verdict.injection) reasons.push("injection");
    if (verdict.abuseFlags.length) reasons.push("abuse");
    if (verdict.supports.some(support => {
      const source = evidence.find(candidate => candidate.id === support.sourceId);
      const span = source?.spans.find(span => span.id === support.spanId);
      return !source || !span || !span.text.includes(support.quote) || source.text.slice(span.start, span.end) !== span.text;
    }) || evidence.some(source => !verdict.supports.some(support => support.sourceId === source.id))) reasons.push("citations");
    const ids = verdict.comparisons.map(comparison => comparison.sourceId);
    if (ids.length !== comparisons.length || new Set(ids).size !== ids.length || comparisons.some(source => !ids.includes(source.id)) ||
        verdict.comparisons.some(comparison => !comparison.consistent)) reasons.push("comparisons");
  }
  const unique = [...new Set(reasons)];
  return { kind: unique.length === 0 ? "publish" : unique.some(reason => ["injection", "abuse", "contradiction", "unsupported_claims"].includes(reason)) ? "reject" : "exception", reasons: unique };
}
