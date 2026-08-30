import { GoogleGenAI, Type } from "@google/genai";
import { generateTranslationRequestSchema } from "@hadithly/validators";

import {
  cacheGeminiTranslation,
  cacheHadithPage,
  canGenerateAiForUser,
  findCachedHadithByInternalId,
  getCachedTranslation,
  incrementAiGenerationForUser,
  parseInternalHadithId,
  upsertApiUser,
} from "@/lib/convex-server";
import { getHadithProvider, jsonError } from "@/lib/hadith-provider";
import { requireClerkAuth } from "@/lib/route-auth";
import {
  deriveSourceReferenceUrl,
  extractCitations,
  parseTranslationPayload,
} from "@/lib/translation-grounding";

const GEMINI_TRANSLATION_MODEL = "gemini-2.5-flash-lite";

export async function POST(request: Request) {
  const parsed = generateTranslationRequestSchema.safeParse(
    await request.json().catch(() => null),
  );
  if (!parsed.success) {
    return jsonError("Invalid translation request", 400);
  }

  const cached = await getCachedTranslation(
    parsed.data.hadithId,
    parsed.data.targetLanguage,
  );
  if (cached) {
    return Response.json({
      translation: cached.content,
      confidence: cached.confidence ?? 1,
      riskFlags: cached.riskFlags ?? [],
      glossaryNotes: [],
      source: cached.source,
      sourceLabel: cached.sourceLabel,
      aiModel: cached.aiModel,
      ratingPercent: cached.ratingPercent,
      groundingUsed: cached.groundingUsed ?? false,
      citations: cached.citations ?? [],
      sourceReferenceUrl: cached.sourceReferenceUrl,
      cached: true,
    });
  }

  const auth = await requireClerkAuth(request);
  if (!auth.ok) return auth.response;

  const userId = await upsertApiUser({ clerkId: auth.clerkId });
  if (!userId) {
    return jsonError("Convex is required for AI quota enforcement", 503);
  }

  const canGenerate = await canGenerateAiForUser(userId);
  if (!canGenerate) {
    return jsonError("AI generation quota exceeded", 402);
  }

  if (!process.env.GEMINI_API_KEY) {
    return jsonError("GEMINI_API_KEY is not configured", 503);
  }

  const hadith = await getOrWarmHadith(parsed.data.hadithId);
  if (!hadith) {
    return jsonError(
      "Hadith must be loaded in the reader before translation can be generated",
      404,
    );
  }

  const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
  // Grounding (Google Search) is always on, per product requirement, so the
  // translation can be verified against and attributed to real sources.
  // Grounding is incompatible with structured JSON output, so the model is
  // asked for inline JSON and parsed defensively below.
  const prompt = [
    "You are a careful translator of hadith (Prophetic narrations).",
    `Translate the hadith faithfully into the target language (${parsed.data.targetLanguage}).`,
    "Preserve religious meaning and tone. Do not issue legal rulings (fatwa).",
    "Use Google Search to verify narrator names, proper nouns, and the established rendering of key Islamic terms.",
    'Respond with ONLY a single JSON object, no prose and no code fences, in exactly this shape: {"translation": string, "confidence": number between 0 and 1, "riskFlags": string[], "glossaryNotes": string[]}.',
    "",
    `Reference: ${hadith.referenceDisplay}`,
    `Narrator: ${hadith.narrator ?? "Unknown"}`,
    `Arabic: ${hadith.arabicText}`,
    `English source: ${hadith.englishText ?? ""}`,
  ].join("\n");

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
    return jsonError("Gemini returned an empty translation", 502);
  }

  const citations = extractCitations(
    response.candidates?.[0]?.groundingMetadata?.groundingChunks,
  );
  const sourceReferenceUrl = deriveSourceReferenceUrl(hadith);
  const confidence = payload?.confidence ?? 0.5;
  const riskFlags = payload?.riskFlags ?? [];
  const glossaryNotes = payload?.glossaryNotes ?? [];

  await incrementAiGenerationForUser(userId);

  await cacheGeminiTranslation({
    hadithId: parsed.data.hadithId,
    language: parsed.data.targetLanguage,
    content: translation,
    aiModel: GEMINI_TRANSLATION_MODEL,
    confidence,
    riskFlags,
    groundingUsed: true,
    groundingSourceCount: citations.length,
    citations,
    sourceReferenceUrl,
  });

  return Response.json({
    translation,
    confidence,
    riskFlags,
    glossaryNotes,
    source: "gemini_ai",
    sourceLabel: "Gemini AI",
    aiModel: GEMINI_TRANSLATION_MODEL,
    ratingPercent: 100,
    groundingUsed: true,
    citations,
    sourceReferenceUrl,
    cached: false,
  });
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

async function getOrWarmHadith(internalHadithId: string) {
  const cached = await findCachedHadithByInternalId(internalHadithId);
  if (cached) return cached;

  const ref = parseInternalHadithId(internalHadithId);
  if (!ref) return null;

  const firstPage = await getHadithProvider().listHadiths({
    collectionSlug: ref.collectionSlug,
    page: 1,
    pageSize: 50,
  });
  await cacheHadithPage(firstPage.items);
  return (
    firstPage.items.find(
      (item) => item.providerHadithId === ref.providerHadithId,
    ) ?? null
  );
}
