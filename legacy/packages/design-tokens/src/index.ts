export const themes = {
  light: {
    bg: "#FFFFFF",
    bgSubtle: "#FAFAFA",
    surface: "#FFFFFF",
    surface2: "#F4F4F5",
    text: "#18181B",
    textSec: "#71717A",
    textTer: "#A1A1AA",
    hair: "#E4E4E7",
    accent: "#168A4A",
    accentSoft: "#E8F8EF",
    accentText: "#116735",
    gold: "#B8893B",
    danger: "#DC2626"
  },
  dark: {
    bg: "#18181B",
    bgSubtle: "#202024",
    surface: "#27272A",
    surface2: "#3F3F46",
    text: "#FAFAFA",
    textSec: "#A1A1AA",
    textTer: "#71717A",
    hair: "rgba(255,255,255,0.12)",
    accent: "#168A4A",
    accentSoft: "#173C29",
    accentText: "#4ADE80",
    gold: "#D1A34E",
    danger: "#F87171"
  },
  sepia: {
    bg: "#F4ECD8",
    bgSubtle: "#EDE3CB",
    surface: "#FAF2DE",
    surface2: "#EDE3CB",
    text: "#241D13",
    textSec: "#8A7B63",
    textTer: "#A89A82",
    hair: "#D8C8A5",
    accent: "#168A4A",
    accentSoft: "#E8D9B5",
    accentText: "#116735",
    gold: "#B8893B",
    danger: "#A22D2D"
  }
} as const;

export const radius = {
  sm: 5,
  md: 7,
  lg: 10,
  xl: 14,
  pill: 999
} as const;

export const typography = {
  ui: "Outfit",
  arabic: "Amiri Quran",
  readerSerif: "Literata"
} as const;
