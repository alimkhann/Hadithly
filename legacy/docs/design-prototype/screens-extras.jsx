// Android variants — Material 3 chrome
// Same content, M3 surfaces and FAB-style cues, no faux iOS glass.

// Android Home
const AndroidHome = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', fontFamily: 'Outfit, "Roboto", system-ui, sans-serif' }}>
      <div style={{ height: 'calc(100% - 80px)', overflowY: 'auto', padding: '8px 16px 90px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 4, marginBottom: 12 }}>
          <div style={{ fontSize: 22, color: t.text, fontWeight: 600, letterSpacing: '-0.018em' }}>Hadithly</div>
          <div style={{ display: 'flex', gap: 6 }}>
            <IconButton name="search" theme={theme} size={42} iconSize={22} />
            <IconButton name="bellDot" theme={theme} size={42} iconSize={22} />
          </div>
        </div>

        {/* M3 search bar */}
        <div style={{
          display: 'flex', gap: 12, alignItems: 'center', padding: '12px 18px',
          background: t.surface2, borderRadius: 999,
        }}>
          <Icon name="search" size={20} color={t.textSec} />
          <div style={{ flex: 1, fontSize: 14, color: t.textTer }}>Search hadith</div>
          <span style={{ fontSize: 18 }}>🇷🇺</span>
        </div>

        {/* Daily hadith — M3 filled tonal card */}
        <div style={{
          marginTop: 16, padding: '18px 18px 16px', borderRadius: 20,
          background: theme === 'dark' ? `${t.accent}1f` : 'oklch(0.96 0.05 152)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 11, flexWrap: 'wrap' }}>
            <span style={{ fontSize: 11, color: t.accentText, fontWeight: 600, letterSpacing: '0.04em' }}>TODAY · 1:1</span>
            <Chip variant="outline" theme={theme} size="xs">Sahih</Chip>
          </div>
          <div className="arabic" style={{ fontSize: 21, lineHeight: 1.95, color: t.text, textAlign: 'right', marginBottom: 10 }}>
            إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ
          </div>
          <div className="serif" style={{ fontSize: 14, lineHeight: 1.55, color: t.text, marginBottom: 14, opacity: .85 }}>
            Поистине, дела оцениваются по намерениям, и каждому достанется лишь то, что он намеревался обрести.
          </div>
          <button style={{
            padding: '10px 20px', borderRadius: 999, border: 'none', cursor: 'pointer',
            background: t.accent, color: t.primaryFg, fontWeight: 500, fontSize: 13.5,
            fontFamily: 'inherit', display: 'inline-flex', alignItems: 'center', gap: 6,
            letterSpacing: '-0.005em',
          }}>Read today <Icon name="arrowR" size={14} /></button>
        </div>

        {/* Continue */}
        <div style={{ marginTop: 18, padding: '13px 14px', borderRadius: 14, background: t.surface, border: `1px solid ${t.hair}`, display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ width: 40, height: 40, borderRadius: 11, background: `${t.accent}22`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="bookOpen" size={20} color={t.accent} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 500, color: t.text, letterSpacing: '-0.005em' }}>Sahih al-Bukhari</div>
            <div style={{ fontSize: 12, color: t.textSec, marginTop: 2 }}>Belief · 11%</div>
          </div>
          <Icon name="play" size={18} color={t.accent} />
        </div>

        <div style={{ marginTop: 18, fontSize: 13, fontWeight: 600, color: t.textSec, letterSpacing: '0.03em', marginBottom: 8, textTransform: 'uppercase' }}>Topics</div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {TOPICS.slice(0, 6).map(topic => (
            <div key={topic} style={{
              padding: '7px 14px', borderRadius: 999,
              background: 'transparent', border: `1px solid ${t.hair}`,
              color: t.text, fontSize: 13, fontWeight: 500,
            }}>{topic}</div>
          ))}
        </div>
      </div>

      {/* M3 nav bar */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, height: 80,
        background: theme === 'dark' ? 'oklch(0.21 0.006 285.885)' : 'oklch(0.96 0.04 152)',
        display: 'flex', justifyContent: 'space-around', padding: '12px 0 20px',
      }}>
        {[
          { id: 'home', name: 'home', label: 'Home', active: true },
          { id: 'library', name: 'book', label: 'Library' },
          { id: 'community', name: 'community', label: 'Community' },
          { id: 'you', name: 'user', label: 'You' },
        ].map(tab => (
          <div key={tab.id} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, flex: 1, paddingTop: 2 }}>
            <div style={{ padding: '5px 18px', borderRadius: 999, background: tab.active ? (theme === 'dark' ? `${t.accent}33` : 'oklch(0.88 0.08 152)') : 'transparent' }}>
              <Icon name={tab.name} size={22} color={tab.active ? t.accent : t.textSec} strokeWidth={tab.active ? 2 : 1.6} />
            </div>
            <div style={{ fontSize: 11, fontWeight: 500, color: tab.active ? t.text : t.textSec }}>{tab.label}</div>
          </div>
        ))}
      </div>
    </div>
  );
};

// Android Reader — minimal: extended FAB for menu, no bottom bar clutter
const AndroidReader = ({ theme = 'light' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative', fontFamily: 'Outfit, "Roboto", system-ui, sans-serif' }}>
      <ProgressPillActive theme={theme} dark={isDark} />
      <div style={{ paddingTop: 36, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
      {/* tiny home — top-left */}
      <div style={{ position: 'absolute', left: 14, bottom: 22, zIndex: 25 }}>
        <button style={{
          width: 48, height: 48, borderRadius: '50%', border: 'none',
          background: isDark ? 'oklch(0.24 0.006 285)' : '#fff',
          boxShadow: '0 4px 12px rgba(0,0,0,0.12), 0 2px 4px rgba(0,0,0,0.08)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        }}>
          <Icon name="home" size={20} color={t.text} />
        </button>
      </div>
      {/* extended FAB for Menu */}
      <div style={{ position: 'absolute', right: 14, bottom: 22, zIndex: 25 }}>
        <button style={{
          padding: '0 18px', height: 48, borderRadius: 14, border: 'none',
          background: t.accent, color: t.primaryFg,
          display: 'inline-flex', alignItems: 'center', gap: 9, cursor: 'pointer',
          boxShadow: '0 6px 14px rgba(0,0,0,0.15), 0 2px 6px rgba(0,0,0,0.1)',
          fontWeight: 500, fontSize: 14, fontFamily: 'inherit', letterSpacing: '-0.005em',
        }}>
          <Icon name="menu" size={20} color={t.primaryFg} /> Menu
        </button>
      </div>
    </div>
  );
};

// Android Reader Menu — M3 modal sheet, minimal, clean rows
const AndroidReaderMenu = ({ theme = 'light' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative', fontFamily: 'Outfit, "Roboto", system-ui, sans-serif' }}>
      <ProgressPillDefault theme={theme} dark={isDark} />
      <div style={{ paddingTop: 22, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
      {/* M3 modal bottom sheet — full-bleed surface, no card stacks */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.4)', zIndex: 50 }} />
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 51,
        background: isDark ? 'oklch(0.24 0.006 285)' : '#fff',
        borderRadius: '28px 28px 0 0', overflow: 'hidden', color: t.text,
        boxShadow: '0 -10px 30px rgba(0,0,0,.25)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 12, paddingBottom: 6 }}>
          <div style={{ width: 32, height: 4, borderRadius: 2, background: isDark ? 'rgba(255,255,255,.2)' : 'rgba(0,0,0,.15)' }} />
        </div>

        <div style={{ padding: '18px 24px 6px' }}>
          <div style={{ fontSize: 11, color: t.textTer, letterSpacing: '0.06em', textTransform: 'uppercase', fontWeight: 600 }}>Now reading</div>
          <div style={{ fontSize: 18, color: t.text, fontWeight: 600, marginTop: 4, letterSpacing: '-0.015em' }}>Sahih al-Bukhari · Belief</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 8 }}>
            <div style={{ flex: 1 }}><ProgressBar value={11} theme={theme} height={3} /></div>
            <div style={{ fontSize: 11.5, color: t.textSec }}>Hadith 8 of 51</div>
          </div>
        </div>

        <div style={{ paddingBottom: 18 }}>
          {[
            ['list', 'Book contents'],
            ['bookmark', 'Bookmarks, favorites, notes'],
            ['search', 'Search in this book'],
            ['sliders', 'Reader settings'],
            ['share', 'Share hadith'],
          ].map(([icon, label]) => (
            <div key={label} style={{
              padding: '14px 24px', display: 'flex', alignItems: 'center', gap: 18,
              cursor: 'pointer',
            }}>
              <Icon name={icon} size={22} color={t.textSec} />
              <span style={{ fontSize: 15, color: t.text, letterSpacing: '-0.005em' }}>{label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// Android paywall — M3 dialog look
const AndroidPaywall = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ width: '100%', height: '100%', padding: '12px 16px 20px', position: 'relative', fontFamily: 'Outfit, "Roboto", system-ui, sans-serif', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <IconButton name="close" theme={theme} size={40} iconSize={20} />
      </div>
      <div style={{ display: 'flex', justifyContent: 'center', marginTop: 2 }}>
        <div style={{ width: 60, height: 60, borderRadius: 18, background: `${t.accent}22`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="sparkle" size={30} color={t.accent} />
        </div>
      </div>
      <div style={{ marginTop: 16, fontSize: 24, color: t.text, fontWeight: 600, lineHeight: 1.18, textAlign: 'center', letterSpacing: '-0.018em' }}>Bring hadith to<br/>every language</div>
      <div style={{ fontSize: 14, color: t.textSec, marginTop: 8, lineHeight: 1.5, textAlign: 'center', maxWidth: 320, alignSelf: 'center' }}>
        Pro supports AI translations and helps the community.
      </div>

      <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 10 }}>
        {['500 AI translations / month', 'Priority queue', 'Offline language packs', 'Advanced contribution tools'].map(label => (
          <div key={label} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 4px' }}>
            <Icon name="check" size={18} color={t.accent} strokeWidth={2.5} />
            <div style={{ fontSize: 14, color: t.text, letterSpacing: '-0.005em' }}>{label}</div>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ padding: '13px 16px', borderRadius: 14, border: `2px solid ${t.accent}`, background: theme === 'dark' ? `${t.accent}1f` : 'oklch(0.96 0.05 152)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <div style={{ fontSize: 11.5, color: t.accent, fontWeight: 600 }}>ANNUAL · BEST VALUE</div>
            <div style={{ fontSize: 18, color: t.text, fontWeight: 600, marginTop: 2, letterSpacing: '-0.012em' }}>$29.99 / year</div>
            <div style={{ fontSize: 11.5, color: t.textSec, marginTop: 1 }}>3-day free trial</div>
          </div>
          <div style={{ width: 22, height: 22, borderRadius: '50%', border: `7px solid ${t.accent}`, background: '#fff' }} />
        </div>
        <div style={{ padding: '13px 16px', borderRadius: 14, border: `1px solid ${t.hair}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <div style={{ fontSize: 11.5, color: t.textSec, fontWeight: 600 }}>MONTHLY</div>
            <div style={{ fontSize: 18, color: t.text, fontWeight: 600, marginTop: 2, letterSpacing: '-0.012em' }}>$3.99 / month</div>
          </div>
          <div style={{ width: 22, height: 22, borderRadius: '50%', border: `2px solid ${t.hair}` }} />
        </div>
      </div>

      <div style={{ flex: 1 }} />
      <button style={{
        padding: '14px 22px', borderRadius: 999, border: 'none',
        background: t.accent, color: t.primaryFg,
        fontWeight: 500, fontSize: 15, fontFamily: 'inherit', cursor: 'pointer', letterSpacing: '-0.005em',
      }}>Start free trial</button>
      <button style={{
        padding: '14px 22px', borderRadius: 999, border: 'none', background: 'transparent',
        color: t.accent, fontWeight: 500, fontSize: 14, fontFamily: 'inherit', cursor: 'pointer', marginTop: 6,
      }}>Continue free</button>
    </div>
  );
};

Object.assign(window, { AndroidHome, AndroidReader, AndroidReaderMenu, AndroidPaywall });
