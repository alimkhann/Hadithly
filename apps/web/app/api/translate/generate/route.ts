import { GoogleGenAI, Type } from "@google/genai";
import {
  generateTranslationRequestSchema,
  geminiTranslationResponseSchema,
} from "@hadithly/validators";

import {
  cacheGeminiTranslation,
  cacheHadithPage,
  findCachedHadithByInternalId,
  getCachedTranslation,
  parseInternalHadithId,
} from "@/lib/convex-server";
import { getHadithProvider, jsonError } from "@/lib/hadith-provider";

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
      cached: true,
    });
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
  const response = await ai.models.generateContent({
    model: GEMINI_TRANSLATION_MODEL,
    contents: [
      "Translate this hadith faithfully. Preserve religious meaning, avoid legal rulings, and return only the structured fields.",
      `Target language: ${parsed.data.targetLanguage}`,
      `Reference: ${hadith.referenceDisplay}`,
      `Narrator: ${hadith.narrator ?? "Unknown"}`,
      `Arabic: ${hadith.arabicText}`,
      `English source: ${hadith.englishText ?? ""}`,
    ].join("\n\n"),
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

  const text = response.text ?? "{}";
  const validated = geminiTranslationResponseSchema.safeParse(JSON.parse(text));
  if (!validated.success) {
    return jsonError("Gemini returned invalid translation JSON", 502);
  }

  await cacheGeminiTranslation({
    hadithId: parsed.data.hadithId,
    language: parsed.data.targetLanguage,
    content: validated.data.translation,
    aiModel: GEMINI_TRANSLATION_MODEL,
    confidence: validated.data.confidence,
    riskFlags: validated.data.riskFlags,
  });

  return Response.json({
    ...validated.data,
    source: "gemini_ai",
    sourceLabel: "Gemini AI",
    cached: false,
  });
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
