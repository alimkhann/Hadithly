// Hadithly components — shadcn preset b2oE7c0Mi · green primary · Outfit
// Phone/Android frames, status bar, chips, buttons, sheets, hadith block,
// icons, tab bar, the logo, etc.

const { useState, useEffect, useRef, useMemo } = React;

// ──────── ICONS — Hugeicons-style stroke set ────────
const Icon = ({ name, size = 18, color = 'currentColor', strokeWidth = 1.6, style }) => {
  const s = { width: size, height: size, display: 'inline-block', verticalAlign: 'middle', flexShrink: 0, ...style };
  const c = { fill: 'none', stroke: color, strokeWidth, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const paths = {
    home: <><path d="M3 11l9-7 9 7v9a2 2 0 0 1-2 2h-4v-7H9v7H5a2 2 0 0 1-2-2z" {...c} /></>,
    book: <><path d="M4 4h7a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H4z" {...c} /><path d="M20 4h-3a3 3 0 0 0-3 3v13" {...c} /></>,
    bookOpen: <><path d="M3 6c3-1 6-1 9 1 3-2 6-2 9-1v13c-3-1-6-1-9 1-3-2-6-2-9-1z" {...c} /><path d="M12 7v13" {...c} /></>,
    community: <><circle cx="9" cy="8" r="3" {...c} /><path d="M2 20c0-3 3-5 7-5s7 2 7 5" {...c} /><circle cx="17" cy="9" r="2.5" {...c} /><path d="M14 14c4 0 8 1.5 8 4.5" {...c} /></>,
    user: <><circle cx="12" cy="8" r="4" {...c} /><path d="M3 21c1.5-4 5-6 9-6s7.5 2 9 6" {...c} /></>,
    search: <><circle cx="11" cy="11" r="6.5" {...c} /><path d="M16.5 16.5l4 4" {...c} /></>,
    bookmark: <><path d="M6 3h12v18l-6-4-6 4z" {...c} /></>,
    bookmarkFill: <path d="M6 3h12v18l-6-4-6 4z" fill={color} stroke={color} strokeWidth="1.5" strokeLinejoin="round" />,
    heart: <><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z" {...c} /></>,
    heartFill: <path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z" fill={color} stroke={color} strokeLinejoin="round" />,
    note: <><path d="M5 4h11l4 4v12H5z" {...c} /><path d="M9 12h6M9 16h4" {...c} /></>,
    menu: <><path d="M4 7h16M4 12h16M4 17h10" {...c} /></>,
    menuDots: <><circle cx="6" cy="12" r="1.5" fill={color} /><circle cx="12" cy="12" r="1.5" fill={color} /><circle cx="18" cy="12" r="1.5" fill={color} /></>,
    close: <><path d="M6 6l12 12M18 6L6 18" {...c} /></>,
    chevronR: <><path d="M9 6l6 6-6 6" {...c} /></>,
    chevronL: <><path d="M15 6l-6 6 6 6" {...c} /></>,
    chevronD: <><path d="M6 9l6 6 6-6" {...c} /></>,
    chevronU: <><path d="M6 15l6-6 6 6" {...c} /></>,
    arrowUp: <><path d="M12 5v14M6 11l6-6 6 6" {...c} /></>,
    arrowDown: <><path d="M12 5v14M6 13l6 6 6-6" {...c} /></>,
    arrowR: <><path d="M5 12h14M13 6l6 6-6 6" {...c} /></>,
    thumbUp: <><path d="M7 11v9H5a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2zM7 11l4-7c1.5 0 3 1 3 3v3h5a2 2 0 0 1 2 2.4l-1.4 6A2 2 0 0 1 17.6 20H7" {...c} /></>,
    thumbDown: <><path d="M17 13V4h2a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2zM17 13l-4 7c-1.5 0-3-1-3-3v-3H5a2 2 0 0 1-2-2.4l1.4-6A2 2 0 0 1 6.4 4H17" {...c} /></>,
    check: <><path d="M5 12l5 5L20 7" {...c} /></>,
    plus: <><path d="M12 5v14M5 12h14" {...c} /></>,
    minus: <><path d="M5 12h14" {...c} /></>,
    sparkle: <><path d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5z" {...c} /><path d="M19 16l.6 1.4L21 18l-1.4.6L19 20l-.6-1.4L17 18l1.4-.6z" {...c} /></>,
    bell: <><path d="M6 9a6 6 0 1 1 12 0c0 5 2 6 2 8H4c0-2 2-3 2-8z" {...c} /><path d="M10 21a2 2 0 0 0 4 0" {...c} /></>,
    bellDot: <><path d="M6 9a6 6 0 1 1 12 0c0 5 2 6 2 8H4c0-2 2-3 2-8z" {...c} /><path d="M10 21a2 2 0 0 0 4 0" {...c} /><circle cx="18" cy="6" r="3" fill={color} stroke="none" /></>,
    moon: <><path d="M20 14A8 8 0 0 1 10 4a8 8 0 1 0 10 10z" {...c} /></>,
    sun: <><circle cx="12" cy="12" r="4" {...c} /><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4" {...c} /></>,
    type: <><path d="M4 6V4h16v2M9 20h6M12 4v16" {...c} /></>,
    sliders: <><path d="M4 6h7M15 6h5M4 12h3M11 12h9M4 18h11M19 18h1" {...c} /><circle cx="13" cy="6" r="2" {...c} /><circle cx="9" cy="12" r="2" {...c} /><circle cx="17" cy="18" r="2" {...c} /></>,
    shield: <><path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z" {...c} /><path d="M9 12l2 2 4-4" {...c} /></>,
    flag: <><path d="M5 4v17M5 4h12l-2 3 2 3H5" {...c} /></>,
    share: <><circle cx="18" cy="5" r="3" {...c} /><circle cx="6" cy="12" r="3" {...c} /><circle cx="18" cy="19" r="3" {...c} /><path d="M8.6 10.5l6.8-4M8.6 13.5l6.8 4" {...c} /></>,
    copy: <><rect x="8" y="8" width="12" height="12" rx="2" {...c} /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" {...c} /></>,
    headphones: <><path d="M4 14v-2a8 8 0 1 1 16 0v2M4 14a2 2 0 0 1 2-2h1v6H6a2 2 0 0 1-2-2zM20 14a2 2 0 0 0-2-2h-1v6h1a2 2 0 0 0 2-2z" {...c} /></>,
    apple: <><path d="M16.5 12.5c0-2.5 2-3.6 2-3.6-1-1.5-2.7-1.7-3.3-1.7-1.4-.1-2.7.8-3.4.8-.7 0-1.8-.8-3-.8-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 3 2.3 1.2-.1 1.6-.8 3.1-.8 1.4 0 1.8.8 3.1.7 1.3 0 2.1-1.1 2.9-2.3.6-.8 1.1-1.7 1.4-2.6-2.3-.9-2.2-3.5-2.2-3.6z M14.4 5c.7-.8 1.1-1.9 1-3-.9.1-2.1.6-2.7 1.4-.6.7-1.2 1.8-1 2.9 1 0 2-.5 2.7-1.3z" fill={color} /></>,
    google: <><path d="M21.4 12.2c0-.7-.1-1.4-.2-2H12v3.8h5.3c-.2 1.2-.9 2.2-2 2.9v2.4h3.2c1.9-1.7 2.9-4.2 2.9-7.1z" fill="#4285F4" /><path d="M12 21.5c2.7 0 5-.9 6.6-2.4l-3.2-2.4c-.9.6-2 1-3.4 1-2.6 0-4.8-1.7-5.6-4.1H3.1v2.5c1.7 3.3 5 5.4 8.9 5.4z" fill="#34A853" /><path d="M6.4 13.5c-.2-.6-.3-1.2-.3-1.9 0-.7.1-1.3.3-1.9V7.2H3.1c-.7 1.4-1.1 3-1.1 4.6 0 1.7.4 3.2 1.1 4.6z" fill="#FBBC04" /><path d="M12 6.6c1.5 0 2.8.5 3.8 1.5l2.9-2.8C16.9 3.7 14.7 2.5 12 2.5c-3.9 0-7.2 2.2-8.9 5.4l3.3 2.6C7.2 8.3 9.4 6.6 12 6.6z" fill="#EA4335" /></>,
    mail: <><rect x="3" y="5" width="18" height="14" rx="2" {...c} /><path d="M3 7l9 7 9-7" {...c} /></>,
    lock: <><rect x="5" y="11" width="14" height="9" rx="2" {...c} /><path d="M8 11V8a4 4 0 1 1 8 0v3" {...c} /></>,
    sparkles: <><path d="M12 3l1.5 4L17 8l-3.5 1L12 13l-1.5-4L7 8l3.5-1z" {...c} /><path d="M18 14l.7 1.8L20 16l-1.3.5L18 18l-.5-1.5L16 16l1.5-.7z" {...c} /><path d="M5 16l.7 1.8L7 18l-1.3.5L5 20l-.5-1.5L3 18l1.5-.7z" {...c} /></>,
    play: <path d="M7 4l13 8-13 8z" fill={color} stroke={color} strokeLinejoin="round" />,
    clock: <><circle cx="12" cy="12" r="9" {...c} /><path d="M12 7v5l3 2" {...c} /></>,
    crown: <><path d="M3 8l4 4 5-7 5 7 4-4-2 11H5z" {...c} /></>,
    flame: <><path d="M12 21c-4 0-7-3-7-7 0-3 3-4 3-7 0 0 3 2 3 5 0-3 2-5 4-7 0 0 4 5 4 9s-3 7-7 7z" {...c} /></>,
    list: <><path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01" {...c} /></>,
    grid: <><rect x="4" y="4" width="7" height="7" rx="1" {...c} /><rect x="13" y="4" width="7" height="7" rx="1" {...c} /><rect x="4" y="13" width="7" height="7" rx="1" {...c} /><rect x="13" y="13" width="7" height="7" rx="1" {...c} /></>,
    filter: <><path d="M4 5h16l-6 8v6l-4-2v-4z" {...c} /></>,
    edit: <><path d="M4 20h4l11-11-4-4L4 16z" {...c} /></>,
    chat: <><path d="M21 12a8 8 0 1 1-3.4-6.5L21 4l-1.5 4A8 8 0 0 1 21 12z" {...c} /></>,
    info: <><circle cx="12" cy="12" r="9" {...c} /><path d="M12 11v6M12 7.5h.01" {...c} /></>,
    star: <><path d="M12 4l2.5 5 5.5.8-4 4 .9 5.5L12 17l-4.9 2.3.9-5.5-4-4 5.5-.8z" {...c} /></>,
    starFill: <path d="M12 4l2.5 5 5.5.8-4 4 .9 5.5L12 17l-4.9 2.3.9-5.5-4-4 5.5-.8z" fill={color} stroke={color} strokeLinejoin="round" />,
    globe: <><circle cx="12" cy="12" r="9" {...c} /><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" {...c} /></>,
    download: <><path d="M12 4v12M6 12l6 6 6-6M4 20h16" {...c} /></>,
    upload: <><path d="M12 20V8M6 12l6-6 6 6M4 4h16" {...c} /></>,
    link: <><path d="M10 14a4 4 0 0 1 0-5l3-3a4 4 0 0 1 5 5l-1.5 1.5M14 10a4 4 0 0 1 0 5l-3 3a4 4 0 0 1-5-5l1.5-1.5" {...c} /></>,
    image: <><rect x="3" y="4" width="18" height="16" rx="2" {...c} /><circle cx="9" cy="10" r="2" {...c} /><path d="M21 16l-5-5-9 9" {...c} /></>,
    camera: <><rect x="3" y="6" width="18" height="14" rx="2" {...c} /><path d="M8 6l2-2h4l2 2" {...c} /><circle cx="12" cy="13" r="3.5" {...c} /></>,
    languages: <><path d="M3 4h10M8 3v2M10 4c-1 5-3 8-7 10" {...c} /><path d="M5 8c1.5 3 4 5 7 6" {...c} /><path d="M13 20l4-10 4 10M14.5 17h5" {...c} /></>,
    wifi: <><path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8 15.5a5 5 0 0 1 8 0" {...c} /><circle cx="12" cy="19" r="1.2" fill={color} /></>,
    cellular: <><rect x="2" y="14" width="3" height="6" rx="0.5" fill={color} stroke="none" /><rect x="7" y="11" width="3" height="9" rx="0.5" fill={color} stroke="none" /><rect x="12" y="7" width="3" height="13" rx="0.5" fill={color} stroke="none" /><rect x="17" y="3" width="3" height="17" rx="0.5" fill={color} stroke="none" /></>,
    battery: <><rect x="2" y="8" width="18" height="10" rx="2.5" {...c} /><rect x="4" y="10" width="14" height="6" rx="1" fill={color} stroke="none" /><rect x="21" y="11" width="1.5" height="4" rx="0.5" fill={color} stroke="none" /></>,
    arrowUpRight: <><path d="M7 17L17 7M9 7h8v8" {...c} /></>,
    trash: <><path d="M5 7h14M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12" {...c} /></>,
  };
  return (
    <svg viewBox="0 0 24 24" style={s} aria-hidden="true">
      {paths[name] || null}
    </svg>
  );
};

// ──────── LOGO ────────
// Crescent moon (open at top) cradling an opened-book V — drawn as SVG so
// it inverts cleanly between themes and stays sharp at every size.
const HadithlyMark = ({ size = 40, color = 'currentColor', style }) => (
  <svg viewBox="0 0 200 200" style={{ width: size, height: size, ...style }} aria-hidden="true">
    {/* outer thin crescent — almost a full ring, with a soft gap at the top */}
    <path
      d="M 60 38 C 30 60 28 110 50 145 C 28 110 38 55 80 38 M 140 38 C 170 60 172 110 150 145 C 172 110 162 55 120 38"
      fill={color}
    />
    {/* open book — V shape with wings extending outward */}
    <path
      d="M 38 138 C 60 144 84 152 100 174 C 116 152 140 144 162 138 C 144 144 124 144 105 152 L 100 158 L 95 152 C 76 144 56 144 38 138 Z"
      fill={color}
    />
  </svg>
);

// ──────── STATUS BAR + FRAMES ────────
const StatusBar = ({ time = '9:41', dark = false }) => {
  const color = dark ? '#F5EFE3' : '#1B1A17';
  return (
    <div style={{
      height: 47, padding: '14px 32px 0', display: 'flex', alignItems: 'center',
      justifyContent: 'space-between', color, fontWeight: 600, fontSize: 15,
      fontFamily: 'Outfit, -apple-system, system-ui, sans-serif',
      letterSpacing: '-0.01em', position: 'relative', zIndex: 5,
    }}>
      <span>{time}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        <Icon name="cellular" size={16} color={color} />
        <Icon name="wifi" size={16} color={color} />
        <Icon name="battery" size={26} color={color} />
      </div>
    </div>
  );
};

const PhoneFrame = ({ children, theme = 'light', bg, dark, hideStatus, time, label }) => {
  const t = themes[theme] || themes.light;
  const isDark = dark != null ? dark : theme === 'dark';
  return (
    <div data-screen-label={label} style={{
      width: PHONE.w, height: PHONE.h, borderRadius: PHONE.radius,
      background: bg || t.bg, position: 'relative', overflow: 'hidden',
      boxShadow: '0 0 0 12px #18181b, 0 0 0 13px #3f3f46, 0 30px 60px rgba(0,0,0,.25)',
      color: t.text,
    }}>
      {!hideStatus && <StatusBar dark={isDark} time={time} />}
      {hideStatus && <div style={{ height: 12 }} />}
      <div style={{ height: hideStatus ? PHONE.h - 12 : PHONE.h - 47, position: 'relative' }}>
        {children}
      </div>
      {/* dynamic island */}
      <div style={{
        position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
        width: 122, height: 36, borderRadius: 22, background: '#000', zIndex: 10,
      }} />
      <div style={{
        position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 3, background: isDark ? '#F5EFE3' : '#1B1A17', opacity: 0.85, zIndex: 10,
      }} />
    </div>
  );
};

const AndroidFrame = ({ children, theme = 'light', bg, dark, label }) => {
  const t = themes[theme] || themes.light;
  const isDark = dark != null ? dark : theme === 'dark';
  const color = isDark ? '#F5EFE3' : '#1B1A17';
  return (
    <div data-screen-label={label} style={{
      width: ANDROID.w, height: ANDROID.h, borderRadius: ANDROID.radius,
      background: bg || t.bg, position: 'relative', overflow: 'hidden',
      boxShadow: '0 0 0 8px #18181b, 0 0 0 9px #3f3f46, 0 30px 60px rgba(0,0,0,.25)',
      color: t.text,
    }}>
      <div style={{ position: 'absolute', top: 14, left: '50%', transform: 'translateX(-50%)', width: 18, height: 18, borderRadius: 9, background: '#000', zIndex: 10 }} />
      <div style={{ height: 44, padding: '14px 20px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', color, fontWeight: 500, fontSize: 14 }}>
        <span>9:41</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Icon name="wifi" size={14} color={color} />
          <Icon name="cellular" size={14} color={color} />
          <span style={{ fontSize: 12 }}>87%</span>
        </div>
      </div>
      <div style={{ height: ANDROID.h - 44 - 20, position: 'relative' }}>{children}</div>
      <div style={{ position: 'absolute', bottom: 6, left: '50%', transform: 'translateX(-50%)', width: 110, height: 4, borderRadius: 2, background: color, opacity: 0.6, zIndex: 10 }} />
    </div>
  );
};

// ──────── PRIMITIVES — shadcn-aligned ────────

// Chip / Badge — pill, three variants (outline, secondary, primary)
const Chip = ({ children, variant = 'secondary', tone, theme = 'light', icon, size = 'sm', style }) => {
  const t = themes[theme];
  const pad = size === 'xs' ? '2px 7px' : size === 'md' ? '4px 10px' : '3px 8px';
  const fontSize = size === 'xs' ? 10.5 : size === 'md' ? 12 : 11;
  let bg, color, border;
  if (variant === 'outline') { bg = 'transparent'; color = t.text; border = `1px solid ${t.hair}`; }
  else if (variant === 'secondary') { bg = t.surface2; color = t.text; border = '1px solid transparent'; }
  else if (variant === 'primary') { bg = t.accent; color = t.primaryFg; border = '1px solid transparent'; }
  else if (variant === 'soft') { bg = theme === 'dark' ? `${t.accent}33` : 'oklch(0.96 0.05 152)'; color = t.accentText; border = '1px solid transparent'; }
  else if (variant === 'ghost') { bg = 'transparent'; color = t.textSec; border = '1px solid transparent'; }
  if (tone === 'success') { color = t.success; border = `1px solid ${t.success}55`; bg = 'transparent'; }
  if (tone === 'warning') { color = t.warning; border = `1px solid ${t.warning}55`; bg = 'transparent'; }
  if (tone === 'danger') { color = t.danger; border = `1px solid ${t.danger}55`; bg = 'transparent'; }
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4, padding: pad,
      borderRadius: RADIUS.md, fontSize, fontWeight: 500, lineHeight: 1.15,
      background: bg, color, border, letterSpacing: '-0.005em', whiteSpace: 'nowrap',
      fontFamily: 'Outfit, system-ui, sans-serif', ...style,
    }}>{icon}{children}</span>
  );
};

// Button — shadcn variants (default/secondary/outline/ghost) + size
const Button = ({ children, variant = 'primary', theme = 'light', size = 'md', icon, iconRight, onClick, block, style, disabled }) => {
  const t = themes[theme];
  const pad = size === 'sm' ? '6px 12px' : size === 'lg' ? '12px 20px' : '9px 16px';
  const fontSize = size === 'sm' ? 13 : size === 'lg' ? 15 : 14;
  let bg, color, border = '1px solid transparent';
  if (variant === 'primary') { bg = t.accent; color = t.primaryFg; }
  else if (variant === 'secondary') { bg = t.surface2; color = t.text; }
  else if (variant === 'outline') { bg = 'transparent'; color = t.text; border = `1px solid ${t.hair}`; }
  else if (variant === 'ghost') { bg = 'transparent'; color = t.text; }
  else if (variant === 'destructive') { bg = t.danger; color = '#fff'; }
  return (
    <button onClick={onClick} disabled={disabled} style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7,
      padding: pad, borderRadius: RADIUS.md, fontSize, fontWeight: 500,
      background: bg, color, border, cursor: 'pointer', width: block ? '100%' : 'auto',
      fontFamily: 'Outfit, system-ui, sans-serif', letterSpacing: '-0.005em',
      transition: 'all .15s', opacity: disabled ? 0.5 : 1, lineHeight: 1.2, ...style,
    }}>{icon}{children}{iconRight}</button>
  );
};

const IconButton = ({ name, theme = 'light', size = 36, iconSize, onClick, glass, dark, style, badge, color, variant = 'ghost' }) => {
  const t = themes[theme];
  const isDark = dark != null ? dark : theme === 'dark';
  let bg = 'transparent';
  if (variant === 'outline') bg = t.surface;
  if (variant === 'secondary') bg = t.surface2;
  if (glass) bg = isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)';
  const c = color || t.text;
  return (
    <button onClick={onClick} style={{
      width: size, height: size, borderRadius: RADIUS.md, border: variant === 'outline' ? `1px solid ${t.hair}` : 'none',
      background: bg, backdropFilter: glass ? 'blur(20px) saturate(160%)' : undefined,
      WebkitBackdropFilter: glass ? 'blur(20px) saturate(160%)' : undefined,
      display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
      position: 'relative', color: c, padding: 0, ...style,
    }}>
      <Icon name={name} size={iconSize || size * 0.5} color={c} />
      {badge && (
        <span style={{
          position: 'absolute', top: -2, right: -2, minWidth: 16, height: 16, padding: '0 4px',
          borderRadius: 8, background: t.danger, color: '#fff', fontSize: 9.5, fontWeight: 700,
          display: 'flex', alignItems: 'center', justifyContent: 'center', border: `2px solid ${t.bg}`,
        }}>{badge}</span>
      )}
    </button>
  );
};

// Switch — shadcn-styled
const Switch = ({ on, theme = 'light', onChange, small }) => {
  const t = themes[theme];
  const w = small ? 36 : 44;
  const h = small ? 20 : 24;
  const knob = small ? 16 : 20;
  return (
    <button onClick={onChange} style={{
      width: w, height: h, borderRadius: h / 2, border: 'none', cursor: 'pointer',
      background: on ? t.accent : (theme === 'dark' ? 'oklch(0.35 0.005 285)' : 'oklch(0.88 0.005 285)'),
      padding: 2, display: 'flex', alignItems: 'center', justifyContent: on ? 'flex-end' : 'flex-start',
      transition: 'all .2s',
    }}>
      <div style={{
        width: knob, height: knob, borderRadius: '50%', background: '#fff',
        boxShadow: '0 1px 2px rgba(0,0,0,.15)',
      }} />
    </button>
  );
};

const ProgressBar = ({ value, theme = 'light', color, height = 4, segments }) => {
  const t = themes[theme];
  if (segments) {
    return (
      <div style={{ height, borderRadius: height / 2, background: t.surface2, overflow: 'hidden', display: 'flex' }}>
        {segments.map((s, i) => <div key={i} style={{ width: `${s.value}%`, background: s.color, height: '100%' }} />)}
      </div>
    );
  }
  return (
    <div style={{ height, borderRadius: height / 2, background: t.surface2, overflow: 'hidden' }}>
      <div style={{ width: `${value}%`, height: '100%', background: color || t.accent, borderRadius: height / 2, transition: 'width .3s' }} />
    </div>
  );
};

// Segmented control
const Segmented = ({ options, value, onChange, theme = 'light', block }) => {
  const t = themes[theme];
  return (
    <div style={{
      display: 'inline-flex', padding: 3, background: t.surface2,
      borderRadius: RADIUS.md + 3, gap: 0, width: block ? '100%' : undefined,
    }}>
      {options.map(o => {
        const val = typeof o === 'string' ? o : o.value;
        const label = typeof o === 'string' ? o : o.label;
        const isVal = val === value;
        return (
          <button key={val} onClick={() => onChange && onChange(val)} style={{
            flex: 1, padding: '6px 14px', borderRadius: RADIUS.md, border: 'none', cursor: 'pointer',
            background: isVal ? (theme === 'dark' ? t.surface : '#fff') : 'transparent',
            boxShadow: isVal ? '0 1px 2px rgba(0,0,0,.08)' : 'none',
            color: isVal ? t.text : t.textSec, fontSize: 12.5, fontWeight: isVal ? 600 : 500,
            fontFamily: 'Outfit, system-ui, sans-serif', whiteSpace: 'nowrap', letterSpacing: '-0.005em',
          }}>{label}</button>
        );
      })}
    </div>
  );
};

// Card — basic shadcn card
const Card = ({ children, theme = 'light', style, padding = 16 }) => {
  const t = themes[theme];
  return (
    <div style={{
      background: t.surface, border: `1px solid ${t.hair}`,
      borderRadius: RADIUS.lg, padding,
      boxShadow: theme === 'dark' ? '0 1px 0 rgba(255,255,255,0.04)' : '0 1px 2px rgba(0,0,0,0.02)',
      ...style,
    }}>{children}</div>
  );
};

// Bottom sheet
const BottomSheet = ({ children, theme = 'light', height, title, onClose, dark, padded = true }) => {
  const t = themes[theme];
  const isDark = dark != null ? dark : theme === 'dark';
  return (
    <>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.4)', backdropFilter: 'blur(2px)', zIndex: 50 }} />
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, height: height || 'auto',
        background: t.surface, borderRadius: `${RADIUS.xl + 4}px ${RADIUS.xl + 4}px 0 0`, zIndex: 51,
        boxShadow: '0 -10px 30px rgba(0,0,0,.25)', overflow: 'hidden', color: t.text,
        border: `1px solid ${t.hair}`, borderBottom: 'none',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 4, borderRadius: 2, background: isDark ? 'rgba(255,255,255,.16)' : 'rgba(0,0,0,.12)' }} />
        </div>
        {title && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px 14px' }}>
            <div style={{ fontSize: 17, fontWeight: 600, color: t.text, letterSpacing: '-0.01em' }}>{title}</div>
            {onClose && <IconButton name="close" theme={theme} size={28} iconSize={15} variant="secondary" onClick={onClose} />}
          </div>
        )}
        {children}
      </div>
    </>
  );
};

// Hadith block — NEW DESIGN:
// • Metadata row aligned LEFT (above hadith), compact
// • Reference is just the NUMBER (4:176-style for chapter:hadith)
// • No big star divider, no extra space — just a thin hairline between blocks
const HadithBlock = ({ h, theme = 'light', showTranslation = true, showArabic = true, fontSize = 26, lineHeight = 2.05, translationSize = 16.5, isLast, idx, showDivider = true }) => {
  const t = themes[theme];
  const sourceColor = h.translationKind === 'gemini' ? t.accent : h.translationKind === 'community' ? t.gold : t.textSec;
  const ratingLabel = h.votes < 5 ? 'New' : (h.ratingPercent < 70 ? 'Needs review' : `${h.ratingPercent}%`);
  // Short ref — drop the collection name, keep "ch:num" or just number
  const shortRef = h.shortRef || (h.ref ? h.ref.replace(/^[A-Za-zʿ' ]+ /, '') : '');

  return (
    <div style={{ padding: '14px 0 14px' }}>
      {/* Metadata row — chapter ref on the LEFT, badges + votes pushed RIGHT */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 5, marginBottom: 10,
        color: t.textSec, fontSize: 11, flexWrap: 'nowrap',
      }}>
        <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500, letterSpacing: '-0.005em' }}>{shortRef}</span>
        <div style={{ flex: 1 }} />
        <Chip variant="outline" theme={theme} size="xs">{h.grade || 'Grade unavailable'}</Chip>
        <Chip variant="soft" theme={theme} size="xs" style={{ color: sourceColor, background: theme === 'dark' ? `${sourceColor}28` : `${sourceColor}15` }}>
          {h.translationKind === 'gemini' && <Icon name="sparkle" size={9} color={sourceColor} />}
          {h.translationKind === 'gemini' ? 'AI' : h.translationKind === 'community' ? 'Community' : 'Official EN'}
        </Chip>
        <span style={{ fontSize: 10.5, color: h.votes < 5 ? t.textTer : t.textSec, fontWeight: 500 }}>{ratingLabel}</span>
        <button style={{ background: 'transparent', border: 'none', cursor: 'pointer', padding: 1, color: t.textTer, display: 'inline-flex', alignItems: 'center' }}>
          <Icon name="thumbUp" size={13} />
        </button>
        <button style={{ background: 'transparent', border: 'none', cursor: 'pointer', padding: 1, color: t.textTer, display: 'inline-flex', alignItems: 'center' }}>
          <Icon name="thumbDown" size={13} />
        </button>
      </div>
      {showArabic && (
        <div className="arabic" style={{ fontSize, lineHeight, color: t.text, textAlign: 'right', marginBottom: showTranslation ? 12 : 0, letterSpacing: 0 }}>
          {h.arabic}
        </div>
      )}
      {showTranslation && (
        <div className="serif" style={{ fontSize: translationSize, lineHeight: 1.7, color: t.text, letterSpacing: '0.003em' }}>
          {h.english}
        </div>
      )}
      {/* hairline divider between hadiths, no centerpiece */}
      {!isLast && showDivider && <div style={{ marginTop: 18, height: 1, background: t.hair }} />}
    </div>
  );
};

// Tab bar — 4 tabs, shadcn-styled
const TabBar = ({ theme = 'light', active = 'home', dark }) => {
  const t = themes[theme];
  const isDark = dark != null ? dark : theme === 'dark';
  const tabs = [
    { id: 'home', name: 'home', label: 'Home' },
    { id: 'library', name: 'book', label: 'Library' },
    { id: 'community', name: 'community', label: 'Community' },
    { id: 'you', name: 'user', label: 'You' },
  ];
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, height: 83,
      background: isDark ? 'oklch(0.18 0.005 285 / 0.9)' : 'rgba(255,255,255,0.85)',
      backdropFilter: 'blur(28px) saturate(180%)',
      WebkitBackdropFilter: 'blur(28px) saturate(180%)',
      borderTop: `1px solid ${t.hair}`,
      display: 'flex', justifyContent: 'space-around', padding: '8px 0 24px',
    }}>
      {tabs.map(tab => {
        const isActive = tab.id === active;
        const color = isActive ? t.accent : t.textSec;
        return (
          <div key={tab.id} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, flex: 1, paddingTop: 4, color }}>
            <Icon name={tab.name} size={24} color={color} strokeWidth={isActive ? 2 : 1.6} />
            <div style={{ fontSize: 10, fontWeight: 500, letterSpacing: '0.005em' }}>{tab.label}</div>
          </div>
        );
      })}
    </div>
  );
};

const Avatar = ({ name, size = 36, color, theme = 'light', style }) => {
  const t = themes[theme];
  const initials = name ? name.split(' ').slice(0, 2).map(w => w[0]).join('') : '';
  const bg = color || `oklch(0.7 0.08 ${(name?.charCodeAt(0) || 60) * 4 % 360})`;
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', background: bg,
      color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: size * 0.36, fontWeight: 600, flexShrink: 0,
      fontFamily: 'Outfit, system-ui, sans-serif', ...style,
    }}>{initials}</div>
  );
};

const Row = ({ leading, title, subtitle, trailing, theme = 'light', onClick, style, noBorder }) => {
  const t = themes[theme];
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 12, padding: '13px 0',
      borderBottom: noBorder ? 'none' : `1px solid ${t.hair}`,
      cursor: onClick ? 'pointer' : 'default', ...style,
    }}>
      {leading}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, color: t.text, fontWeight: 500, lineHeight: 1.3, letterSpacing: '-0.005em' }}>{title}</div>
        {subtitle && <div style={{ fontSize: 12.5, color: t.textSec, marginTop: 2, lineHeight: 1.35 }}>{subtitle}</div>}
      </div>
      {trailing}
    </div>
  );
};

const SectionHeader = ({ children, theme = 'light', style, right }) => {
  const t = themes[theme];
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '6px 0 10px', ...style }}>
      <div style={{ fontSize: 11, fontWeight: 600, color: t.textSec, letterSpacing: '0.04em', textTransform: 'uppercase' }}>{children}</div>
      {right}
    </div>
  );
};

Object.assign(window, {
  Icon, StatusBar, PhoneFrame, AndroidFrame,
  Chip, Button, IconButton, Switch, ProgressBar, Segmented, Card,
  BottomSheet, HadithBlock, TabBar, Avatar, Row, SectionHeader, HadithlyMark,
});
