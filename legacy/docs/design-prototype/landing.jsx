// Hadithly — landing page
// Single-page React layout: hero, features grid, why-trust, pricing, CTA, testimonials, footer.
// Reuses tokens/components from the prototype. Green primary (shadcn preset).

const t = themes.light;

// ──────── Layout primitives ────────
const Container = ({ children, style, max = 1200 }) => (
  <div style={{ maxWidth: max, margin: '0 auto', padding: '0 28px', ...style }}>{children}</div>
);

const SectionTitle = ({ eyebrow, title, sub, align = 'center', style }) => (
  <div style={{ textAlign: align, ...style }}>
    {eyebrow && (
      <div style={{
        display: 'inline-block', padding: '5px 12px', borderRadius: 999,
        background: `${t.accent}1a`, color: t.accentText,
        fontSize: 12, fontWeight: 600, letterSpacing: '0.02em',
        border: `1px solid ${t.accent}22`,
      }}>{eyebrow}</div>
    )}
    <div className="display" style={{
      fontSize: 48, lineHeight: 1.05, letterSpacing: '-0.03em', fontWeight: 600,
      marginTop: eyebrow ? 18 : 0, color: t.text,
    }}>{title}</div>
    {sub && <div style={{
      fontSize: 16, color: t.textSec, marginTop: 14, lineHeight: 1.55,
      maxWidth: 580, margin: align === 'center' ? '14px auto 0' : '14px 0 0',
      letterSpacing: '-0.005em',
    }}>{sub}</div>}
  </div>
);

// App store buttons — black pill with subtitle + brand
const StoreButton = ({ kind = 'apple', dark = true }) => {
  const bg = dark ? '#0a0a0a' : '#fff';
  const color = dark ? '#fff' : '#0a0a0a';
  return (
    <a style={{
      display: 'inline-flex', alignItems: 'center', gap: 10,
      padding: '11px 18px', borderRadius: 12, background: bg, color,
      border: dark ? 'none' : `1px solid ${t.hair}`, cursor: 'pointer',
      fontFamily: 'Outfit, system-ui, sans-serif',
    }}>
      <Icon name={kind === 'apple' ? 'apple' : 'play'} size={22} color={color} />
      <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1.1 }}>
        <span style={{ fontSize: 9.5, opacity: 0.7, letterSpacing: '0.04em' }}>{kind === 'apple' ? 'Download on the' : 'GET IT ON'}</span>
        <span style={{ fontSize: 15.5, fontWeight: 600, marginTop: 1 }}>{kind === 'apple' ? 'App Store' : 'Google Play'}</span>
      </div>
    </a>
  );
};

// Tiny phone — wraps a PhoneFrame at a scaled size
const Phone = ({ children, scale = 0.72, label, theme = 'light' }) => {
  // Phone frame is 390x844; reserve space at scaled dimensions
  const w = Math.ceil(390 * scale);
  const h = Math.ceil(844 * scale);
  return (
    <div style={{ width: w, height: h, position: 'relative' }}>
      <div style={{ position: 'absolute', top: 0, left: 0, transformOrigin: 'top left', transform: `scale(${scale})` }}>
        <PhoneFrame theme={theme} label={label} hideStatus>{children}</PhoneFrame>
      </div>
    </div>
  );
};

// ──────── NAV ────────
const Nav = () => (
  <div style={{
    position: 'sticky', top: 0, zIndex: 20,
    background: 'rgba(255,255,255,0.8)', backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)',
    borderBottom: '1px solid rgba(0,0,0,0.04)',
  }}>
    <Container style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 28px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <HadithlyMark size={28} color={t.text} />
        <span style={{ fontSize: 21, fontWeight: 600, letterSpacing: '-0.025em' }}>Hadithly</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 30 }}>
        {[
          ['Home', true], ['Features', false], ['Screenshots', false], ['Pricing', false], ['FAQ', false], ['Contact', false],
        ].map(([l, active]) => (
          <a key={l} style={{
            fontSize: 14.5, fontWeight: 500, color: active ? t.text : t.textSec,
            letterSpacing: '-0.005em', position: 'relative',
          }}>
            {active && <span style={{ display: 'inline-block', width: 5, height: 5, borderRadius: 3, background: t.accent, marginRight: 7, verticalAlign: 'middle' }} />}
            {l}
          </a>
        ))}
      </div>
      <a style={{
        display: 'inline-flex', alignItems: 'center', gap: 8,
        padding: '10px 18px', borderRadius: 12, background: t.text, color: '#fff',
        fontSize: 14, fontWeight: 600, cursor: 'pointer', letterSpacing: '-0.005em',
      }}>
        Download app <Icon name="arrowR" size={14} color="#fff" />
      </a>
    </Container>
  </div>
);

// ──────── HERO ────────
const Hero = () => (
  <Container style={{ paddingTop: 60, paddingBottom: 40 }}>
    <div style={{
      position: 'relative', borderRadius: 32, overflow: 'hidden',
      // Layered green-tinted radial gradient backdrop
      background: `
        radial-gradient(circle at 15% 30%, oklch(0.95 0.05 152) 0%, transparent 45%),
        radial-gradient(circle at 90% 70%, oklch(0.93 0.04 80) 0%, transparent 50%),
        radial-gradient(circle at 50% 100%, oklch(0.94 0.05 152) 0%, transparent 60%),
        oklch(0.985 0.005 152)
      `,
      padding: '60px 28px 0',
      minHeight: 720,
    }}>
      <div style={{ textAlign: 'center' }}>
        <div style={{
          display: 'inline-block', padding: '5px 14px', borderRadius: 999,
          background: '#fff', color: t.accentText,
          fontSize: 12, fontWeight: 600, letterSpacing: '0.02em',
          border: `1px solid ${t.accent}33`,
        }}>The clear hadith reader</div>
      </div>
      <div className="display" style={{
        marginTop: 22, textAlign: 'center', fontSize: 64, lineHeight: 1.0, letterSpacing: '-0.035em', fontWeight: 600,
      }}>
        Read hadith in<br />your language.
      </div>
      <div style={{
        marginTop: 18, textAlign: 'center', fontSize: 17, color: t.textSec,
        lineHeight: 1.55, maxWidth: 540, margin: '18px auto 0', letterSpacing: '-0.005em',
      }}>
        Arabic and English source, AI-assisted translations into 30+ languages, and a community that keeps making them better — all in one calm reader.
      </div>
      <div style={{ display: 'flex', justifyContent: 'center', gap: 12, marginTop: 28 }}>
        <StoreButton kind="apple" />
        <StoreButton kind="google" />
      </div>

      {/* Phone composition — 3 phones layered */}
      <div style={{
        position: 'relative', marginTop: 50, height: 540,
        display: 'flex', justifyContent: 'center', alignItems: 'flex-start',
      }}>
        {/* Center phone — Reader (light) — slightly elevated */}
        <div style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', zIndex: 3 }}>
          <Phone theme="light" scale={0.72} label="hero-reader">
            <ReaderDefault theme="light" />
          </Phone>
        </div>
        {/* Left phone — Home, tilted left, recessed */}
        <div style={{ position: 'absolute', top: 36, left: '50%', transform: 'translateX(calc(-50% - 230px)) rotate(-6deg)', zIndex: 2 }}>
          <Phone theme="light" scale={0.62} label="hero-home">
            <HomeScreen theme="light" />
          </Phone>
        </div>
        {/* Right phone — Reader dark, tilted right */}
        <div style={{ position: 'absolute', top: 36, left: '50%', transform: 'translateX(calc(-50% + 230px)) rotate(6deg)', zIndex: 2 }}>
          <Phone theme="dark" scale={0.62} label="hero-dark">
            <ReaderDefault theme="dark" />
          </Phone>
        </div>

        {/* Floating callouts — small cards over the phones */}
        <div style={{
          position: 'absolute', top: 76, left: 'calc(50% - 360px)', zIndex: 5,
          background: '#fff', padding: '10px 12px', borderRadius: 12,
          boxShadow: '0 12px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)',
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <div style={{ display: 'flex' }}>
            {['#A78BFA', '#F472B6', '#34D399'].map((c, i) => (
              <Avatar key={i} name={['Aa', 'Bb', 'Cc'][i]} color={c} size={22} style={{ marginLeft: i ? -7 : 0, border: '2px solid #fff' }} />
            ))}
          </div>
          <div style={{ fontSize: 11.5, lineHeight: 1.25 }}>
            <div style={{ fontWeight: 600, color: t.text }}>4k+ readers</div>
            <div style={{ color: t.textSec }}>across 30 languages</div>
          </div>
        </div>

        <div style={{
          position: 'absolute', top: 110, right: 'calc(50% - 410px)', zIndex: 5,
          background: '#fff', padding: '8px 12px', borderRadius: 12,
          boxShadow: '0 12px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <div style={{ width: 28, height: 28, borderRadius: 8, background: `${t.accent}1a`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="sparkle" size={15} color={t.accent} />
          </div>
          <div style={{ fontSize: 11.5, lineHeight: 1.25 }}>
            <div style={{ fontWeight: 600, color: t.text }}>AI translation</div>
            <div style={{ color: t.textSec }}>in 30+ languages</div>
          </div>
        </div>

        <div style={{
          position: 'absolute', bottom: 110, left: 'calc(50% - 280px)', zIndex: 5,
          background: '#fff', padding: '8px 12px', borderRadius: 12,
          boxShadow: '0 12px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <div style={{ width: 28, height: 28, borderRadius: 8, background: `${t.gold}22`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="bookmarkFill" size={14} color={t.gold} />
          </div>
          <div style={{ fontSize: 11.5, lineHeight: 1.25 }}>
            <div style={{ fontWeight: 600, color: t.text }}>247 saved</div>
            <div style={{ color: t.textSec }}>bookmarks & notes</div>
          </div>
        </div>
      </div>
    </div>
  </Container>
);

// ──────── FEATURES GRID ────────
const FeaturesGrid = () => {
  const features = [
    { icon: 'bookOpen', title: 'Beautiful, book-like reader', body: 'Continuous text, no cards. Arabic right-aligned. Translation right below. Light, dark, sepia.' },
    { icon: 'sparkle', title: 'AI when you need it', body: 'When a translation is missing, AI generates one instantly. Every output labeled and rateable.' },
    { icon: 'shield', title: 'Authenticity, transparent', body: 'Grade and source dataset shown for every hadith. AI never decides authenticity.' },
    { icon: 'community', title: 'A humble community', body: 'Suggest better translations with a source. AI reviews quality. No flame wars, no public threads.' },
    { icon: 'bookmark', title: 'Bookmarks, favorites, notes', body: 'Sync across devices. Pin a passage, save a quote, add a thought.' },
    { icon: 'bell', title: 'A hadith every morning', body: 'One short hadith at the time you choose, in the language you read.' },
  ];
  return (
    <Container style={{ paddingTop: 100, paddingBottom: 80 }}>
      <SectionTitle eyebrow="Features" title={<>Everything you need.<br/>Nothing you don't.</>} sub="Sacred text deserves a calm, modern reader. Hadithly is built around that single idea." />

      <div style={{
        marginTop: 56, display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 18,
      }}>
        {/* Card 0 */}
        <FeatureCard {...features[0]} />
        {/* Center column — phone mockup spanning 2 rows */}
        <div style={{
          gridRow: 'span 2',
          borderRadius: 22, padding: '32px 20px 0', overflow: 'hidden',
          background: `linear-gradient(160deg, ${t.accent} 0%, oklch(0.42 0.13 152) 100%)`,
          position: 'relative',
          display: 'flex', flexDirection: 'column', alignItems: 'center',
        }}>
          <div style={{ color: '#fff', textAlign: 'center', marginBottom: 18 }}>
            <div className="display" style={{ fontSize: 22, fontWeight: 600, letterSpacing: '-0.02em' }}>The reader.</div>
            <div style={{ fontSize: 13.5, opacity: 0.85, marginTop: 4 }}>Open the book. Begin again.</div>
          </div>
          <div style={{ position: 'relative', flex: 1 }}>
            <Phone theme="dark" scale={0.7} label="feature-reader">
              <ReaderDefault theme="dark" />
            </Phone>
          </div>
        </div>
        {/* Card 1 */}
        <FeatureCard {...features[1]} />
        {/* Card 2 */}
        <FeatureCard {...features[2]} />
        {/* Card 3 */}
        <FeatureCard {...features[3]} />
      </div>
      <div style={{ display: 'flex', justifyContent: 'center', marginTop: 28 }}>
        <a style={{
          display: 'inline-flex', alignItems: 'center', gap: 8,
          padding: '10px 18px', borderRadius: 999, background: t.accent, color: '#fff',
          fontSize: 14, fontWeight: 600, cursor: 'pointer', letterSpacing: '-0.005em',
        }}>
          Explore all features <Icon name="arrowR" size={14} color="#fff" />
        </a>
      </div>
    </Container>
  );
};

const FeatureCard = ({ icon, title, body }) => (
  <div style={{
    padding: 24, borderRadius: 22, background: '#fff',
    border: `1px solid ${t.hair}`,
    display: 'flex', flexDirection: 'column', minHeight: 200,
  }}>
    <div style={{ width: 38, height: 38, borderRadius: 10, background: `${t.accent}1a`, color: t.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14 }}>
      <Icon name={icon} size={18} color={t.accent} />
    </div>
    <div style={{ fontSize: 16, fontWeight: 600, color: t.text, letterSpacing: '-0.01em', marginBottom: 6 }}>{title}</div>
    <div style={{ fontSize: 13.5, color: t.textSec, lineHeight: 1.55, flex: 1 }}>{body}</div>
    <a style={{ fontSize: 13, color: t.accent, fontWeight: 500, marginTop: 12, display: 'inline-flex', alignItems: 'center', gap: 4 }}>
      Learn more <Icon name="arrowR" size={12} color={t.accent} />
    </a>
  </div>
);

// ──────── WHY THOUSANDS TRUST ────────
const WhyTrust = () => (
  <div style={{ background: 'oklch(0.97 0.02 152)', padding: '90px 0 100px' }}>
    <Container>
      <SectionTitle eyebrow="Why readers stay" title={<>Built for the way you<br/>actually read.</>} sub="Three things matter most in a hadith reader: the text, the translation, and the trust. Hadithly takes each one seriously." />
      <div style={{ marginTop: 56, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 22 }}>
        {[
          { icon: 'bookOpen', title: 'A reader, not a feed', body: 'Continuous, book-like text. Hairlines between hadiths. No tappable cards bouncing for attention.', screen: 'reader' },
          { icon: 'sparkle', title: 'AI you can audit', body: 'Every translation is labeled by source. Rate, vote, or suggest a better one with a source link or screenshot.', screen: 'translation' },
          { icon: 'community', title: 'Calm community', body: 'AI reviews submissions for meaning preservation and glossary consistency. Humble leaderboards, no gamification creep.', screen: 'community' },
        ].map((c, i) => (
          <div key={i} style={{
            padding: 24, borderRadius: 22, background: '#fff',
            border: `1px solid ${t.hair}`,
          }}>
            <div style={{ width: 38, height: 38, borderRadius: 10, background: `${t.accent}1a`, color: t.accent, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14 }}>
              <Icon name={c.icon} size={18} color={t.accent} />
            </div>
            <div style={{ fontSize: 17, fontWeight: 600, color: t.text, letterSpacing: '-0.015em', marginBottom: 6 }}>{c.title}</div>
            <div style={{ fontSize: 13.5, color: t.textSec, lineHeight: 1.55, marginBottom: 20 }}>{c.body}</div>

            <div style={{
              borderRadius: 16, overflow: 'hidden', background: 'oklch(0.985 0.005 285)',
              padding: '14px 0 0', height: 280, position: 'relative',
            }}>
              <div style={{ position: 'absolute', top: 18, left: '50%', transform: 'translateX(-50%)' }}>
                <Phone theme="light" scale={0.55} label={`trust-${i}`}>
                  {c.screen === 'reader' && <ReaderDefault theme="light" />}
                  {c.screen === 'translation' && <TranslationDetailsSheet theme="light" />}
                  {c.screen === 'community' && <CommunityScreen theme="light" />}
                </Phone>
              </div>
            </div>
          </div>
        ))}
      </div>
    </Container>
  </div>
);

// ──────── PRICING ────────
const Pricing = () => (
  <Container style={{ paddingTop: 100, paddingBottom: 80 }}>
    <SectionTitle eyebrow="Pricing" title="Free forever. Pro when you need it." sub="Basic reading and cached translations remain free, always. Pro funds AI generation and offline access." />

    <div style={{ marginTop: 56, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 20 }}>
      {/* Free */}
      <div style={{
        padding: 28, borderRadius: 22, background: '#fff', border: `1px solid ${t.hair}`,
        display: 'flex', flexDirection: 'column',
      }}>
        <div style={{ width: 36, height: 36, borderRadius: 10, background: t.surface2, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14 }}>
          <Icon name="bookOpen" size={18} color={t.text} />
        </div>
        <div style={{ fontSize: 18, fontWeight: 600, letterSpacing: '-0.015em' }}>Free</div>
        <div className="display" style={{ fontSize: 44, fontWeight: 600, letterSpacing: '-0.03em', marginTop: 14, lineHeight: 1 }}>$0<span style={{ fontSize: 16, color: t.textSec, fontWeight: 500 }}> forever</span></div>
        <div style={{ fontSize: 13, color: t.textSec, marginTop: 4 }}>Everything that matters most.</div>
        <ul style={{ listStyle: 'none', padding: 0, margin: '22px 0', display: 'flex', flexDirection: 'column', gap: 9, flex: 1 }}>
          {['Full reader · Arabic + English', 'View all cached translations', '20 AI translations / month', 'Bookmarks, favorites, notes', 'Daily hadith notification'].map(l => (
            <li key={l} style={{ display: 'flex', alignItems: 'center', gap: 9, fontSize: 14, color: t.text, letterSpacing: '-0.005em' }}>
              <Icon name="check" size={16} color={t.accent} strokeWidth={2.2} /> {l}
            </li>
          ))}
        </ul>
        <a style={{ display: 'inline-flex', justifyContent: 'center', alignItems: 'center', padding: '12px 18px', borderRadius: 999, background: t.surface2, color: t.text, fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>Get started</a>
      </div>

      {/* Pro Annual — primary */}
      <div style={{
        padding: 28, borderRadius: 22, position: 'relative',
        background: `linear-gradient(160deg, ${t.accent} 0%, oklch(0.42 0.13 152) 100%)`,
        color: '#fff', display: 'flex', flexDirection: 'column',
        boxShadow: `0 24px 60px ${t.accent}33`,
      }}>
        <div style={{ position: 'absolute', top: -1, right: 18, padding: '5px 12px', borderRadius: '0 0 10px 10px', background: t.gold, color: '#fff', fontSize: 11, fontWeight: 700, letterSpacing: '0.04em' }}>MOST POPULAR</div>
        <div style={{ width: 36, height: 36, borderRadius: 10, background: 'rgba(255,255,255,0.18)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14 }}>
          <Icon name="sparkle" size={18} color="#fff" />
        </div>
        <div style={{ fontSize: 18, fontWeight: 600, letterSpacing: '-0.015em' }}>Pro · Annual</div>
        <div className="display" style={{ fontSize: 44, fontWeight: 600, letterSpacing: '-0.03em', marginTop: 14, lineHeight: 1 }}>$29.99<span style={{ fontSize: 16, opacity: 0.85, fontWeight: 500 }}> / year</span></div>
        <div style={{ fontSize: 13, opacity: 0.85, marginTop: 4 }}>≈ $2.50 / month · 3-day free trial.</div>
        <ul style={{ listStyle: 'none', padding: 0, margin: '22px 0', display: 'flex', flexDirection: 'column', gap: 9, flex: 1 }}>
          {['500 AI translations / month', 'Priority translation queue', 'Offline language packs', 'Advanced contribution tools', 'Everything in Free'].map(l => (
            <li key={l} style={{ display: 'flex', alignItems: 'center', gap: 9, fontSize: 14, letterSpacing: '-0.005em' }}>
              <Icon name="check" size={16} color="#fff" strokeWidth={2.2} /> {l}
            </li>
          ))}
        </ul>
        <a style={{ display: 'inline-flex', justifyContent: 'center', alignItems: 'center', padding: '12px 18px', borderRadius: 999, background: '#fff', color: t.text, fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>Start 3-day trial</a>
      </div>

      {/* Pro Monthly */}
      <div style={{
        padding: 28, borderRadius: 22, background: '#fff', border: `1px solid ${t.hair}`,
        display: 'flex', flexDirection: 'column',
      }}>
        <div style={{ width: 36, height: 36, borderRadius: 10, background: t.surface2, display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 14 }}>
          <Icon name="flame" size={18} color={t.text} />
        </div>
        <div style={{ fontSize: 18, fontWeight: 600, letterSpacing: '-0.015em' }}>Pro · Monthly</div>
        <div className="display" style={{ fontSize: 44, fontWeight: 600, letterSpacing: '-0.03em', marginTop: 14, lineHeight: 1 }}>$3.99<span style={{ fontSize: 16, color: t.textSec, fontWeight: 500 }}> / month</span></div>
        <div style={{ fontSize: 13, color: t.textSec, marginTop: 4 }}>Cancel anytime, no questions.</div>
        <ul style={{ listStyle: 'none', padding: 0, margin: '22px 0', display: 'flex', flexDirection: 'column', gap: 9, flex: 1 }}>
          {['500 AI translations / month', 'Priority translation queue', 'Offline language packs', 'Advanced contribution tools', 'Everything in Free'].map(l => (
            <li key={l} style={{ display: 'flex', alignItems: 'center', gap: 9, fontSize: 14, color: t.text, letterSpacing: '-0.005em' }}>
              <Icon name="check" size={16} color={t.accent} strokeWidth={2.2} /> {l}
            </li>
          ))}
        </ul>
        <a style={{ display: 'inline-flex', justifyContent: 'center', alignItems: 'center', padding: '12px 18px', borderRadius: 999, background: t.surface2, color: t.text, fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>Go monthly</a>
      </div>
    </div>

    <div style={{ marginTop: 28, textAlign: 'center', fontSize: 13, color: t.textSec }}>
      All prices in USD. Cached translations are always free to view.
    </div>
  </Container>
);

// ──────── DOWNLOAD CTA ────────
// Decorative QR-like grid (not a real QR, since we don't link anywhere real)
const QRCode = ({ size = 130 }) => {
  const cells = 21;
  const seed = (i, j) => {
    // deterministic pseudo-noise + finder pattern
    if ((i < 7 && j < 7) || (i < 7 && j > 13) || (i > 13 && j < 7)) {
      if (i === 0 || i === 6 || j === 0 || j === 6) return true;
      if (i >= 2 && i <= 4 && j >= 2 && j <= 4) return true;
      if (i === 1 || i === 5 || j === 1 || j === 5) return false;
      return false;
    }
    const x = (i * 73 + j * 137 + i * j * 13) % 100;
    return x < 48;
  };
  const s = size / cells;
  return (
    <div style={{
      width: size + 24, height: size + 24, background: '#fff', borderRadius: 14, padding: 12,
      boxShadow: '0 8px 20px rgba(0,0,0,0.1)',
    }}>
      <svg viewBox={`0 0 ${cells} ${cells}`} width={size} height={size}>
        {Array.from({ length: cells }).map((_, i) => (
          Array.from({ length: cells }).map((_, j) => (
            seed(i, j) ? <rect key={`${i}-${j}`} x={j} y={i} width="1" height="1" fill="#0a0a0a" /> : null
          ))
        ))}
      </svg>
    </div>
  );
};

const DownloadCTA = () => (
  <Container style={{ paddingTop: 40, paddingBottom: 80 }}>
    <div style={{
      borderRadius: 28, padding: '60px 28px',
      background: `
        radial-gradient(circle at 20% 30%, oklch(0.65 0.16 152) 0%, transparent 55%),
        radial-gradient(circle at 80% 70%, oklch(0.55 0.16 152) 0%, transparent 60%),
        linear-gradient(135deg, oklch(0.55 0.18 152) 0%, oklch(0.40 0.15 152) 100%)
      `,
      color: '#fff', position: 'relative', overflow: 'hidden',
      textAlign: 'center',
    }}>
      {/* decorative arabic flourish */}
      <div className="arabic" style={{
        position: 'absolute', top: 20, right: 30, fontSize: 86, opacity: 0.08, color: '#fff',
        pointerEvents: 'none', userSelect: 'none',
      }}>﷽</div>
      <div className="display" style={{ fontSize: 44, fontWeight: 600, letterSpacing: '-0.03em', lineHeight: 1.1 }}>
        Download Hadithly.<br />Open the book in your language.
      </div>
      <div style={{ marginTop: 14, fontSize: 16, opacity: 0.9, lineHeight: 1.5, maxWidth: 480, margin: '14px auto 0' }}>
        Scan the QR with your phone, or grab it from the store. Free forever.
      </div>
      <div style={{ marginTop: 36, display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 28, flexWrap: 'wrap' }}>
        <QRCode size={130} />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <StoreButton kind="apple" />
          <StoreButton kind="google" />
        </div>
      </div>
    </div>
  </Container>
);

// ──────── TESTIMONIALS ────────
const Testimonials = () => {
  const items = [
    { name: 'Aigerim N.', loc: 'Almaty', stars: 5, body: 'Reading hadith in Kazakh used to mean piecing together broken translations. Hadithly just… works. The Arabic is gorgeous.' },
    { name: 'Yusuf K.', loc: 'Istanbul', stars: 5, body: 'The reader feels like a book, not an app. I sit with one hadith for ten minutes and the app gets out of the way.' },
    { name: 'Ahmad S.', loc: 'Dhaka', stars: 5, body: 'The AI badge plus rating is honest. I trust what I\'m reading because nothing is hidden from me.' },
    { name: 'Fatima R.', loc: 'Casablanca', stars: 5, body: 'The community translation flow is the calmest I have ever used. Submitted three improvements, two went live the same day.' },
    { name: 'Bilal A.', loc: 'Manchester', stars: 5, body: 'I bookmark a hadith, write a note, and my younger brother sees it the next morning. Simple, works across our family.' },
    { name: 'Aliya S.', loc: 'Bishkek', stars: 5, body: 'Daily hadith at 7:30. One short line each morning. It is changing the rhythm of my day.' },
  ];
  return (
    <Container style={{ paddingTop: 80, paddingBottom: 80 }}>
      <SectionTitle eyebrow="Stories" title={<>Quiet readers.<br/>Real reflections.</>} sub="Hadithly is read in 30+ languages by tens of thousands of people every day." />
      <div style={{ marginTop: 56, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16 }}>
        {items.map((tm, i) => (
          <div key={i} style={{
            padding: 22, borderRadius: 18, background: '#fff',
            border: `1px solid ${t.hair}`,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 11, marginBottom: 12 }}>
              <Avatar name={tm.name} color={`oklch(0.7 0.08 ${(tm.name.charCodeAt(0) * 13) % 360})`} size={36} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13.5, fontWeight: 600, color: t.text, letterSpacing: '-0.005em' }}>{tm.name}</div>
                <div style={{ fontSize: 11.5, color: t.textSec }}>{tm.loc}</div>
              </div>
              <div style={{ display: 'flex', gap: 1 }}>
                {Array.from({ length: tm.stars }).map((_, j) => <Icon key={j} name="starFill" size={11} color={t.gold} />)}
              </div>
            </div>
            <div className="serif" style={{ fontSize: 14, lineHeight: 1.55, color: t.text }}>"{tm.body}"</div>
          </div>
        ))}
      </div>
    </Container>
  );
};

// ──────── FOOTER ────────
const Footer = () => (
  <div style={{ background: '#0a0a0a', color: '#fff', padding: '60px 0 30px', marginTop: 40 }}>
    <Container>
      <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1fr 1fr 1fr 1.4fr', gap: 40 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <HadithlyMark size={28} color="#fff" />
            <span style={{ fontSize: 21, fontWeight: 600, letterSpacing: '-0.025em' }}>Hadithly</span>
          </div>
          <div style={{ fontSize: 13.5, color: 'rgba(255,255,255,0.6)', marginTop: 14, lineHeight: 1.55 }}>
            Read the words that lit a world. Hadithly is a calm, modern hadith reader in the language you read.
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 18 }}>
            {['globe', 'mail', 'chat', 'sparkle'].map(ic => (
              <div key={ic} style={{ width: 32, height: 32, borderRadius: '50%', background: 'rgba(255,255,255,0.06)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name={ic} size={14} color="#fff" />
              </div>
            ))}
          </div>
        </div>
        {[
          ['Product', ['Features', 'Reader', 'Languages', 'Pricing', 'Roadmap']],
          ['Company', ['About', 'Blog', 'Press', 'Open source']],
          ['Resources', ['FAQ', 'Help center', 'Status', 'Sources']],
        ].map(([title, items]) => (
          <div key={title}>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.03em', textTransform: 'uppercase', color: '#fff', marginBottom: 14 }}>{title}</div>
            {items.map(item => (
              <a key={item} style={{ display: 'block', fontSize: 13.5, color: 'rgba(255,255,255,0.6)', padding: '5px 0' }}>{item}</a>
            ))}
          </div>
        ))}
        <div>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.03em', textTransform: 'uppercase', color: '#fff', marginBottom: 14 }}>Stay close</div>
          <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.6)', lineHeight: 1.55, marginBottom: 12 }}>
            One short email when new languages launch. Never more.
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <input style={{
              flex: 1, padding: '10px 14px', borderRadius: 999,
              background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)',
              color: '#fff', fontFamily: 'inherit', fontSize: 13, outline: 'none',
            }} placeholder="your@email.com" />
            <a style={{
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: '10px 16px', borderRadius: 999,
              background: t.accent, color: '#fff', fontSize: 13, fontWeight: 600, cursor: 'pointer',
            }}>Subscribe</a>
          </div>
        </div>
      </div>
      <div style={{ height: 1, background: 'rgba(255,255,255,0.06)', margin: '40px 0 20px' }} />
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: 'rgba(255,255,255,0.5)' }}>
        <div>© 2026 Hadithly. Made with care, for readers everywhere.</div>
        <div style={{ display: 'flex', gap: 18 }}>
          <a>Terms</a><a>Privacy</a><a>Cookies</a>
        </div>
      </div>
    </Container>
  </div>
);

// ──────── ROOT ────────
const Landing = () => (
  <div style={{ background: '#fff' }}>
    <Nav />
    <Hero />
    <FeaturesGrid />
    <WhyTrust />
    <Pricing />
    <DownloadCTA />
    <Testimonials />
    <Footer />
  </div>
);

ReactDOM.createRoot(document.getElementById('root')).render(<Landing />);
