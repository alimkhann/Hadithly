import { localeFallbackChain } from "./preferences";

// Draft UI copy. Approval is tracked with the L1 native copy, not corpus rights.
const aiTranslationLabels: Readonly<Record<string, string>> = {
  en: "AI translation",
  ar: "ترجمة بالذكاء الاصطناعي",
  ru: "Перевод ИИ",
  kk: "ЖИ аудармасы",
  ky: "ЖИ котормосу",
  uz: "Sun’iy intellekt tarjimasi",
  tr: "Yapay zekâ çevirisi",
  id: "Terjemahan AI",
  ur: "مصنوعی ذہانت کا ترجمہ",
  fr: "Traduction par IA",
  "es-419": "Traducción con IA",
  "pt-BR": "Tradução por IA",
  sw: "Tafsiri ya AI",
  hi: "एआई अनुवाद",
  bn: "এআই অনুবাদ",
};

export function notificationAITranslationLabel(locale: string): string {
  for (const candidate of localeFallbackChain(locale)) {
    const label = aiTranslationLabels[candidate];
    if (label !== undefined) return label;
  }
  return "AI translation";
}
