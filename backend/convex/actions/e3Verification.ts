"use node";
import { internalAction } from "../_generated/server";
import { independentReviews } from "./evidenceReview";
import { decidePublication, POLICY_VERSION } from "../lib/evidenceReviewPolicy";
import type { ReviewPacket } from "../lib/evidenceReviewPolicy";

// Real provider proof using only self-authored disposable text.
export const probe = internalAction({ args: {}, handler: async (): Promise<object> => {
  if (!process.env.CONVEX_CLOUD_URL?.includes("festive-cobra-664") || process.env.EVIDENCE_REVIEW_PAID_CONFIRMED !== "1" || !process.env.GEMINI_API_KEY) throw new Error("Development paid review configuration required");
  const text = "This is a test text.";
  const citation = { url: "https://hadithly.app", title: "Hadithly self-authored synthetic source", location: "Verification fixture, not a hadith" };
  const packet: ReviewPacket = { policyVersion: POLICY_VERSION, untrustedData: { canonicalId: "local_dump:e3_fixture:9001", language: "en", proposedTranslation: text, sources: [
    { id: "evidence:0", kind: "evidence", language: "en", text, citation, spans: [{ id: "span:0", start: 0, end: text.length, text }] },
    { id: "arabic:0", kind: "arabic", language: "ar", text: "هذا نص للاختبار.", citation, spans: [] },
  ] } };
  try {
    const passes = await independentReviews(packet, process.env.GEMINI_API_KEY);
    const decision = decidePublication({ packet, passes, clean: true, licensed: true, provenance: true, abuse: false });
    return { decision, modelVersions: passes.map(pass=>pass.modelVersion), confidence: passes.map(pass=>pass.verdict.confidence) };
  } catch (error) {
    return { failure: error instanceof Error && ["provider_authorization", "provider_limit", "provider_unavailable"].includes(error.message) ? error.message : "invalid_response" };
  }
} });

export const availableReviewModels = internalAction({ args: {}, handler: async (): Promise<object> => {
  if (!process.env.CONVEX_CLOUD_URL?.includes("festive-cobra-664") || !process.env.GEMINI_API_KEY) throw new Error("Development only");
  const response = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000", { signal: AbortSignal.timeout(15_000), redirect: "error", headers: { "x-goog-api-key": process.env.GEMINI_API_KEY } });
  if (!response.ok) {
    const errorBody: unknown = await response.json();
    const reasons: string[] = [];
    if (errorBody !== null && typeof errorBody === "object" && "error" in errorBody && errorBody.error !== null && typeof errorBody.error === "object" && "details" in errorBody.error && Array.isArray(errorBody.error.details)) {
      for (const detail of errorBody.error.details) if (detail !== null && typeof detail === "object" && "reason" in detail && typeof detail.reason === "string" && /^[A-Z_]+$/.test(detail.reason)) reasons.push(detail.reason);
    }
    return { httpStatus: response.status, reasons };
  }
  const body: unknown = await response.json();
  if (body === null || typeof body !== "object" || !("models" in body) || !Array.isArray(body.models)) throw new Error("Invalid model catalogue");
  return { httpStatus: response.status, models: body.models.flatMap((row: unknown) => row !== null && typeof row === "object" && "name" in row && typeof row.name === "string" && /^models\/gemini-(?:2\.5|3\.)/.test(row.name) && "supportedGenerationMethods" in row && Array.isArray(row.supportedGenerationMethods) && row.supportedGenerationMethods.includes("generateContent") ? [row.name] : []) };
} });
