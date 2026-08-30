/**
 * Gemini grounding helpers, ported from legacy apps/web/lib/translation-grounding.
 *
 * Gemini's Google Search grounding tool cannot be combined with structured
 * JSON output (responseSchema), so the model returns an inline JSON object
 * and we parse it defensively here.
 */

export type Citation = {
  url: string;
  title?: string;
  domain?: string;
};

export type TranslationPayload = {
  translation: string;
  confidence: number;
  riskFlags: string[];
  glossaryNotes: string[];
};

export function extractTranslationJson(raw: string): string | null {
  if (!raw) return null;
  let text = raw.trim();
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence?.[1]) text = fence[1].trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  return text.slice(start, end + 1);
}

export function parseTranslationPayload(raw: string): TranslationPayload | null {
  const json = extractTranslationJson(raw);
  if (!json) return null;
  try {
    const parsed = JSON.parse(json) as Partial<TranslationPayload>;
    if (typeof parsed.translation !== "string") return null;
    const confidence =
      typeof parsed.confidence === "number"
        ? Math.min(1, Math.max(0, parsed.confidence))
        : 0.5;
    return {
      translation: parsed.translation,
      confidence,
      riskFlags: stringArray(parsed.riskFlags),
      glossaryNotes: stringArray(parsed.glossaryNotes),
    };
  } catch {
    return null;
  }
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

type GroundingChunkLike = {
  web?: { uri?: string | null; title?: string | null } | null;
};

function domainOf(url: string): string | undefined {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return undefined;
  }
}

export function extractCitations(
  chunks: GroundingChunkLike[] | undefined | null,
): Citation[] {
  if (!chunks?.length) return [];
  const seen = new Set<string>();
  const citations: Citation[] = [];
  for (const chunk of chunks) {
    const url = chunk.web?.uri?.trim();
    if (!url || seen.has(url)) continue;
    seen.add(url);
    citations.push({
      url,
      title: chunk.web?.title?.trim() || undefined,
      domain: domainOf(url),
    });
  }
  return citations;
}

function lastNumber(value?: string | null): string | undefined {
  if (!value) return undefined;
  const matches = value.match(/\d+/g);
  return matches ? matches[matches.length - 1] : undefined;
}

/**
 * Best-effort canonical hadith URL, used as the "source link" when grounding
 * returns no usable citations. sunnah.com accepts `collection:number` paths.
 */
export function deriveSourceReferenceUrl(input: {
  collectionSlug?: string;
  providerHadithId?: string;
  referenceDisplay?: string;
}): string | undefined {
  const slug = input.collectionSlug?.trim();
  if (!slug) return undefined;
  const num =
    lastNumber(input.providerHadithId) ?? lastNumber(input.referenceDisplay);
  if (!num) return undefined;
  return `https://sunnah.com/${slug}:${num}`;
}
