import { useCallback, useEffect, useState } from "react";

export type ReaderThemeName = "light" | "sepia" | "dark";

export type ReaderPrefs = {
  theme: ReaderThemeName;
  fontScale: number;
};

export const DEFAULT_READER_PREFS: ReaderPrefs = {
  theme: "sepia",
  fontScale: 1,
};

export const MIN_FONT_SCALE = 0.85;
export const MAX_FONT_SCALE = 1.4;
export const FONT_SCALE_STEP = 0.05;

const STORAGE_KEY = "hadithly:reader-prefs:v1";

export function clampFontScale(value: number) {
  const rounded = Math.round(value * 100) / 100;
  return Math.min(MAX_FONT_SCALE, Math.max(MIN_FONT_SCALE, rounded));
}

export function nextFontScale(current: number, direction: "up" | "down") {
  return clampFontScale(
    current + (direction === "up" ? FONT_SCALE_STEP : -FONT_SCALE_STEP),
  );
}

export function mergeReaderPrefs(
  current: ReaderPrefs,
  next: Partial<ReaderPrefs>,
): ReaderPrefs {
  const merged = { ...current, ...next };
  return { theme: merged.theme, fontScale: clampFontScale(merged.fontScale) };
}

export function useReaderPreferences() {
  const [prefs, setPrefs] = useState<ReaderPrefs>(DEFAULT_READER_PREFS);

  useEffect(() => {
    let active = true;
    loadReaderPrefs().then((next) => {
      if (active) setPrefs(next);
    });
    return () => {
      active = false;
    };
  }, []);

  const update = useCallback(async (next: Partial<ReaderPrefs>) => {
    setPrefs((current) => {
      const merged = mergeReaderPrefs(current, next);
      void saveReaderPrefs(merged);
      return merged;
    });
  }, []);

  return { prefs, update };
}

async function loadReaderPrefs(): Promise<ReaderPrefs> {
  try {
    const raw = await (await storage()).getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_READER_PREFS;
    return mergeReaderPrefs(
      DEFAULT_READER_PREFS,
      JSON.parse(raw) as Partial<ReaderPrefs>,
    );
  } catch {
    return DEFAULT_READER_PREFS;
  }
}

async function saveReaderPrefs(prefs: ReaderPrefs) {
  try {
    await (await storage()).setItem(STORAGE_KEY, JSON.stringify(prefs));
  } catch {
    // ignore persistence failures; preferences stay in-memory
  }
}

async function storage() {
  const module = await import("@react-native-async-storage/async-storage");
  return module.default;
}
