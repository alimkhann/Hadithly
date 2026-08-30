import { I18n } from "i18n-js";

export const uiTranslations = {
  en: {
    begin: "Begin",
    continue: "Continue",
    continueAsGuest: "Continue as guest",
    continueWithApple: "Continue with Apple",
    continueWithEmail: "Continue with email",
    continueWithGoogle: "Continue with Google",
    email: "Email",
    password: "Password",
    readerLanguageTitle: "Choose your\nreading language",
    signInToSync: "Sign in to sync",
    verifyEmail: "Verify email",
  },
  ru: {
    begin: "Начать",
    continue: "Продолжить",
    continueAsGuest: "Продолжить как гость",
    continueWithApple: "Войти через Apple",
    continueWithEmail: "Войти по email",
    continueWithGoogle: "Войти через Google",
    email: "Email",
    password: "Пароль",
    readerLanguageTitle: "Выберите язык\nчтения",
    signInToSync: "Войдите для синхронизации",
    verifyEmail: "Подтвердите email",
  },
  kk: {
    begin: "Бастау",
    continue: "Жалғастыру",
    continueAsGuest: "Қонақ ретінде жалғастыру",
    continueWithApple: "Apple арқылы кіру",
    continueWithEmail: "Email арқылы кіру",
    continueWithGoogle: "Google арқылы кіру",
    email: "Email",
    password: "Құпиясөз",
    readerLanguageTitle: "Оқу тілін\nтаңдаңыз",
    signInToSync: "Синхрондау үшін кіріңіз",
    verifyEmail: "Email-ды растаңыз",
  },
} as const;

export type UiLanguage = keyof typeof uiTranslations;

export function createI18n(language: string) {
  const i18n = new I18n(uiTranslations);
  i18n.locale = isUiLanguage(language) ? language : "en";
  i18n.enableFallback = true;
  return i18n;
}

export function translateUi(language: string, key: keyof typeof uiTranslations.en) {
  return createI18n(language).t(key);
}

function isUiLanguage(language: string): language is UiLanguage {
  return language === "en" || language === "ru" || language === "kk";
}
