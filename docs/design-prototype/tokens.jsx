// Design tokens — Hadithly · shadcn preset b2oE7c0Mi
// Zinc neutrals + green primary, Outfit type, small radius (~0.45rem)
// Three reader themes: light, dark, sepia (sepia stays for book mode)

const themes = {
  light: {
    // shadcn light — zinc neutrals + green primary
    bg: '#FFFFFF',                                  // background
    bgSubtle: 'oklch(0.985 0.001 286.375)',         // muted-ish
    surface: '#FFFFFF',                              // card
    surface2: 'oklch(0.967 0.001 286.375)',         // muted / accent / secondary
    text: 'oklch(0.141 0.005 285.823)',             // foreground
    textSec: 'oklch(0.552 0.016 285.938)',          // muted-foreground
    textTer: 'oklch(0.705 0.015 286.067)',          // ring / dimmed
    hair: 'oklch(0.92 0.004 286.32)',               // border / input
    accent: 'oklch(0.527 0.154 150.069)',           // primary (green)
    accentSoft: 'oklch(0.95 0.04 152)',             // tonal green
    accentText: 'oklch(0.448 0.119 151.328)',       // darker green for text
    primaryFg: 'oklch(0.982 0.018 155.826)',        // primary-foreground
    gold: 'oklch(0.66 0.13 78)',                    // rare gold detail
    success: 'oklch(0.627 0.194 149.214)',
    warning: 'oklch(0.7 0.16 75)',
    danger: 'oklch(0.577 0.245 27.325)',
    chart1: 'oklch(0.871 0.15 154.449)',
    chart2: 'oklch(0.723 0.219 149.579)',
    chart3: 'oklch(0.627 0.194 149.214)',
    chart4: 'oklch(0.527 0.154 150.069)',
    chart5: 'oklch(0.448 0.119 151.328)',
  },
  dark: {
    // shadcn dark
    bg: 'oklch(0.141 0.005 285.823)',
    bgSubtle: 'oklch(0.18 0.006 285)',
    surface: 'oklch(0.21 0.006 285.885)',           // card
    surface2: 'oklch(0.274 0.006 286.033)',         // muted / accent / secondary
    text: 'oklch(0.985 0 0)',                       // foreground
    textSec: 'oklch(0.705 0.015 286.067)',          // muted-foreground
    textTer: 'oklch(0.552 0.016 285.938)',
    hair: 'oklch(1 0 0 / 0.1)',                     // border
    accent: 'oklch(0.527 0.154 150.069)',           // primary green (kept punchy in dark)
    accentSoft: 'oklch(0.30 0.06 152)',             // tonal green dark
    accentText: 'oklch(0.723 0.219 149.579)',       // brighter for dark
    primaryFg: 'oklch(0.982 0.018 155.826)',
    gold: 'oklch(0.78 0.13 80)',
    success: 'oklch(0.723 0.219 149.579)',
    warning: 'oklch(0.78 0.15 75)',
    danger: 'oklch(0.704 0.191 22.216)',
    chart1: 'oklch(0.871 0.15 154.449)',
    chart2: 'oklch(0.723 0.219 149.579)',
    chart3: 'oklch(0.627 0.194 149.214)',
    chart4: 'oklch(0.527 0.154 150.069)',
    chart5: 'oklch(0.448 0.119 151.328)',
  },
  sepia: {
    bg: '#F4ECD8',
    bgSubtle: '#EDE3CB',
    surface: '#FAF2DE',
    surface2: '#EDE3CB',
    text: '#241D13',
    textSec: '#8A7B63',
    textTer: '#A89A82',
    hair: '#D8C8A5',
    accent: 'oklch(0.527 0.154 150.069)',
    accentSoft: '#E8D9B5',
    accentText: 'oklch(0.448 0.119 151.328)',
    primaryFg: '#FAF2DE',
    gold: '#B8893B',
    success: 'oklch(0.527 0.154 150.069)',
    warning: '#B7791F',
    danger: '#A22D2D',
  },
};

const RADIUS = {
  sm: 5,     // ~0.3rem
  md: 7,     // ~0.45rem (shadcn --radius)
  lg: 10,    // ~0.65rem
  xl: 14,    // ~0.9rem
  pill: 999,
};

const PHONE = { w: 390, h: 844, radius: 54 };
const ANDROID = { w: 390, h: 844, radius: 32 };

Object.assign(window, { themes, PHONE, ANDROID, RADIUS });
