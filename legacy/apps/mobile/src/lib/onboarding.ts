import { useCallback, useEffect, useState } from "react";

export type AuthMode = "guest" | "signed-in";
export type DeviceLocale = { languageCode?: string | null };

export type OnboardingState = {
  preferredLanguage: string;
  notificationsEnabled: boolean;
  notificationTime: string;
  authMode: AuthMode;
  onboardingComplete: boolean;
  completedAt?: number;
};

type PersistedStorage = {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
};

const STORAGE_KEY = "hadithly:onboarding:v1";

export const DEFAULT_ONBOARDING_STATE: OnboardingState = {
  preferredLanguage: "en",
  notificationsEnabled: false,
  notificationTime: "07:30",
  authMode: "guest",
  onboardingComplete: false,
};

export const SUPPORTED_LANGUAGES = [
  { code: "en", title: "English", native: "English", status: "Official" },
  { code: "ar", title: "Arabic", native: "العربية", status: "Source" },
  { code: "kk", title: "Kazakh", native: "Қазақша", status: "AI/community" },
  { code: "ru", title: "Russian", native: "Русский", status: "AI/community" },
  { code: "tr", title: "Turkish", native: "Türkçe", status: "AI/community" },
  { code: "uz", title: "Uzbek", native: "O'zbekcha", status: "AI/community" },
  {
    code: "id",
    title: "Indonesian",
    native: "Bahasa Indonesia",
    status: "AI/community",
  },
  { code: "ur", title: "Urdu", native: "اُردُو", status: "AI/community" },
] as const;

export function mergeOnboardingState(
  current: OnboardingState,
  next: Partial<OnboardingState>,
): OnboardingState {
  return { ...current, ...next };
}

export function isOnboardingComplete(state: OnboardingState) {
  return Boolean(
    state.onboardingComplete &&
      state.preferredLanguage.trim() &&
      state.authMode,
  );
}

export function derivePreferredLanguage(locales: DeviceLocale[] = []) {
  const supported = new Set<string>(SUPPORTED_LANGUAGES.map((language) => language.code));
  for (const locale of locales) {
    const languageCode = locale.languageCode?.toLowerCase();
    if (languageCode && supported.has(languageCode)) return languageCode;
  }
  return "en";
}

export async function loadOnboardingState(
  storage = getAsyncStorage(),
  deviceLocales?: DeviceLocale[],
) {
  const saved = await storage.getItem(STORAGE_KEY);
  if (!saved) {
    return {
      ...DEFAULT_ONBOARDING_STATE,
      preferredLanguage: derivePreferredLanguage(
        deviceLocales ?? getDeviceLocales(),
      ),
    };
  }
  try {
    return mergeOnboardingState(
      DEFAULT_ONBOARDING_STATE,
      JSON.parse(saved) as Partial<OnboardingState>,
    );
  } catch {
    return {
      ...DEFAULT_ONBOARDING_STATE,
      preferredLanguage: derivePreferredLanguage(
        deviceLocales ?? getDeviceLocales(),
      ),
    };
  }
}

function getDeviceLocales(): DeviceLocale[] {
  try {
    const requireFn = Function("return typeof require === 'function' ? require : undefined")() as
      | undefined
      | ((id: string) => { getLocales?: () => DeviceLocale[] });
    return requireFn?.("expo-localization").getLocales?.() ?? [];
  } catch {
    return [];
  }
}

export async function saveOnboardingState(
  state: OnboardingState,
  storage = getAsyncStorage(),
) {
  await storage.setItem(STORAGE_KEY, JSON.stringify(state));
}

export function useOnboardingState() {
  const [state, setState] = useState<OnboardingState>(
    DEFAULT_ONBOARDING_STATE,
  );
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let active = true;
    loadOnboardingState()
      .then((next) => {
        if (active) setState(next);
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const update = useCallback(
    async (next: Partial<OnboardingState>) => {
      const merged = mergeOnboardingState(state, next);
      setState(merged);
      await saveOnboardingState(merged);
      return merged;
    },
    [state],
  );

  return { state, isLoading, update };
}

function getAsyncStorage(): PersistedStorage {
  return {
    async getItem(key) {
      const module = await import("@react-native-async-storage/async-storage");
      return module.default.getItem(key);
    },
    async setItem(key, value) {
      const module = await import("@react-native-async-storage/async-storage");
      await module.default.setItem(key, value);
    },
  };
}
