import { describe, expect, it } from "vitest";

import {
  clampFontScale,
  mergeReaderPrefs,
  MAX_FONT_SCALE,
  MIN_FONT_SCALE,
  nextFontScale,
  DEFAULT_READER_PREFS,
} from "./reader-prefs";

describe("clampFontScale", () => {
  it("clamps below the minimum and above the maximum", () => {
    expect(clampFontScale(0.1)).toBe(MIN_FONT_SCALE);
    expect(clampFontScale(99)).toBe(MAX_FONT_SCALE);
  });

  it("keeps values inside the range", () => {
    expect(clampFontScale(1)).toBe(1);
  });
});

describe("nextFontScale", () => {
  it("steps up and down within bounds", () => {
    expect(nextFontScale(1, "up")).toBeGreaterThan(1);
    expect(nextFontScale(1, "down")).toBeLessThan(1);
    expect(nextFontScale(MAX_FONT_SCALE, "up")).toBe(MAX_FONT_SCALE);
    expect(nextFontScale(MIN_FONT_SCALE, "down")).toBe(MIN_FONT_SCALE);
  });
});

describe("mergeReaderPrefs", () => {
  it("merges and clamps the font scale", () => {
    expect(mergeReaderPrefs(DEFAULT_READER_PREFS, { theme: "dark" })).toEqual({
      theme: "dark",
      fontScale: 1,
    });
    expect(mergeReaderPrefs(DEFAULT_READER_PREFS, { fontScale: 99 }).fontScale).toBe(
      MAX_FONT_SCALE,
    );
  });
});
