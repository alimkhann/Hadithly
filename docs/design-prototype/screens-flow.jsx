// Onboarding / flow — Splash, Welcome, Language, Notification, Preview,
// Auth, Soft paywall, Quota paywall. Now with shadcn type, inspirational quote.

const SplashScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  // Inject one-time keyframes for the splash motion
  useEffect(() => {
    if (document.getElementById('splash-kf')) return;
    const s = document.createElement('style');
    s.id = 'splash-kf';
    s.textContent = `
      @keyframes splash-breath { 0%,100% { transform: scale(1); opacity: 1 } 50% { transform: scale(1.04); opacity: .92 } }
      @keyframes splash-ring { 0% { transform: rotate(0deg) scale(1); opacity: .35 } 50% { opacity: .55 } 100% { transform: rotate(360deg) scale(1); opacity: .35 } }
      @keyframes splash-rise { from { opacity: 0; transform: translateY(8px) } to { opacity: 1; transform: translateY(0) } }
      @keyframes splash-shimmer { 0% { transform: translateX(-100%) } 100% { transform: translateX(100%) } }
    `;
    document.head.appendChild(s);
  }, []);
  const isDark = theme === 'dark';
  return (
    <div style={{
      width: '100%', height: '100%', position: 'absolute', inset: 0,
      // Layered: deep paper + soft green halo behind the mark
      background: isDark
        ? 'radial-gradient(110% 70% at 50% 38%, oklch(0.30 0.06 152 / 0.55) 0%, oklch(0.18 0.02 285) 45%, oklch(0.10 0.005 285) 100%)'
        : 'radial-gradient(110% 70% at 50% 38%, oklch(0.95 0.05 152 / 0.8) 0%, oklch(0.985 0.005 152) 45%, #fff 100%)',
      color: t.text, overflow: 'hidden',
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      gap: 18
    }}>
      {/* slowly-rotating decorative light ring behind the mark */}
      <div style={{
        position: 'absolute', top: '32%', left: '50%', width: 240, height: 240,
        transform: 'translate(-50%, -50%)',
        borderRadius: '50%',
        background: `conic-gradient(from 0deg, transparent 0deg, ${t.accent}33 60deg, transparent 180deg, ${t.accent}22 280deg, transparent 360deg)`,
        animation: 'splash-ring 24s linear infinite',
        filter: 'blur(28px)', opacity: 0.6,
      }} />
      {/* faint inner ring outline */}
      <div style={{
        position: 'absolute', top: '32%', left: '50%', width: 168, height: 168,
        transform: 'translate(-50%, -50%)',
        borderRadius: '50%',
        border: `1px solid ${isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.05)'}`,
      }} />
      {/* mark with slow breath */}
      <div style={{
        animation: 'splash-breath 5s ease-in-out infinite',
        filter: isDark ? `drop-shadow(0 0 28px ${t.accent}66)` : `drop-shadow(0 4px 18px ${t.accent}44)`,
        zIndex: 1,
      }}>
        <HadithlyMark size={84} color={t.text} />
      </div>
      <div className="display" style={{
        fontSize: 38, fontWeight: 600, letterSpacing: '-0.025em',
        animation: 'splash-rise .8s ease-out .2s both', position: 'relative',
        background: isDark
          ? `linear-gradient(180deg, ${t.text} 0%, ${t.textSec} 100%)`
          : `linear-gradient(180deg, ${t.text} 0%, oklch(0.30 0.005 285) 100%)`,
        WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent',
      }}>Hadithly</div>
      <div className="arabic" style={{
        fontSize: 18, color: t.textSec, marginTop: -12,
        animation: 'splash-rise .8s ease-out .35s both',
      }}>حَدِيْثلِيْ</div>

      {/* hairline shimmer separator */}
      <div style={{
        position: 'absolute', bottom: 132, width: 60, height: 1,
        background: t.hair, overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', inset: 0,
          background: `linear-gradient(90deg, transparent, ${t.accent}, transparent)`,
          animation: 'splash-shimmer 2.4s ease-in-out infinite',
        }} />
      </div>
      <div style={{
        position: 'absolute', bottom: 100, fontSize: 12, color: t.textTer,
        letterSpacing: '0.06em', textTransform: 'uppercase', fontWeight: 500,
        animation: 'splash-rise .8s ease-out .5s both',
      }}>
        Read the words that lit a world
      </div>
    </div>);

};

// Welcome — adds a centered inspirational hadith excerpt
const WelcomeScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ width: '100%', height: '100%', padding: '40px 28px 30px', display: 'flex', flexDirection: 'column' }}>
      <HadithlyMark size={36} color={t.text} />
      <div className="display" style={{
        marginTop: 30, fontSize: 38, lineHeight: 1.05, color: t.text, letterSpacing: '-0.025em', fontWeight: 600
      }}>
        Read hadith<br />in your language.
      </div>
      <div style={{
        fontSize: 16, lineHeight: 1.5, color: t.textSec, marginTop: 16,
        maxWidth: 320, letterSpacing: '-0.005em'
      }}>
        Arabic and English source text — with translations into your language, generated on the spot when missing and improved over time by the community.
      </div>

      {/* Inspirational quote */}
      <div style={{
        marginTop: 28, padding: '20px 20px 18px', borderRadius: RADIUS.lg,
        background: t.surface, border: `1px solid ${t.hair}`,
        position: 'relative'
      }}>
        <div style={{ position: 'absolute', top: -1, left: 16, padding: '0 8px', background: t.bg, fontSize: 10, color: t.textTer, letterSpacing: '0.06em', textTransform: 'uppercase', fontWeight: 600, transform: 'translateY(-50%)' }}>
          A reminder
        </div>
        <div className="arabic" style={{ fontSize: 20, lineHeight: 1.85, color: t.text, textAlign: 'right', marginBottom: 10 }}>
          طَلَبُ الْعِلْمِ فَرِيضَةٌ عَلَى كُلِّ مُسْلِمٍ
        </div>
        <div className="serif" style={{ fontSize: 14.5, lineHeight: 1.55, color: t.textSec }}>
          "The seeking of knowledge is an obligation upon every Muslim."
        </div>
        <div style={{ fontSize: 11, color: t.textTer, marginTop: 8, letterSpacing: '-0.005em' }}>— Ibn Majah 224</div>
      </div>

      <div style={{ flex: 1 }} />
      <Button variant="primary" theme={theme} size="lg" block iconRight={<Icon name="arrowR" size={16} />}>Begin</Button>
      <div style={{ marginTop: 12, textAlign: 'center', fontSize: 11.5, color: t.textTer, letterSpacing: '-0.005em' }}>
        By continuing you agree to our <span style={{ color: t.accent }}>Terms</span> and <span style={{ color: t.accent }}>Privacy</span>.
      </div>
    </div>);

};

const LanguageScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  const selected = 'ru';
  return (
    <div style={{ width: '100%', height: '100%', padding: '24px 22px 30px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 22 }}>
        <IconButton name="chevronL" theme={theme} size={32} iconSize={18} />
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: t.surface2, overflow: 'hidden' }}>
          <div style={{ width: '33%', height: '100%', background: t.accent, transition: 'width .3s' }} />
        </div>
        <div style={{ fontSize: 12, color: t.textSec, fontWeight: 500 }}>1/3</div>
      </div>

      <div className="display" style={{ fontSize: 28, lineHeight: 1.1, color: t.text, letterSpacing: '-0.022em', fontWeight: 600 }}>
        Choose your<br />reading language
      </div>
      <div style={{ fontSize: 14.5, lineHeight: 1.5, color: t.textSec, marginTop: 10, maxWidth: 320 }}>
        Hadithly shows coverage per language. Missing translations are generated automatically.
      </div>

      <div style={{
        marginTop: 18, flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 2,
        marginLeft: -2, marginRight: -2
      }}>
        {LANGUAGES.map((lang) => {
          const isSel = lang.code === selected;
          return (
            <div key={lang.code} style={{
              padding: '12px 14px', borderRadius: RADIUS.md,
              background: isSel ? theme === 'dark' ? `${themes[theme].accent}1a` : 'oklch(0.97 0.04 152)' : 'transparent',
              border: `1px solid ${isSel ? t.accent : 'transparent'}`,
              display: 'flex', alignItems: 'center', gap: 12, transition: 'all .15s'
            }}>
              <span style={{ fontSize: 22 }}>{lang.flag}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                  <div style={{ fontSize: 15.5, fontWeight: 600, color: t.text, letterSpacing: '-0.005em' }}>{lang.en}</div>
                  <div style={{ fontSize: 13, color: t.textSec }}>{lang.native}</div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 4 }}>
                  {lang.status === 'Official' && <Chip variant="secondary" theme={theme} size="xs">Official</Chip>}
                  {lang.status === 'Source' && <Chip variant="outline" theme={theme} size="xs">Source</Chip>}
                  {lang.status === 'community' &&
                  <>
                      <span style={{ fontSize: 11.5, color: t.textSec }}>{lang.coverage}% community</span>
                      <span style={{ fontSize: 10, color: t.textTer }}>·</span>
                      <span style={{ fontSize: 11.5, color: t.accent, fontWeight: 500, display: 'inline-flex', alignItems: 'center', gap: 3 }}>
                        <Icon name="sparkle" size={10} color={t.accent} /> AI on demand
                      </span>
                    </>
                  }
                </div>
              </div>
              <div style={{
                width: 22, height: 22, borderRadius: '50%',
                border: `1.5px solid ${isSel ? t.accent : t.hair}`,
                background: isSel ? t.accent : 'transparent',
                display: 'flex', alignItems: 'center', justifyContent: 'center'
              }}>
                {isSel && <Icon name="check" size={13} color={t.primaryFg} strokeWidth={2.5} />}
              </div>
            </div>);

        })}
      </div>
      <Button variant="primary" theme={theme} size="lg" block style={{ marginTop: 14 }} iconRight={<Icon name="arrowR" size={15} />}>Continue</Button>
    </div>);

};

const NotificationScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ width: '100%', height: '100%', padding: '24px 22px 30px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 22 }}>
        <IconButton name="chevronL" theme={theme} size={32} iconSize={18} />
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: t.surface2, overflow: 'hidden' }}>
          <div style={{ width: '66%', height: '100%', background: t.accent }} />
        </div>
        <div style={{ fontSize: 12, color: t.textSec, fontWeight: 500 }}>2/3</div>
      </div>

      <div className="display" style={{ fontSize: 28, lineHeight: 1.1, color: t.text, letterSpacing: '-0.022em', fontWeight: 600 }}>
        A hadith,<br />every morning.
      </div>
      <div style={{ fontSize: 14.5, lineHeight: 1.5, color: t.textSec, marginTop: 10, maxWidth: 320 }}>
        One short hadith delivered at a time you choose, in the language you read.
      </div>

      {/* Preview notification — looks like an iOS push */}
      <div style={{
        marginTop: 22, padding: '12px 14px', borderRadius: RADIUS.lg,
        background: theme === 'dark' ? 'oklch(0.24 0.005 285)' : 'rgba(255,255,255,0.85)',
        backdropFilter: 'blur(14px)', WebkitBackdropFilter: 'blur(14px)',
        border: `1px solid ${t.hair}`, display: 'flex', gap: 11, alignItems: 'flex-start',
        boxShadow: theme === 'light' ? '0 4px 16px rgba(0,0,0,0.04)' : 'none'
      }}>
        <div style={{
          width: 38, height: 38, borderRadius: 9, background: t.text, flexShrink: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center'
        }}>
          <HadithlyMark size={22} color={t.bg} />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ fontSize: 13, fontWeight: 600, color: t.text }}>Hadithly</div>
            <div style={{ fontSize: 11, color: t.textTer }}>now</div>
          </div>
          <div style={{ fontSize: 13.5, color: t.text, marginTop: 2, lineHeight: 1.35, fontWeight: 500 }}>Today's hadith — 1:1</div>
          <div style={{ fontSize: 12.5, color: t.textSec, marginTop: 1, lineHeight: 1.4 }}>
            Actions are but by intention, and every man shall have only that which he intended…
          </div>
        </div>
      </div>

      <Card theme={theme} style={{ marginTop: 22, padding: '4px 16px' }}>
        <Row theme={theme} noBorder title="Daily hadith" subtitle="One short hadith each morning"
        trailing={<Switch on theme={theme} />} />
        <Row theme={theme} noBorder title="Time" subtitle="07:30 — local"
        style={{ borderTop: `1px solid ${t.hair}` }}
        trailing={<Icon name="chevronR" size={17} color={t.textTer} />} />
        <Row theme={theme} noBorder title="Notification language" subtitle="Russian"
        style={{ borderTop: `1px solid ${t.hair}` }}
        trailing={<Icon name="chevronR" size={17} color={t.textTer} />} />
      </Card>

      <div style={{ flex: 1 }} />
      <Button variant="primary" theme={theme} size="lg" block>Allow notifications</Button>
      <Button variant="ghost" theme={theme} size="md" block style={{ marginTop: 4, color: t.textSec }}>Not now</Button>
    </div>);

};

// Preview / aha moment — same hadith in 3 languages, AI generates Russian
const PreviewScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ width: '100%', height: '100%', padding: '24px 22px 30px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 22 }}>
        <IconButton name="chevronL" theme={theme} size={32} iconSize={18} />
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: t.surface2, overflow: 'hidden' }}>
          <div style={{ width: '100%', height: '100%', background: t.accent }} />
        </div>
        <div style={{ fontSize: 12, color: t.textSec, fontWeight: 500 }}>3/3</div>
      </div>

      <div className="display" style={{ fontSize: 26, lineHeight: 1.12, color: t.text, letterSpacing: '-0.022em', fontWeight: 600 }}>
        The same hadith,<br />in your language.
      </div>
      <div style={{ fontSize: 14, lineHeight: 1.5, color: t.textSec, marginTop: 8 }}>
        When a translation is missing, AI generates one instantly. The community improves it over time.
      </div>

      <Card theme={theme} style={{ marginTop: 16, padding: '14px 16px 16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 10, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500, marginRight: 1 }}>1:1</span>
          <Chip variant="outline" theme={theme} size="xs">Sahih</Chip>
          <Chip variant="soft" theme={theme} size="xs"><Icon name="sparkle" size={9} color={t.accent} />AI</Chip>
          <span style={{ fontSize: 10.5, color: t.textTer }}>New</span>
        </div>
        <div className="arabic" style={{ fontSize: 21, lineHeight: 2, color: t.text, textAlign: 'right', marginBottom: 12 }}>
          إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ
        </div>
        <div className="serif" style={{ fontSize: 14, lineHeight: 1.65, color: t.text, marginBottom: 14 }}>
          Actions are but by intention, and every man shall have only that which he intended.
        </div>
        <div style={{ height: 1, background: t.hair, margin: '0 0 12px' }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 7 }}>
          <Chip variant="soft" theme={theme} size="xs"><Icon name="sparkle" size={9} color={t.accent} />Russian · just now</Chip>
        </div>
        <div className="serif" style={{ fontSize: 14, lineHeight: 1.65, color: t.textSec, fontStyle: 'italic' }}>
          Поистине, дела оцениваются по намерениям, и каждому достанется лишь то, что он намеревался обрести.
        </div>
      </Card>

      <div style={{ flex: 1 }} />
      <Button variant="primary" theme={theme} size="lg" block iconRight={<Icon name="arrowR" size={15} />}>Show me the reader</Button>
    </div>);

};

const AuthScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ width: '100%', height: '100%', padding: '40px 24px 30px', display: 'flex', flexDirection: 'column' }}>
      <HadithlyMark size={32} color={t.text} />
      <div className="display" style={{ marginTop: 30, fontSize: 30, lineHeight: 1.1, color: t.text, letterSpacing: '-0.022em', fontWeight: 600 }}>
        Sign in to sync
      </div>
      <div style={{ fontSize: 14.5, lineHeight: 1.5, color: t.textSec, marginTop: 10, maxWidth: 320 }}>
        Keep notes, bookmarks, and contributions across devices. Or continue as a guest.
      </div>

      <div style={{ marginTop: 32, display: 'flex', flexDirection: 'column', gap: 10 }}>
        <Button variant="secondary" theme={theme} size="lg" block style={{ background: '#000', color: '#fff' }} icon={<Icon name="apple" size={18} color="#fff" />}>Continue with Apple</Button>
        <Button variant="outline" theme={theme} size="lg" block icon={<Icon name="google" size={18} />}>Continue with Google</Button>
        <Button variant="outline" theme={theme} size="lg" block icon={<Icon name="mail" size={18} />}>Continue with email</Button>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 10, margin: '28px 0 20px' }}>
        <div style={{ flex: 1, height: 1, background: t.hair }} />
        <span style={{ fontSize: 10.5, color: t.textTer, letterSpacing: '0.06em', textTransform: 'uppercase', fontWeight: 600 }}>or</span>
        <div style={{ flex: 1, height: 1, background: t.hair }} />
      </div>

      <Button variant="ghost" theme={theme} size="md" block style={{ color: t.textSec }}>Continue as guest</Button>

      <div style={{ flex: 1 }} />
      <div style={{ fontSize: 11.5, color: t.textTer, textAlign: 'center', lineHeight: 1.5, maxWidth: 280, alignSelf: 'center' }}>
        Your reading is yours. We don't share notes, bookmarks, or vote activity.
      </div>
    </div>);

};

const SoftPaywallScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ width: '100%', height: '100%', padding: '16px 24px 22px', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <IconButton name="close" theme={theme} size={32} iconSize={16} variant="secondary" />
      </div>
      <div style={{ marginTop: 4, display: 'flex', justifyContent: 'center' }}>
        <div style={{
          width: 60, height: 60, borderRadius: RADIUS.lg,
          background: t.accent, color: t.primaryFg,
          display: 'flex', alignItems: 'center', justifyContent: 'center'
        }}>
          <HadithlyMark size={36} color={t.primaryFg} />
        </div>
      </div>
      <div className="display" style={{
        marginTop: 18, fontSize: 28, lineHeight: 1.1, color: t.text, letterSpacing: '-0.025em',
        textAlign: 'center', fontWeight: 600
      }}>Bring hadith to<br />every language</div>
      <div style={{ fontSize: 14, lineHeight: 1.5, color: t.textSec, marginTop: 8, textAlign: 'center', maxWidth: 320, alignSelf: 'center' }}>
        Pro funds AI translations and helps the community improve them.
      </div>

      <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 11 }}>
        {[
        ['500 AI translations / month', 'sparkle'],
        ['Priority translation queue', 'flame'],
        ['Offline language packs', 'download'],
        ['Advanced contribution tools', 'edit']].
        map(([label, icon]) =>
        <div key={label} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <Icon name="check" size={18} color={t.accent} strokeWidth={2.5} />
            <div style={{ fontSize: 14.5, color: t.text, letterSpacing: '-0.005em' }}>{label}</div>
          </div>
        )}
      </div>

      <div style={{ marginTop: 22, display: 'flex', gap: 10 }}>
        <Card theme={theme} padding={14} style={{ flex: 1 }}>
          <div style={{ fontSize: 11.5, color: t.textSec, fontWeight: 500, letterSpacing: '-0.005em' }}>Monthly</div>
          <div className="display" style={{ fontSize: 22, color: t.text, marginTop: 4, fontWeight: 600, letterSpacing: '-0.015em' }}>$3.99</div>
          <div style={{ fontSize: 11, color: t.textTer, marginTop: 1 }}>per month</div>
        </Card>
        <Card theme={theme} padding={14} style={{ flex: 1, borderColor: t.accent, position: 'relative', background: theme === 'dark' ? `${t.accent}1a` : 'oklch(0.97 0.04 152)' }}>
          <div style={{
            position: 'absolute', top: -9, right: 10, padding: '2px 8px', borderRadius: RADIUS.md - 2,
            background: t.accent, color: t.primaryFg, fontSize: 9.5, fontWeight: 700, letterSpacing: '0.04em'
          }}>BEST VALUE</div>
          <div style={{ fontSize: 11.5, color: t.accent, fontWeight: 600 }}>Annual</div>
          <div className="display" style={{ fontSize: 22, color: t.text, marginTop: 4, fontWeight: 600, letterSpacing: '-0.015em' }}>$29.99</div>
          <div style={{ fontSize: 11, color: t.textTer, marginTop: 1 }}>≈ $2.50 / month</div>
        </Card>
      </div>

      <div style={{ flex: 1 }} />
      <Button variant="primary" theme={theme} size="lg" block style={{ marginTop: 14 }}>Start 3-day free trial</Button>
      <Button variant="ghost" theme={theme} size="md" block style={{ marginTop: 4, color: t.textSec }}>Continue free</Button>
      <div style={{ marginTop: 8, display: 'flex', justifyContent: 'center', gap: 14, fontSize: 11, color: t.textTer }}>
        <span>Restore</span><span>·</span><span>Terms</span><span>·</span><span>Privacy</span>
      </div>
    </div>);

};

const QuotaPaywallScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ width: '100%', height: '100%', padding: '16px 24px 22px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <IconButton name="close" theme={theme} size={32} iconSize={16} variant="secondary" />
      </div>

      <Card theme={theme} style={{ marginTop: 6, padding: '14px 16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
          <Icon name="info" size={16} color={t.warning} />
          <div style={{ fontSize: 13, color: t.text, fontWeight: 600, letterSpacing: '-0.005em' }}>20 / 20 AI translations used this month</div>
        </div>
        <ProgressBar value={100} theme={theme} color={t.warning} height={5} />
        <div style={{ fontSize: 12, color: t.textSec, marginTop: 8, lineHeight: 1.45 }}>
          Resets June 1. Already-translated hadiths remain free to view, always.
        </div>
      </Card>

      <div className="display" style={{
        marginTop: 22, fontSize: 26, lineHeight: 1.15, color: t.text, letterSpacing: '-0.022em',
        fontWeight: 600
      }}>Continue translating<br />with AI</div>
      <div style={{ fontSize: 14, lineHeight: 1.5, color: t.textSec, marginTop: 8 }}>
        Pro raises your monthly limit to 500, plus priority queue and offline packs.
      </div>

      <Card theme={theme} style={{ marginTop: 18, padding: '14px 16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Chip variant="primary" theme={theme} size="xs">Pro</Chip>
            <span className="display" style={{ fontSize: 22, color: t.text, fontWeight: 600, letterSpacing: '-0.015em' }}>$29.99</span>
            <span style={{ fontSize: 12, color: t.textSec }}>/ year</span>
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7, fontSize: 13.5, color: t.text }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}><Icon name="sparkle" size={14} color={t.accent} /> 500 AI translations / month</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}><Icon name="flame" size={14} color={t.accent} /> Priority queue</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}><Icon name="download" size={14} color={t.accent} /> Offline language packs</div>
        </div>
      </Card>

      <div style={{ flex: 1 }} />
      <Button variant="primary" theme={theme} size="lg" block>Start 3-day trial · $29.99/yr</Button>
      <Button variant="outline" theme={theme} size="md" block style={{ marginTop: 8 }}>Monthly · $3.99</Button>
      <Button variant="ghost" theme={theme} size="md" block style={{ marginTop: 2, color: t.textSec }}>Not now</Button>
    </div>);

};

Object.assign(window, { SplashScreen, WelcomeScreen, LanguageScreen, NotificationScreen, PreviewScreen, AuthScreen, SoftPaywallScreen, QuotaPaywallScreen });