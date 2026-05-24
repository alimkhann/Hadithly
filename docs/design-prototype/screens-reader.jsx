// Reader screens — the heart
// Continuous text, no cards, metadata aligned LEFT, hairline between hadiths
// Minimal progress pills, sheets are minimal, no authenticity sheet,
// no missing-translation state (translations always available immediately)

// Reader page — continuous book-like text
const ReaderPage = ({ theme = 'light', fontSize = 26, lineHeight = 2.05, translationSize = 16, showArabic = true, showTranslation = true }) => {
  const t = themes[theme];
  return (
    <div style={{
      padding: '0 22px', color: t.text, height: '100%', overflowY: 'auto',
    }}>
      {/* Book heading — English + Arabic on the SAME line */}
      <div style={{
        display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
        marginTop: 16, marginBottom: 4, gap: 12,
      }}>
        <div className="display" style={{ fontSize: 20, color: t.text, fontWeight: 600, letterSpacing: '-0.018em' }}>Book of Belief</div>
        <div className="arabic" style={{ fontSize: 16, color: t.textSec, direction: 'rtl' }}>كِتَابُ الْإِيمَانِ</div>
      </div>
      <div style={{ fontSize: 10.5, color: t.textTer, letterSpacing: '0.06em', textTransform: 'uppercase', fontWeight: 600, marginBottom: 14 }}>
        Sahih al-Bukhari · 51 hadith
      </div>
      <div style={{ height: 1, background: t.hair, marginBottom: 2 }} />
      <HadithBlock h={HADITHS[1]} theme={theme} fontSize={fontSize} lineHeight={lineHeight} translationSize={translationSize} showArabic={showArabic} showTranslation={showTranslation} />
      <HadithBlock h={HADITHS[0]} theme={theme} fontSize={fontSize} lineHeight={lineHeight} translationSize={translationSize} showArabic={showArabic} showTranslation={showTranslation} />
      <HadithBlock h={HADITHS[2]} theme={theme} fontSize={fontSize} lineHeight={lineHeight} translationSize={translationSize} showArabic={showArabic} showTranslation={showTranslation} isLast />
    </div>
  );
};

// Minimal default progress pill — bare filled pill, no label
const ProgressPillDefault = ({ theme = 'light', dark }) => {
  const t = themes[theme];
  const isDark = dark != null ? dark : theme === 'dark';
  return (
    <div style={{
      position: 'absolute', top: 10, left: '50%', transform: 'translateX(-50%)',
      zIndex: 20, padding: '3px 8px', borderRadius: 999,
      background: isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)',
    }}>
      <div style={{
        width: 38, height: 3, borderRadius: 2,
        background: isDark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.12)', overflow: 'hidden',
      }}>
        <div style={{ width: '11%', height: '100%', background: t.accent }} />
      </div>
    </div>
  );
};

// Active progress pill — minimal, just label + filled pill (label floats ABOVE the pill)
const ProgressPillActive = ({ theme = 'light', dark }) => {
  const t = themes[theme];
  const isDark = dark != null ? dark : theme === 'dark';
  return (
    <div style={{
      position: 'absolute', top: 8, left: '50%', transform: 'translateX(-50%)',
      zIndex: 20, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
    }}>
      <div style={{
        fontSize: 11, fontWeight: 600, color: isDark ? t.text : t.text,
        letterSpacing: '-0.005em', fontFamily: 'Outfit, system-ui, sans-serif',
      }}>Page 12</div>
      <div style={{
        width: 90, height: 5, borderRadius: 3,
        background: isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.12)', overflow: 'hidden',
      }}>
        <div style={{ width: '11%', height: '100%', background: t.accent }} />
      </div>
    </div>
  );
};

// Default reader state
const ReaderDefault = ({ theme = 'light' }) => {
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <ProgressPillDefault theme={theme} dark={isDark} />
      <div style={{ paddingTop: 22, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
    </div>
  );
};

// Active reader state — chrome visible
const ReaderActive = ({ theme = 'light' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <ProgressPillActive theme={theme} dark={isDark} />
      <div style={{ paddingTop: 36, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>

      {/* bottom-left home, bottom-right menu */}
      <div style={{ position: 'absolute', left: 18, bottom: 28, zIndex: 25 }}>
        <IconButton name="home" theme={theme} size={44} iconSize={20} glass dark={isDark} />
      </div>
      <div style={{ position: 'absolute', right: 18, bottom: 28, zIndex: 25 }}>
        <IconButton name="menu" theme={theme} size={44} iconSize={20} glass dark={isDark} />
      </div>
      {/* right side bookmark + search */}
      <div style={{ position: 'absolute', right: 18, top: '46%', zIndex: 25, display: 'flex', flexDirection: 'column', gap: 9 }}>
        <IconButton name="bookmark" theme={theme} size={40} iconSize={17} glass dark={isDark} />
        <IconButton name="search" theme={theme} size={40} iconSize={17} glass dark={isDark} />
      </div>
    </div>
  );
};

// Reader menu sheet — redesigned, cleaner. Each row is a clear action.
const ReaderMenuSheet = ({ theme = 'light' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <ProgressPillDefault theme={theme} dark={isDark} />
      <div style={{ paddingTop: 22, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
      <BottomSheet theme={theme} title="Menu" dark={isDark}>
        <div style={{ padding: '0 20px 22px' }}>
          {/* Context — where you are */}
          <Card theme={theme} padding={14} style={{ marginBottom: 12, background: t.surface2, border: 'none' }}>
            <div style={{ fontSize: 11, color: t.textTer, letterSpacing: '0.06em', textTransform: 'uppercase', fontWeight: 600 }}>You're reading</div>
            <div style={{ fontSize: 15, color: t.text, fontWeight: 600, marginTop: 4, letterSpacing: '-0.005em' }}>Sahih al-Bukhari · Belief</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
              <div style={{ flex: 1 }}><ProgressBar value={11} theme={theme} height={3} /></div>
              <div style={{ fontSize: 11, color: t.textSec }}>11% · Hadith 8 of 51</div>
            </div>
          </Card>

          <Card theme={theme} style={{ padding: '0 14px' }}>
            <Row theme={theme} onClick={()=>{}}
              leading={<Icon name="list" size={19} color={t.textSec} />}
              title="Book contents" subtitle="Jump to any book or hadith"
              trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
            <Row theme={theme} onClick={()=>{}}
              leading={<Icon name="bookmark" size={18} color={t.textSec} />}
              title="Bookmarks, favorites, notes" subtitle="24 saved"
              trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
            <Row theme={theme} onClick={()=>{}}
              leading={<Icon name="search" size={18} color={t.textSec} />}
              title="Search in this book"
              trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
            <Row theme={theme} onClick={()=>{}}
              leading={<Icon name="sliders" size={18} color={t.textSec} />}
              title="Reader settings" subtitle="Typography, theme, display"
              trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
            <Row theme={theme} noBorder onClick={()=>{}}
              leading={<Icon name="share" size={18} color={t.textSec} />}
              title="Share hadith"
              trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
          </Card>
        </div>
      </BottomSheet>
    </div>
  );
};

// Reader settings sheet — typography + theme + display toggles
const ReaderSettingsSheet = ({ theme = 'light' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <ProgressPillDefault theme={theme} dark={isDark} />
      <div style={{ paddingTop: 22, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
      <BottomSheet theme={theme} title="Reader settings" height={550} dark={isDark}>
        <div style={{ padding: '0 20px 22px', overflowY: 'auto', height: 498 }}>
          <SectionHeader theme={theme}>Display</SectionHeader>
          <Card theme={theme} style={{ padding: '0 14px', marginBottom: 16, background: t.surface2, border: 'none' }}>
            <Row theme={theme} title="Arabic" trailing={<Switch on theme={theme} small />} />
            <Row theme={theme} title="Translation" trailing={<Switch on theme={theme} small />} />
            <Row theme={theme} noBorder title="Transliteration" trailing={<Switch on={false} theme={theme} small />} />
          </Card>

          <SectionHeader theme={theme}>Theme</SectionHeader>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8, marginBottom: 16 }}>
            {[
              { id: 'light', label: 'Light', bg: '#FFFFFF', dot: 'oklch(0.141 0.005 285.823)' },
              { id: 'dark', label: 'Dark', bg: 'oklch(0.141 0.005 285.823)', dot: '#F5EFE3' },
              { id: 'sepia', label: 'Sepia', bg: '#F4ECD8', dot: '#241D13' },
            ].map(opt => {
              const sel = opt.id === theme;
              return (
                <div key={opt.id} style={{
                  padding: 10, borderRadius: RADIUS.md, background: opt.bg,
                  border: `1.5px solid ${sel ? t.accent : t.hair}`, textAlign: 'center',
                }}>
                  <div style={{ height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Icon name="type" size={15} color={opt.dot} />
                  </div>
                  <div style={{ fontSize: 12, color: opt.dot, fontWeight: sel ? 600 : 500, marginTop: 4 }}>{opt.label}</div>
                </div>
              );
            })}
          </div>

          <SectionHeader theme={theme}>Typography</SectionHeader>
          <Card theme={theme} style={{ padding: '12px 14px', marginBottom: 10, background: t.surface2, border: 'none' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
              <span style={{ fontSize: 13.5, color: t.text }}>Arabic size</span>
              <span style={{ fontSize: 12, color: t.textSec }}>26 pt</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span className="arabic" style={{ fontSize: 12, color: t.textSec }}>أ</span>
              <div style={{ flex: 1, height: 4, borderRadius: 2, background: t.hair, position: 'relative' }}>
                <div style={{ position: 'absolute', left: 0, top: 0, height: '100%', width: '52%', background: t.accent, borderRadius: 2 }} />
                <div style={{ position: 'absolute', left: '52%', top: '50%', width: 18, height: 18, borderRadius: '50%', background: '#fff', border: `1px solid ${t.hair}`, transform: 'translate(-50%, -50%)', boxShadow: '0 1px 4px rgba(0,0,0,.15)' }} />
              </div>
              <span className="arabic" style={{ fontSize: 22, color: t.textSec }}>أ</span>
            </div>
          </Card>
          <Card theme={theme} style={{ padding: '12px 14px', marginBottom: 16, background: t.surface2, border: 'none' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
              <span style={{ fontSize: 13.5, color: t.text }}>Translation size</span>
              <span style={{ fontSize: 12, color: t.textSec }}>16 pt</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ fontSize: 11, color: t.textSec }}>A</span>
              <div style={{ flex: 1, height: 4, borderRadius: 2, background: t.hair, position: 'relative' }}>
                <div style={{ position: 'absolute', left: 0, top: 0, height: '100%', width: '40%', background: t.accent, borderRadius: 2 }} />
                <div style={{ position: 'absolute', left: '40%', top: '50%', width: 18, height: 18, borderRadius: '50%', background: '#fff', border: `1px solid ${t.hair}`, transform: 'translate(-50%, -50%)', boxShadow: '0 1px 4px rgba(0,0,0,.15)' }} />
              </div>
              <span style={{ fontSize: 18, color: t.textSec }}>A</span>
            </div>
          </Card>

          <SectionHeader theme={theme}>Behavior</SectionHeader>
          <Card theme={theme} style={{ padding: '0 14px', background: t.surface2, border: 'none' }}>
            <Row theme={theme} title="Hide status bar in reader" trailing={<Switch on theme={theme} small />} />
            <Row theme={theme} title="Keep screen awake" trailing={<Switch on={false} theme={theme} small />} />
            <Row theme={theme} noBorder title="Haptics" trailing={<Switch on theme={theme} small />} />
          </Card>
        </div>
      </BottomSheet>
    </div>
  );
};

// Translation details sheet — minimal: source, suggest translation, view original
const TranslationDetailsSheet = ({ theme = 'light' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <ProgressPillDefault theme={theme} dark={isDark} />
      <div style={{ paddingTop: 22, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
      <BottomSheet theme={theme} title="Translation" dark={isDark}>
        <div style={{ padding: '0 20px 22px' }}>
          {/* Provenance — clean info row */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '10px 0 14px' }}>
            <div style={{
              width: 36, height: 36, borderRadius: RADIUS.md, background: t.accent,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: t.primaryFg,
            }}>
              <Icon name="sparkle" size={18} color={t.primaryFg} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14.5, fontWeight: 600, color: t.text, letterSpacing: '-0.005em' }}>Generated with AI</div>
              <div style={{ fontSize: 12, color: t.textSec, marginTop: 1 }}>Russian · 94% · 32 votes · May 23, 2026</div>
            </div>
          </div>

          <div style={{ fontSize: 12.5, color: t.textSec, lineHeight: 1.55, padding: '10px 14px', background: t.surface2, borderRadius: RADIUS.md, marginBottom: 14 }}>
            This translation was generated by AI and may contain mistakes. Authenticity grades are never determined by AI.
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <Button variant="primary" theme={theme} size="md" block icon={<Icon name="edit" size={15} />}>Suggest a better translation</Button>
            <Button variant="outline" theme={theme} size="md" block icon={<Icon name="globe" size={15} />}>View original English</Button>
          </div>
        </div>
      </BottomSheet>
    </div>
  );
};

// Reader context menu — long-press on a hadith
const ReaderContextMenu = ({ theme = 'light' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <ProgressPillDefault theme={theme} dark={isDark} />
      <div style={{ paddingTop: 22, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
      {/* dim overlay */}
      <div style={{ position: 'absolute', inset: 0, background: isDark ? 'rgba(0,0,0,.55)' : 'rgba(0,0,0,.3)', backdropFilter: 'blur(2px)', zIndex: 30 }} />
      {/* highlighted hadith preview */}
      <div style={{ position: 'absolute', left: 16, right: 16, top: 168, zIndex: 31 }}>
        <Card theme={theme} padding={14} style={{ border: `1px solid ${t.accent}`, background: isDark ? 'oklch(0.21 0.006 285.885)' : '#fff' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 8, flexWrap: 'wrap' }}>
            <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>2:8</span>
            <Chip variant="outline" theme={theme} size="xs">Sahih</Chip>
            <Chip variant="soft" theme={theme} size="xs" style={{ color: t.gold, background: `${t.gold}1f` }}>Community</Chip>
            <span style={{ fontSize: 10.5, color: t.textSec }}>96%</span>
          </div>
          <div className="arabic" style={{ fontSize: 18, lineHeight: 1.85, color: t.text, textAlign: 'right', marginBottom: 6 }}>
            بُنِيَ الْإِسْلَامُ عَلَى خَمْسٍ…
          </div>
          <div className="serif" style={{ fontSize: 12.5, lineHeight: 1.5, color: t.textSec }}>
            Islam is built upon five…
          </div>
        </Card>
      </div>
      {/* floating menu */}
      <div style={{
        position: 'absolute', left: '50%', top: 350, transform: 'translateX(-50%)',
        width: 248, background: isDark ? 'oklch(0.24 0.006 285.885 / 0.95)' : 'rgba(255,255,255,0.96)',
        backdropFilter: 'blur(28px)', WebkitBackdropFilter: 'blur(28px)',
        borderRadius: RADIUS.lg, zIndex: 32, overflow: 'hidden',
        boxShadow: '0 20px 50px rgba(0,0,0,.3)',
        border: `1px solid ${t.hair}`,
      }}>
        {[
          ['bookmark', 'Bookmark'],
          ['heart', 'Favorite'],
          ['note', 'Add note'],
          ['edit', 'Suggest translation'],
          ['sparkle', 'Translation details'],
          ['copy', 'Copy hadith'],
          ['share', 'Share'],
        ].map(([icon, label], i, arr) => (
          <div key={label} style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '10px 14px', borderBottom: i === arr.length - 1 ? 'none' : `1px solid ${t.hair}`,
            color: t.text, fontSize: 14, fontWeight: 500, letterSpacing: '-0.005em',
          }}>
            <span>{label}</span>
            <Icon name={icon} size={16} color={t.textSec} />
          </div>
        ))}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '10px 14px', borderTop: `1px solid ${t.hair}`,
          color: t.danger, fontSize: 14, fontWeight: 500, letterSpacing: '-0.005em',
        }}>
          <span>Report issue</span>
          <Icon name="flag" size={16} color={t.danger} />
        </div>
      </div>
    </div>
  );
};

// Bookmarks / favorites / notes sheet
const BookmarksSheet = ({ theme = 'light', tab = 'bookmarks' }) => {
  const t = themes[theme];
  const isDark = theme === 'dark';
  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <ProgressPillDefault theme={theme} dark={isDark} />
      <div style={{ paddingTop: 22, height: '100%' }}>
        <ReaderPage theme={theme} />
      </div>
      <BottomSheet theme={theme} height={620} dark={isDark}>
        <div style={{ padding: '6px 20px 22px' }}>
          <Segmented theme={theme} options={[
            { value: 'bookmarks', label: 'Bookmarks' },
            { value: 'favorites', label: 'Favorites' },
            { value: 'notes', label: 'Notes' },
          ]} value={tab} block />

          <div style={{ marginTop: 12 }}>
            {tab === 'bookmarks' && [
              ['Bukhari 1:1', 'Belief', 'Today, 14:32'],
              ['Muslim 15', 'Faith', 'Yesterday, 09:14'],
              ['Tirmidhi 2517', 'Faith', '2 days ago, 22:05'],
              ['Nawawi 1', '40 Hadith', '4 days ago, 07:18'],
              ['Bukhari 2:8', 'Belief', 'Last week, 11:40'],
            ].map(([ref, book, time]) => (
              <Row key={ref} theme={theme}
                leading={<div style={{ width: 28, height: 32, borderRadius: 5, background: t.gold + '22', color: t.gold, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="bookmarkFill" size={16} color={t.gold} /></div>}
                title={ref} subtitle={`${book} · ${time}`}
                trailing={<Icon name="chevronR" size={16} color={t.textTer} />}
              />
            ))}
            {tab === 'favorites' && [
              ['Bukhari 1:1', 'Last week, 02:50'],
              ['Muslim 15', '2 weeks ago, 03:20'],
            ].map(([ref, time]) => (
              <Row key={ref} theme={theme}
                leading={<div style={{ width: 28, height: 28, borderRadius: RADIUS.sm, background: 'oklch(0.65 0.18 0 / 0.18)', color: 'oklch(0.65 0.18 0)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="heartFill" size={15} color="oklch(0.65 0.2 5)" /></div>}
                title={ref} subtitle={time}
                trailing={<Icon name="chevronR" size={16} color={t.textTer} />}
              />
            ))}
            {tab === 'notes' && (
              <div>
                <div style={{ padding: '13px 0', borderBottom: `1px solid ${t.hair}` }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 6 }}>
                    <Icon name="note" size={15} color={t.gold} />
                    <span style={{ fontSize: 14, fontWeight: 600, color: t.text, letterSpacing: '-0.005em' }}>Bukhari 1:1</span>
                    <span style={{ marginLeft: 'auto', fontSize: 11.5, color: t.textTer }}>46s ago</span>
                  </div>
                  <div className="serif" style={{ fontSize: 13.5, color: t.text, lineHeight: 1.5 }}>
                    Niyyah — the heart of every action. Worth re-reading before each major decision.
                  </div>
                </div>
                <div style={{ padding: '13px 0', borderBottom: `1px solid ${t.hair}` }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 6 }}>
                    <Icon name="note" size={15} color={t.gold} />
                    <span style={{ fontSize: 14, fontWeight: 600, color: t.text, letterSpacing: '-0.005em' }}>Muslim 15</span>
                    <span style={{ marginLeft: 'auto', fontSize: 11.5, color: t.textTer }}>Yesterday</span>
                  </div>
                  <div className="serif" style={{ fontSize: 13.5, color: t.text, lineHeight: 1.5 }}>
                    Speech, neighbors, guests — three concentric circles of character.
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </BottomSheet>
    </div>
  );
};

Object.assign(window, {
  ReaderDefault, ReaderActive, ReaderMenuSheet, ReaderSettingsSheet,
  TranslationDetailsSheet, ReaderContextMenu, BookmarksSheet,
  ReaderPage, ProgressPillDefault, ProgressPillActive,
});
