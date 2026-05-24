import { z } from "zod";

export const generateTranslationRequestSchema = z.object({
  hadithId: z.string().min(1),
  targetLanguage: z.string().min(2),
  sourceLanguage: z.string().default("en")
});

export const geminiTranslationResponseSchema = z.object({
  translation: z.string().min(1),
  confidence: z.number().min(0).max(1),
  riskFlags: z.array(z.string()).default([]),
  glossaryNotes: z.array(z.string()).default([])
});

export const translationVoteSchema = z.object({
  translationId: z.string().min(1),
  vote: z.enum(["up", "down"]),
  reason: z
    .enum(["meaning", "language", "missing_nuance", "grammar", "inappropriate", "other"])
    .optional()
});

export type GenerateTranslationRequest = z.infer<typeof generateTranslationRequestSchema>;
export type GeminiTranslationResponse = z.infer<typeof geminiTranslationResponseSchema>;
