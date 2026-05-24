// Hadithly — design canvas

const { DesignCanvas, DCSection, DCArtboard } = window;

const ARTBOARD_W = PHONE.w + 24;
const ARTBOARD_H = PHONE.h + 24;

// Helper returns a real DCArtboard element so DCSection's type filter accepts it
const Board = (id, label, content) => (
  <DCArtboard key={id} id={id} label={label} width={ARTBOARD_W} height={ARTBOARD_H}>
    <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {content}
    </div>
  </DCArtboard>
);

const App = () => (
  <DesignCanvas>
    {/* ──────── ONBOARDING / AUTH / PAYWALL ──────── */}
    <DCSection id="onboarding" title="1 · Onboarding & access" subtitle="Splash → welcome (with an inspirational hadith) → language → daily hadith → preview aha-moment → auth → paywall. Calm, minimal, dismissible.">
      {Board("splash", "01 · Splash", <PhoneFrame theme="light" label="01 Splash" hideStatus><SplashScreen theme="light" /></PhoneFrame>)}
      {Board("welcome", "02 · Welcome + reminder", <PhoneFrame theme="light" label="02 Welcome"><WelcomeScreen theme="light" /></PhoneFrame>)}
      {Board("language", "03 · Language picker", <PhoneFrame theme="light" label="03 Language"><LanguageScreen theme="light" /></PhoneFrame>)}
      {Board("notif", "04 · Daily hadith", <PhoneFrame theme="light" label="04 Notifications setup"><NotificationScreen theme="light" /></PhoneFrame>)}
      {Board("preview", "05 · Translation preview", <PhoneFrame theme="light" label="05 Preview"><PreviewScreen theme="light" /></PhoneFrame>)}
      {Board("auth", "06 · Auth", <PhoneFrame theme="light" label="06 Auth"><AuthScreen theme="light" /></PhoneFrame>)}
      {Board("paywall-soft", "07 · Soft paywall", <PhoneFrame theme="light" label="07 Soft paywall"><SoftPaywallScreen theme="light" /></PhoneFrame>)}
      {Board("paywall-quota", "08 · Quota-hit paywall", <PhoneFrame theme="light" label="08 Quota paywall"><QuotaPaywallScreen theme="light" /></PhoneFrame>)}
    </DCSection>

    {/* ──────── CORE APP ──────── */}
    <DCSection id="app" title="2 · Core app" subtitle="Four tabs: Home · Library · Community · You. Bell replaces the avatar in Home — Profile lives in You.">
      {Board("home", "09 · Home", <PhoneFrame theme="light" label="09 Home"><HomeScreen theme="light" /></PhoneFrame>)}
      {Board("home-dark", "10 · Home · dark", <PhoneFrame theme="dark" label="10 Home dark"><HomeScreen theme="dark" /></PhoneFrame>)}
      {Board("notifs", "11 · Notifications", <PhoneFrame theme="light" label="11 Notifications"><NotificationsScreen theme="light" /></PhoneFrame>)}
      {Board("topic", "12 · Topic detail (Faith)", <PhoneFrame theme="light" label="12 Topic detail"><TopicDetailScreen theme="light" /></PhoneFrame>)}
      {Board("library", "13 · Library", <PhoneFrame theme="light" label="13 Library"><LibraryScreen theme="light" /></PhoneFrame>)}
      {Board("collection", "14 · Collection detail", <PhoneFrame theme="light" label="14 Collection"><CollectionDetailScreen theme="light" /></PhoneFrame>)}
      {Board("search", "15 · Search", <PhoneFrame theme="light" label="15 Search"><SearchScreen theme="light" /></PhoneFrame>)}
      {Board("community", "16 · Community", <PhoneFrame theme="light" label="16 Community"><CommunityScreen theme="light" /></PhoneFrame>)}
      {Board("submit", "17 · Submit translation w/ proof", <PhoneFrame theme="light" label="17 Submit translation"><SubmitTranslationScreen theme="light" /></PhoneFrame>)}
      {Board("you", "18 · You", <PhoneFrame theme="light" label="18 You"><YouScreen theme="light" /></PhoneFrame>)}
      {Board("settings", "19 · Settings", <PhoneFrame theme="light" label="19 Settings"><SettingsScreen theme="light" /></PhoneFrame>)}
    </DCSection>

    {/* ──────── READER ──────── */}
    <DCSection id="reader" title="3 · Reader" subtitle="Continuous book-like text. Metadata aligned LEFT — chapter:hadith number, grade, source/AI, rating, vote arrows. Hairlines between hadiths, never cards. Three themes: light, dark, sepia.">
      {Board("reader-light", "20 · Reader · light (default)", <PhoneFrame theme="light" hideStatus label="20 Reader light"><ReaderDefault theme="light" /></PhoneFrame>)}
      {Board("reader-dark", "21 · Reader · dark", <PhoneFrame theme="dark" hideStatus label="21 Reader dark"><ReaderDefault theme="dark" /></PhoneFrame>)}
      {Board("reader-sepia", "22 · Reader · sepia", <PhoneFrame theme="sepia" hideStatus label="22 Reader sepia"><ReaderDefault theme="sepia" /></PhoneFrame>)}
      {Board("reader-active", "23 · Reader · active chrome", <PhoneFrame theme="light" label="23 Reader active"><ReaderActive theme="light" /></PhoneFrame>)}
      {Board("reader-active-dark", "24 · Reader active · dark", <PhoneFrame theme="dark" label="24 Reader active dark"><ReaderActive theme="dark" /></PhoneFrame>)}
    </DCSection>

    {/* ──────── READER SHEETS ──────── */}
    <DCSection id="sheets" title="4 · Reader sheets & menus" subtitle="The Menu, settings, translation provenance, long-press context, and bookmarks/notes — all bottom sheets.">
      {Board("reader-menu", "25 · Reader menu", <PhoneFrame theme="light" hideStatus label="25 Reader menu"><ReaderMenuSheet theme="light" /></PhoneFrame>)}
      {Board("reader-settings", "26 · Reader settings", <PhoneFrame theme="light" hideStatus label="26 Reader settings"><ReaderSettingsSheet theme="light" /></PhoneFrame>)}
      {Board("reader-translation", "27 · Translation details", <PhoneFrame theme="light" hideStatus label="27 Translation details"><TranslationDetailsSheet theme="light" /></PhoneFrame>)}
      {Board("reader-context", "28 · Long-press context", <PhoneFrame theme="light" hideStatus label="28 Context menu"><ReaderContextMenu theme="light" /></PhoneFrame>)}
      {Board("reader-bookmarks", "29 · Bookmarks", <PhoneFrame theme="light" hideStatus label="29 Bookmarks"><BookmarksSheet theme="light" tab="bookmarks" /></PhoneFrame>)}
      {Board("reader-notes", "30 · Notes", <PhoneFrame theme="light" hideStatus label="30 Notes"><BookmarksSheet theme="light" tab="notes" /></PhoneFrame>)}
    </DCSection>

    {/* ──────── ANDROID ──────── */}
    <DCSection id="android" title="5 · Android — Material 3" subtitle="Same product. M3 surfaces, extended FAB for reader menu, ripple-style nav indicator, no faux iOS glass.">
      {Board("and-home", "31 · Android · Home", <AndroidFrame theme="light" label="31 Android Home"><AndroidHome theme="light" /></AndroidFrame>)}
      {Board("and-reader", "32 · Android · Reader", <AndroidFrame theme="light" label="32 Android Reader"><AndroidReader theme="light" /></AndroidFrame>)}
      {Board("and-reader-dark", "33 · Android · Reader dark", <AndroidFrame theme="dark" label="33 Android Reader dark"><AndroidReader theme="dark" /></AndroidFrame>)}
      {Board("and-menu", "34 · Android · Reader menu", <AndroidFrame theme="light" label="34 Android Reader menu"><AndroidReaderMenu theme="light" /></AndroidFrame>)}
      {Board("and-paywall", "35 · Android · Paywall", <AndroidFrame theme="light" label="35 Android Paywall"><AndroidPaywall theme="light" /></AndroidFrame>)}
    </DCSection>

    {/* ──────── DESIGN SYSTEM ──────── */}
    <DCSection id="system" title="6 · Design system" subtitle="shadcn preset b2oE7c0Mi — green primary, zinc neutrals, Outfit type, small radius. Light + dark match the shadcn dashboards verbatim.">
      <DCArtboard id="ds-logo" label="36 · Logo + wordmark" width={820} height={360}>
        <DesignSystemLogo />
      </DCArtboard>
      <DCArtboard id="ds-colors" label="37 · Color tokens" width={820} height={460}>
        <DesignSystemColors />
      </DCArtboard>
      <DCArtboard id="ds-type" label="38 · Typography" width={820} height={500}>
        <DesignSystemType />
      </DCArtboard>
      <DCArtboard id="ds-components" label="39 · Components" width={820} height={620}>
        <DesignSystemComponents />
      </DCArtboard>
    </DCSection>
  </DesignCanvas>
);

// ──────── DESIGN SYSTEM CARDS ────────
const Swatch = ({ name, value }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px', borderRadius: 8, background: 'oklch(0.985 0.001 286.375)', border: '1px solid oklch(0.92 0.004 286.32)' }}>
    <div style={{ width: 30, height: 30, borderRadius: 6, background: value, border: '1px solid rgba(0,0,0,.08)' }} />
    <div style={{ minWidth: 0 }}>
      <div style={{ fontSize: 11.5, fontWeight: 600, color: 'oklch(0.141 0.005 285.823)', letterSpacing: '-0.005em' }}>{name}</div>
      <div style={{ fontSize: 9.5, color: 'oklch(0.552 0.016 285.938)', fontFamily: 'ui-monospace, monospace', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 145 }}>{value}</div>
    </div>
  </div>
);

const DesignSystemLogo = () => {
  const t = themes.light;
  return (
    <div style={{ padding: 32, background: '#fff', height: '100%', color: t.text, fontFamily: 'Outfit, system-ui, sans-serif' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginBottom: 24 }}>
        <div style={{ fontSize: 24, fontWeight: 600, letterSpacing: '-0.02em' }}>Logo</div>
        <div style={{ fontSize: 12, color: t.textSec }}>Crescent + opened book. Quiet, geometric, no clip-art motifs.</div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 18 }}>
        <div style={{ padding: 30, background: '#fff', border: `1px solid ${t.hair}`, borderRadius: 12, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
          <HadithlyMark size={80} color={t.text} />
          <div style={{ fontSize: 11, color: t.textSec, letterSpacing: '0.06em', textTransform: 'uppercase' }}>Mark · light</div>
        </div>
        <div style={{ padding: 30, background: t.text, borderRadius: 12, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
          <HadithlyMark size={80} color="#fff" />
          <div style={{ fontSize: 11, color: '#fff', letterSpacing: '0.06em', textTransform: 'uppercase' }}>Mark · dark</div>
        </div>
        <div style={{ padding: 30, background: t.accent, borderRadius: 12, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
          <HadithlyMark size={80} color="#fff" />
          <div style={{ fontSize: 11, color: '#fff', letterSpacing: '0.06em', textTransform: 'uppercase' }}>On primary</div>
        </div>
      </div>
      <div style={{ marginTop: 20, padding: '20px 24px', background: t.surface2, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 18 }}>
        <HadithlyMark size={44} color={t.text} />
        <div style={{ fontSize: 36, fontWeight: 600, letterSpacing: '-0.025em' }}>Hadithly</div>
        <div style={{ flex: 1 }} />
        <div className="arabic" style={{ fontSize: 22, color: t.textSec }}>حَدِيْثلِيْ</div>
      </div>
    </div>
  );
};

const DesignSystemColors = () => (
  <div style={{ padding: 30, background: '#fff', height: '100%', overflowY: 'auto', color: 'oklch(0.141 0.005 285.823)', fontFamily: 'Outfit, system-ui, sans-serif' }}>
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginBottom: 12 }}>
      <div style={{ fontSize: 24, fontWeight: 600, letterSpacing: '-0.02em' }}>Colors</div>
      <div style={{ fontSize: 12, color: 'oklch(0.552 0.016 285.938)' }}>shadcn preset b2oE7c0Mi · zinc neutrals · green primary · gold rare detail</div>
    </div>
    <div style={{ marginTop: 16 }}>
      <div style={{ fontSize: 11, fontWeight: 600, color: 'oklch(0.552 0.016 285.938)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Light</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {Object.entries(themes.light).slice(0, 16).map(([k, v]) => <Swatch key={k} name={k} value={v} />)}
      </div>
    </div>
    <div style={{ marginTop: 18 }}>
      <div style={{ fontSize: 11, fontWeight: 600, color: 'oklch(0.552 0.016 285.938)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Dark</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {Object.entries(themes.dark).slice(0, 16).map(([k, v]) => <Swatch key={k} name={k} value={v} />)}
      </div>
    </div>
    <div style={{ marginTop: 18 }}>
      <div style={{ fontSize: 11, fontWeight: 600, color: 'oklch(0.552 0.016 285.938)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Sepia · reader-only</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {Object.entries(themes.sepia).slice(0, 12).map(([k, v]) => <Swatch key={k} name={k} value={v} />)}
      </div>
    </div>
  </div>
);

const DesignSystemType = () => (
  <div style={{ padding: 30, background: '#fff', height: '100%', overflowY: 'auto', color: 'oklch(0.141 0.005 285.823)', fontFamily: 'Outfit, system-ui, sans-serif' }}>
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginBottom: 18 }}>
      <div style={{ fontSize: 24, fontWeight: 600, letterSpacing: '-0.02em' }}>Typography</div>
      <div style={{ fontSize: 12, color: 'oklch(0.552 0.016 285.938)' }}>UI · Outfit  ·  Translation serif · Literata  ·  Arabic · Amiri Quran</div>
    </div>

    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 28 }}>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: 'oklch(0.552 0.016 285.938)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 6 }}>Arabic reader</div>
        <div className="arabic" style={{ fontSize: 30, lineHeight: 2.05, textAlign: 'right' }}>إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ</div>
        <div style={{ fontSize: 11, color: 'oklch(0.552 0.016 285.938)', marginTop: 4, fontFamily: 'ui-monospace, monospace' }}>Amiri Quran · 26–30pt · lh 2.0–2.2</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: 'oklch(0.552 0.016 285.938)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 6 }}>Translation serif</div>
        <div className="serif" style={{ fontSize: 18, lineHeight: 1.7 }}>Actions are but by intention, and every man shall have only that which he intended.</div>
        <div style={{ fontSize: 11, color: 'oklch(0.552 0.016 285.938)', marginTop: 4, fontFamily: 'ui-monospace, monospace' }}>Literata · 16–18pt · lh 1.65–1.85</div>
      </div>

      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: 'oklch(0.552 0.016 285.938)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 6 }}>Display</div>
        <div style={{ fontSize: 32, fontWeight: 600, lineHeight: 1.1, letterSpacing: '-0.025em' }}>Bring hadith to every language</div>
        <div style={{ fontSize: 11, color: 'oklch(0.552 0.016 285.938)', marginTop: 4, fontFamily: 'ui-monospace, monospace' }}>Outfit Semibold · 24–40pt</div>
      </div>

      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: 'oklch(0.552 0.016 285.938)', letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 8 }}>UI scale</div>
        <div style={{ fontSize: 22, fontWeight: 600, letterSpacing: '-0.015em' }}>Title 22/28</div>
        <div style={{ fontSize: 16, fontWeight: 600, marginTop: 6 }}>Section 16/22</div>
        <div style={{ fontSize: 14, fontWeight: 400, marginTop: 4 }}>Body 14/22 — Outfit regular</div>
        <div style={{ fontSize: 12, fontWeight: 500, color: 'oklch(0.552 0.016 285.938)', marginTop: 4 }}>Caption 12/16</div>
        <div style={{ fontSize: 10, fontWeight: 600, color: 'oklch(0.705 0.015 286.067)', marginTop: 4, letterSpacing: '0.04em' }}>MICRO 10/14</div>
      </div>
    </div>
  </div>
);

const DesignSystemComponents = () => {
  const t = themes.light;
  return (
    <div style={{ padding: 30, background: '#fff', height: '100%', overflowY: 'auto', color: t.text, fontFamily: 'Outfit, system-ui, sans-serif' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginBottom: 18 }}>
        <div style={{ fontSize: 24, fontWeight: 600, letterSpacing: '-0.02em' }}>Components</div>
        <div style={{ fontSize: 12, color: t.textSec }}>shadcn primitives — adapted for React Native</div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 28 }}>
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: t.textSec, letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Buttons</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'flex-start' }}>
            <Button variant="primary" theme="light" iconRight={<Icon name="arrowR" size={14} />}>Primary</Button>
            <Button variant="secondary" theme="light">Secondary</Button>
            <Button variant="outline" theme="light">Outline</Button>
            <Button variant="ghost" theme="light">Ghost</Button>
            <Button variant="destructive" theme="light">Destructive</Button>
          </div>
        </div>

        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: t.textSec, letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Chips · badges</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            <Chip variant="primary" theme="light">Primary</Chip>
            <Chip variant="secondary" theme="light">Secondary</Chip>
            <Chip variant="outline" theme="light">Outline</Chip>
            <Chip variant="soft" theme="light">Soft</Chip>
            <Chip variant="outline" theme="light" tone="danger">Destructive</Chip>
            <Chip variant="outline" theme="light" tone="warning">Warning</Chip>
            <Chip variant="outline" theme="light">Sahih</Chip>
            <Chip variant="outline" theme="light">Hasan</Chip>
            <Chip variant="soft" theme="light"><Icon name="sparkle" size={9} color={t.accent} />AI</Chip>
            <Chip variant="soft" theme="light" style={{ color: t.gold, background: `${t.gold}1f` }}>Community</Chip>
            <Chip variant="secondary" theme="light">Official EN</Chip>
            <Chip variant="primary" theme="light"><Icon name="crown" size={10} color={t.primaryFg} />Pro</Chip>
          </div>
        </div>

        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: t.textSec, letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Switches</div>
          <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
            <Switch on theme="light" /><Switch on={false} theme="light" />
            <Switch on theme="light" small /><Switch on={false} theme="light" small />
          </div>
        </div>

        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: t.textSec, letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Segmented</div>
          <Segmented theme="light" options={['Bookmarks', 'Favorites', 'Notes']} value="Bookmarks" />
        </div>

        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: t.textSec, letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Progress</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7, maxWidth: 260 }}>
            <ProgressBar value={11} theme="light" />
            <ProgressBar value={88} theme="light" color={t.gold} />
            <ProgressBar theme="light" height={6} segments={[
              { value: 4, color: t.gold },
              { value: 26, color: t.accent },
              { value: 6, color: t.warning },
              { value: 64, color: 'oklch(0.85 0.005 285)' },
            ]} />
          </div>
        </div>

        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: t.textSec, letterSpacing: '0.06em', textTransform: 'uppercase', marginBottom: 10 }}>Hadith metadata row</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
              <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>1:1</span>
              <Chip variant="outline" theme="light" size="xs">Sahih</Chip>
              <Chip variant="soft" theme="light" size="xs"><Icon name="sparkle" size={9} color={t.accent} />AI</Chip>
              <span style={{ fontSize: 11, color: t.textSec }}>94%</span>
              <Icon name="thumbUp" size={13} color={t.textTer} />
              <Icon name="thumbDown" size={13} color={t.textTer} />
            </div>
            <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
              <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>2:8</span>
              <Chip variant="outline" theme="light" size="xs">Sahih</Chip>
              <Chip variant="soft" theme="light" size="xs" style={{ color: t.gold, background: `${t.gold}1f` }}>Community</Chip>
              <span style={{ fontSize: 11, color: t.textTer }}>New</span>
              <Icon name="thumbUp" size={13} color={t.textTer} />
              <Icon name="thumbDown" size={13} color={t.textTer} />
            </div>
            <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
              <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>2517</span>
              <Chip variant="outline" theme="light" size="xs">Hasan Sahih</Chip>
              <Chip variant="secondary" theme="light" size="xs">Official EN</Chip>
              <span style={{ fontSize: 11, color: t.textTer }}>—</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
