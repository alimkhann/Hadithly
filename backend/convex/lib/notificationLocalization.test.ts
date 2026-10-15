import { expect, test } from "vitest";
import { buildNotificationPayload } from "./notifyContent";
import { notificationAITranslationLabel } from "./notificationLocalization";

test("Wave 1 push bodies label AI without changing the target or content locale", () => {
  const locales = ["en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn"];
  for (const language of locales) {
    const payload = buildNotificationPayload({
      collectionName: "Collection",
      referenceDisplay: "Reference 1",
      translation: { text: "Original selected translation", language, isAI: true },
      hadithId: "h1", collectionSlug: "bukhari", providerHadithId: "1", volumeId: "2",
    });
    expect(payload.body).toBe(`Original selected translation\n— ${notificationAITranslationLabel(language)}`);
    expect(payload.data).toMatchObject({ locale: language, ai: "1", providerHadithId: "1", volumeId: "2" });
    if (language !== "en") expect(payload.body).not.toContain("AI translation");
    const source = buildNotificationPayload({
      collectionName: "Collection", referenceDisplay: "Reference 1",
      translation: { text: "Original selected translation", language, isAI: false },
      hadithId: "h1", collectionSlug: "bukhari", providerHadithId: "1",
    });
    expect(source.body).toBe("Original selected translation");
    expect(source.data.ai).toBe("0");
  }
});

test("AI notice uses exact, base and English UI fallback", () => {
  expect(notificationAITranslationLabel("ar-EG")).toBe("ترجمة بالذكاء الاصطناعي");
  expect(notificationAITranslationLabel("RU_ru")).toBe("Перевод ИИ");
  expect(notificationAITranslationLabel("pt-BR")).toBe("Tradução por IA");
  expect(notificationAITranslationLabel("pt-PT")).toBe("AI translation");
  expect(notificationAITranslationLabel("invalid locale")).toBe("AI translation");
});
