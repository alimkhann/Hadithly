import { describe, expect, it } from "vitest";

import {
  DEFAULT_ONBOARDING_STATE,
  derivePreferredLanguage,
  isOnboardingComplete,
  loadOnboardingState,
  mergeOnboardingState,
} from "./onboarding";

describe("onboarding state", () => {
  it("starts as an English guest profile with onboarding incomplete", () => {
    expect(DEFAULT_ONBOARDING_STATE).toMatchObject({
      preferredLanguage: "en",
      authMode: "guest",
      onboardingComplete: false,
      notificationsEnabled: false,
    });
  });

  it("only treats onboarding as complete after language, auth mode, and completion are set", () => {
    expect(
      isOnboardingComplete({
        ...DEFAULT_ONBOARDING_STATE,
        preferredLanguage: "ru",
        authMode: "guest",
        onboardingComplete: true,
      }),
    ).toBe(true);

    expect(
      isOnboardingComplete({
        ...DEFAULT_ONBOARDING_STATE,
        preferredLanguage: "",
        authMode: "guest",
        onboardingComplete: true,
      }),
    ).toBe(false);
  });

  it("merges partial updates without dropping existing selections", () => {
    expect(
      mergeOnboardingState(
        {
          ...DEFAULT_ONBOARDING_STATE,
          preferredLanguage: "kk",
          notificationsEnabled: true,
        },
        { authMode: "signed-in", onboardingComplete: true },
      ),
    ).toMatchObject({
      preferredLanguage: "kk",
      notificationsEnabled: true,
      authMode: "signed-in",
      onboardingComplete: true,
    });
  });

  it("derives the first preferred language from the phone locale when supported", () => {
    expect(derivePreferredLanguage([{ languageCode: "ru" }])).toBe("ru");
    expect(derivePreferredLanguage([{ languageCode: "kk" }])).toBe("kk");
    expect(derivePreferredLanguage([{ languageCode: "de" }])).toBe("en");
    expect(derivePreferredLanguage([])).toBe("en");
  });

  it("uses phone locale only when no saved onboarding state exists", async () => {
    const emptyStorage = {
      getItem: async () => null,
      setItem: async () => undefined,
    };
    await expect(
      loadOnboardingState(emptyStorage, [{ languageCode: "ru" }]),
    ).resolves.toMatchObject({ preferredLanguage: "ru" });

    const savedStorage = {
      getItem: async () =>
        JSON.stringify({ preferredLanguage: "kk", onboardingComplete: true }),
      setItem: async () => undefined,
    };
    await expect(
      loadOnboardingState(savedStorage, [{ languageCode: "ru" }]),
    ).resolves.toMatchObject({ preferredLanguage: "kk" });
  });
});
