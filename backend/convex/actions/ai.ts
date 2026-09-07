"use node";

/**
 * AI actions (Gemini). Everything AI-related runs server-side with the key
 * in Convex env vars (GEMINI_API_KEY). Clients only ever receive finished
 * translations or review verdicts.
 *
 * There is deliberately no public voting, rating, or leaderboard anywhere
 * in this flow. Quality is enforced by AI review + admin approval.
 */

import { GoogleGenAI, Type } from "@google/genai";
import { v } from "convex/values";
import { action } from "../_generated/server";
import type { ActionCtx } from "../_generated/server";
import { api, internal } from "../_generated/api";
import type { Id } from "../_generated/dataModel";
import { requireIdentity } from "../lib/identity";
import {
  deriveSourceReferenceUrl,
  extractCitations,
  parseTranslationPayload,
  untrustedProviderDataBlock,
} from "../lib/grounding";
import { parseInternalHadithId } from "../lib/sunnahNow";

const GEMINI_TRANSLATION_MODEL = "gemini-2.5-flash-lite";
const GEMINI_REVIEW_MODEL = "gemini-2.5-flash-lite";

type HadithDoc = {
  _id: Id<"hadiths">;
  collectionSlug: string;
  providerHadithId: string;
  arabicText: string;
  englishText?: string;
  narrator?: string;
  referenceDisplay: string;
  collectionName: string;
};

type Citation = { url: string; title?: string; domain?: string };

type TranslationResult = {
  translationId: string;
  translation: string;
  confidence: number;
  riskFlags: string[];
  glossaryNotes: string[];
  source: string;
  sourceLabel: string;
  aiModel?: string;
  groundingUsed: boolean;
  citations: Citation[];
  sourceReferenceUrl?: string;
  cached: boolean;
};

function gemini(): GoogleGenAI {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error("GEMINI_API_KEY is not configured");
  return new GoogleGenAI({ apiKey });
}

function translationPrompt(hadith: HadithDoc, targetLanguage: string) {
  return [
    "You are a careful translator of hadith (Prophetic narrations).",
    `Translate the hadith faithfully into the target language (${targetLanguage}).`,
    "Preserve religious meaning and tone. Do not issue legal rulings (fatwa).",
    "Use Google Search to verify narrator names, proper nouns, and the established rendering of key Islamic terms.",
    'Respond with ONLY a single JSON object, no prose and no code fences, in exactly this shape: {"translation": string, "confidence": number between 0 and 1, "riskFlags": string[], "glossaryNotes": string[]}.',
    "",
    untrustedProviderDataBlock(hadith),
  ].join("\n");
}

// Fallback when the grounded response is not valid JSON: re-ask the model to
// reformat into the required shape using structured output (no tools).
async function repairTranslationJson(ai: GoogleGenAI, raw: string) {
  if (!raw.trim()) return null;
  try {
    const response = await ai.models.generateContent({
      model: GEMINI_TRANSLATION_MODEL,
      contents: `Reformat the following into the required JSON object. Keep the translation text intact.\n\n${raw}`,
      config: {
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            translation: { type: Type.STRING },
            confidence: { type: Type.NUMBER },
            riskFlags: { type: Type.ARRAY, items: { type: Type.STRING } },
            glossaryNotes: { type: Type.ARRAY, items: { type: Type.STRING } },
          },
          required: ["translation", "confidence", "riskFlags", "glossaryNotes"],
        },
      },
    });
    return parseTranslationPayload(response.text ?? "");
  } catch {
    return null;
  }
}

async function loadHadith(
  ctx: ActionCtx,
  internalId: string,
): Promise<HadithDoc | null> {
  const identity = parseInternalHadithId(internalId);
  if (!identity) return null;
  return await ctx.runQuery(internal.hadiths.getByProviderRef, {
    provider: identity.provider,
    collectionSlug: identity.collectionSlug,
    providerHadithId: identity.providerHadithId,
  });
}

/**
 * Requires a signed-in user (AI quota is per user). Cache-first: returns the
 * cached default translation when one already exists for the language.
 */
export const translateHadith = action({
  args: {
    hadithInternalId: v.string(),
    targetLanguage: v.string(),
  },
  handler: async (ctx, args): Promise<TranslationResult> => {
    const identity = await requireIdentity(ctx);

    const parts = args.hadithInternalId.split(":");
    if (parts.length !== 3) {
      throw new Error("Invalid hadith internal id");
    }
    const [, collectionSlug, providerHadithId] = parts;

    const cached = await ctx.runQuery(
      api.translations.getDefaultForProviderRef,
      {
        provider: "sunnah_now",
        collectionSlug,
        providerHadithId,
        language: args.targetLanguage,
      },
    );
    if (cached) {
      return {
        translationId: cached._id as string,
        translation: cached.content,
        confidence: cached.confidence ?? 1,
        riskFlags: cached.riskFlags ?? [],
        glossaryNotes: [] as string[],
        source: cached.source,
        sourceLabel: cached.sourceLabel,
        aiModel: cached.aiModel,
        groundingUsed: cached.groundingUsed ?? false,
        citations: cached.citations ?? [],
        sourceReferenceUrl: cached.sourceReferenceUrl,
        cached: true,
      };
    }

    const userRow = await ctx.runQuery(internal.users.getByClerkId, {
      clerkId: identity.clerkId,
    });
    if (!userRow) {
      throw new Error(
        "User not found. Call users:ensureCurrentUser after sign-in first.",
      );
    }

    const canGenerate = await ctx.runQuery(internal.quotas.canGenerateAi, {
      userId: userRow._id,
    });
    if (!canGenerate) {
      throw new Error("AI_GENERATION_QUOTA_EXCEEDED");
    }

    const hadith = await loadHadith(ctx, args.hadithInternalId);
    if (!hadith) {
      throw new Error(
        "Hadith must be loaded in the reader before translation can be generated",
      );
    }

    const ai = gemini();
    const prompt = translationPrompt(hadith, args.targetLanguage);
    const response = await ai.models.generateContent({
      model: GEMINI_TRANSLATION_MODEL,
      contents: prompt,
      config: {
        temperature: 0.2,
        tools: [{ googleSearch: {} }],
      },
    });

    const rawText = response.text ?? "";
    let payload = parseTranslationPayload(rawText);
    if (!payload) {
      payload = await repairTranslationJson(ai, rawText);
    }

    const translation = (payload?.translation ?? rawText).trim();
    if (!translation) {
      throw new Error("Gemini returned an empty translation");
    }

    const citations = extractCitations(
      response.candidates?.[0]?.groundingMetadata?.groundingChunks,
    );
    const sourceReferenceUrl = deriveSourceReferenceUrl(hadith);

    await ctx.runMutation(internal.quotas.incrementAiGeneration, {
      userId: userRow._id,
    });

    const translationId = await ctx.runMutation(
      internal.translations.cacheGeminiTranslation,
      {
        hadithId: hadith._id,
        language: args.targetLanguage,
        content: translation,
        aiModel: GEMINI_TRANSLATION_MODEL,
        confidence: payload?.confidence ?? 0.5,
        riskFlags: payload?.riskFlags ?? [],
        generatedByUserId: userRow._id,
        groundingUsed: true,
        groundingSourceCount: citations.length,
        citations,
        sourceReferenceUrl,
      },
    );

    return {
      translationId,
      translation,
      confidence: payload?.confidence ?? 0.5,
      riskFlags: payload?.riskFlags ?? [],
      glossaryNotes: payload?.glossaryNotes ?? [],
      source: "gemini_ai" as const,
      sourceLabel: "AI",
      aiModel: GEMINI_TRANSLATION_MODEL,
      groundingUsed: true,
      citations,
      sourceReferenceUrl,
      cached: false,
    };
  },
});

type AiReview = {
  model: string;
  score: number;
  riskFlags: string[];
  missingMeaning?: string[];
  addedMeaning?: string[];
  glossaryIssues?: string[];
  recommendation:
    | "approve"
    | "admin_review"
    | "reject";
};

async function reviewWithGemini(
  hadith: HadithDoc,
  language: string,
  proposedContent: string,
): Promise<AiReview> {
  const ai = gemini();
  const prompt = [
    "You are reviewing a community translation of a hadith (Prophetic narration).",
    "Compare the proposal against the Arabic source and the English reference.",
    "Judge meaning fidelity, tone, and proper rendering of Islamic terms. Do not judge style preference.",
    "Be conservative: for religious text, uncertainty must escalate to human review.",
    'Respond with ONLY a single JSON object, no prose and no code fences, in exactly this shape: {"score": number between 0 and 1, "riskFlags": string[], "missingMeaning": string[], "addedMeaning": string[], "glossaryIssues": string[], "recommendation": "approve" | "admin_review" | "reject"}.',
    "",
    `Reference: ${hadith.referenceDisplay}`,
    `Narrator: ${hadith.narrator ?? "Unknown"}`,
    `Arabic: ${hadith.arabicText}`,
    `English source: ${hadith.englishText ?? ""}`,
    `Target language: ${language}`,
    `Proposal: ${proposedContent}`,
  ].join("\n");

  const response = await ai.models.generateContent({
    model: GEMINI_REVIEW_MODEL,
    contents: prompt,
    config: {
      temperature: 0.1,
      responseMimeType: "application/json",
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          score: { type: Type.NUMBER },
          riskFlags: { type: Type.ARRAY, items: { type: Type.STRING } },
          missingMeaning: { type: Type.ARRAY, items: { type: Type.STRING } },
          addedMeaning: { type: Type.ARRAY, items: { type: Type.STRING } },
          glossaryIssues: { type: Type.ARRAY, items: { type: Type.STRING } },
          recommendation: {
            type: Type.STRING,
            enum: [
              "approve",
              "admin_review",
              "reject",
            ],
          },
        },
        required: ["score", "riskFlags", "recommendation"],
      },
    },
  });

  try {
    const raw = JSON.parse(
      (extractObjectJson(response.text ?? "") ?? "{}") as string,
    ) as Partial<AiReview>;
    const recommendation = (
      ["approve", "admin_review", "reject"] as const
    ).includes(raw.recommendation as AiReview["recommendation"])
      ? (raw.recommendation as AiReview["recommendation"])
      : "admin_review";
    return {
      model: GEMINI_REVIEW_MODEL,
      score:
        typeof raw.score === "number"
          ? Math.max(0, Math.min(1, raw.score))
          : 0.5,
      riskFlags: raw.riskFlags ?? [],
      missingMeaning: raw.missingMeaning ?? [],
      addedMeaning: raw.addedMeaning ?? [],
      glossaryIssues: raw.glossaryIssues ?? [],
      recommendation,
    };
  } catch {
    return {
      model: GEMINI_REVIEW_MODEL,
      score: 0,
      riskFlags: ["review_parse_failed"],
      recommendation: "admin_review",
    };
  }
}

function extractObjectJson(raw: string): string | null {
  const text = raw.trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  return text.slice(start, end + 1);
}

/**
 * Requires a signed-in user. Runs the AI review and records the submission.
 * Rejected recommendations are stored as rejected; ambiguous ones queue for
 * human review. Nothing here is publicly ranked.
 */
export const submitTranslation = action({
  args: {
    hadithInternalId: v.string(),
    language: v.string(),
    proposedContent: v.string(),
    replacesTranslationId: v.optional(v.id("translations")),
  },
  handler: async (
    ctx,
    args,
  ): Promise<{ submissionId: string; aiReview: AiReview; status: string }> => {
    const identity = await requireIdentity(ctx);

    const userRow = await ctx.runQuery(internal.users.getByClerkId, {
      clerkId: identity.clerkId,
    });
    if (!userRow) {
      throw new Error(
        "User not found. Call users:ensureCurrentUser after sign-in first.",
      );
    }

    const hadith = await loadHadith(ctx, args.hadithInternalId);
    if (!hadith) {
      throw new Error("Unknown hadith for submission");
    }
    if (!args.proposedContent.trim()) {
      throw new Error("Translation proposal must not be empty");
    }
    const language = args.language.trim();
    if (!language) throw new Error("Translation language must not be empty");

    if (args.replacesTranslationId) {
      const replaced = await ctx.runQuery(internal.translations.getById, {
        translationId: args.replacesTranslationId,
      });
      if (
        !replaced ||
        replaced.hadithId !== hadith._id ||
        replaced.language !== language
      ) {
        throw new Error("Replacement translation does not match this hadith");
      }
    }

    const aiReview = await reviewWithGemini(
      hadith,
      language,
      args.proposedContent,
    );
    const status =
      aiReview.recommendation === "reject"
        ? ("rejected" as const)
        : aiReview.recommendation === "admin_review"
          ? ("needs_admin" as const)
          : ("pending" as const);

    const submissionId = await ctx.runMutation(
      internal.community.insertSubmission,
      {
        clerkId: identity.clerkId,
        hadithId: hadith._id,
        language,
        proposedContent: args.proposedContent.trim(),
        replacesTranslationId: args.replacesTranslationId,
        aiReview,
        status,
      },
    );

    return { submissionId, aiReview, status };
  },
});

/** Requires a signed-in user. Flags a translation for moderation review. */
export const reportTranslation = action({
  args: {
    translationId: v.id("translations"),
    reason: v.string(),
  },
  handler: async (ctx, args): Promise<{ ok: boolean }> => {
    const identity = await requireIdentity(ctx);
    const userRow = await ctx.runQuery(internal.users.getByClerkId, {
      clerkId: identity.clerkId,
    });
    const reason = args.reason.trim();
    if (!reason) throw new Error("Report reason must not be empty");
    const translation = await ctx.runQuery(internal.translations.getById, {
      translationId: args.translationId,
    });
    if (!translation) throw new Error("Translation not found");
    await ctx.runMutation(internal.community.insertReport, {
      translationId: args.translationId,
      reporterUserId: userRow?._id,
      reason,
    });
    return { ok: true };
  },
});
