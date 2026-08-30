import Image from "next/image";
import type { CSSProperties, ReactNode } from "react";

const ACCENT = "#168a4a";
const GOLD = "#b8893b";

const features: Array<[IconName, string, string]> = [
  [
    "bookOpen",
    "Beautiful, book-like reader",
    "Continuous text, no cards. Arabic right-aligned. Translation below. Light, dark, sepia.",
  ],
  [
    "sparkle",
    "AI when you need it",
    "When a translation is missing, AI generates one instantly — grounded in web sources and labeled.",
  ],
  [
    "shield",
    "Authenticity, transparent",
    "Grade and source dataset shown for every hadith. AI never decides authenticity.",
  ],
  [
    "community",
    "A humble community",
    "Suggest better translations with a source. AI reviews quality. No public argument threads.",
  ],
  [
    "bookmark",
    "Bookmarks, favorites, notes",
    "Sync across devices. Pin a passage, save a quote, add a thought.",
  ],
  [
    "bell",
    "A hadith every morning",
    "One short hadith at the time you choose, in the language you read.",
  ],
];

const testimonials: Array<[string, string, string]> = [
  [
    "Aigerim N.",
    "Almaty",
    "Reading hadith in Kazakh used to mean piecing together broken translations. Hadithly just works.",
  ],
  [
    "Yusuf K.",
    "Istanbul",
    "The reader feels like a book, not an app. I sit with one hadith and the app gets out of the way.",
  ],
  [
    "Ahmad S.",
    "Dhaka",
    "The AI badge plus the source link is honest. I trust what I am reading because nothing is hidden.",
  ],
  [
    "Fatima R.",
    "Casablanca",
    "The community translation flow is calm. I submitted improvements and two went live the same day.",
  ],
  [
    "Bilal A.",
    "Manchester",
    "I bookmark a hadith, write a note, and my younger brother sees it the next morning.",
  ],
  [
    "Aliya S.",
    "Bishkek",
    "Daily hadith at 7:30. One short line each morning. It changed the rhythm of my day.",
  ],
];

export default function LandingPage() {
  return (
    <main>
      <Nav />
      <Hero />
      <FeaturesGrid />
      <WhyTrust />
      <Pricing />
      <DownloadCTA />
      <Testimonials />
      <Footer />
    </main>
  );
}

function Nav() {
  return (
    <nav className="nav">
      <a className="brand" href="#top" aria-label="Hadithly home">
        <Image
          src="/brand/hadithly-logo-light.png"
          width={30}
          height={30}
          alt=""
          priority
        />
        <span>Hadithly</span>
      </a>
      <div className="navLinks">
        {["Home", "Features", "Screenshots", "Pricing", "FAQ", "Contact"].map(
          (label, index) => (
            <a
              className={index === 0 ? "active" : ""}
              href={index === 0 ? "#top" : `#${label.toLowerCase()}`}
              key={label}
            >
              {label}
            </a>
          ),
        )}
      </div>
      <a className="navCta" href="#download">
        Download app <Icon name="arrowR" size={14} color="#fff" />
      </a>
    </nav>
  );
}

function Hero() {
  return (
    <section className="heroShell" id="top">
      <div className="hero">
        <p className="eyebrow">The clear hadith reader</p>
        <h1 className="display">
          Read hadith in
          <br />
          your language.
        </h1>
        <p className="lede">
          Arabic and English source, AI-assisted translations into 30+
          languages, and a community that keeps making them better — all in one
          calm reader.
        </p>
        <div className="storeRow" id="download">
          <StoreButton kind="apple" />
          <StoreButton kind="google" />
        </div>
        <div className="phoneStage">
          <div className="phoneWrap phoneLeft">
            <PhoneMock screen="home" />
          </div>
          <div className="phoneWrap phoneCenter">
            <PhoneMock screen="reader" />
          </div>
          <div className="phoneWrap phoneRight">
            <PhoneMock dark screen="reader" />
          </div>
          <div className="callout calloutReaders">
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <div style={{ display: "flex" }}>
                {["#A78BFA", "#F472B6", "#34D399"].map((c, i) => (
                  <Avatar
                    key={c}
                    name={["Aa", "Bb", "Cc"][i]}
                    color={c}
                    size={22}
                    style={{ marginLeft: i ? -7 : 0, border: "2px solid #fff" }}
                  />
                ))}
              </div>
              <div style={{ lineHeight: 1.25 }}>
                <strong style={{ display: "block", fontSize: 11.5 }}>
                  4k+ readers
                </strong>
                <small>across 30 languages</small>
              </div>
            </div>
          </div>
          <div className="callout calloutAi">
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <div
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: 8,
                  background: "rgba(22,138,74,.1)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <Icon name="sparkle" size={15} color={ACCENT} />
              </div>
              <div style={{ lineHeight: 1.25 }}>
                <strong style={{ display: "block", fontSize: 11.5 }}>
                  AI translation
                </strong>
                <small>in 30+ languages</small>
              </div>
            </div>
          </div>
          <div className="callout calloutSaved">
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <div
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: 8,
                  background: "rgba(184,137,59,.14)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <Icon name="bookmarkFill" size={14} color={GOLD} />
              </div>
              <div style={{ lineHeight: 1.25 }}>
                <strong style={{ display: "block", fontSize: 11.5 }}>
                  247 saved
                </strong>
                <small>bookmarks &amp; notes</small>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function FeaturesGrid() {
  return (
    <section className="section" id="features">
      <SectionTitle
        eyebrow="Features"
        title={
          <>
            Everything you need.
            <br />
            Nothing you don&apos;t.
          </>
        }
        sub="Sacred text deserves a calm, modern reader. Hadithly is built around that single idea."
      />
      <div className="featureGrid">
        <FeatureCard item={features[0]} />
        <div className="readerFeature">
          <div>
            <h3 className="display">The reader.</h3>
            <p>Open the book. Begin again.</p>
          </div>
          <PhoneMock dark screen="reader" />
        </div>
        {features.slice(1, 4).map((feature) => (
          <FeatureCard item={feature} key={feature[1]} />
        ))}
      </div>
      <a className="roundCta" href="#pricing">
        Explore all features <Icon name="arrowR" size={14} color="#fff" />
      </a>
    </section>
  );
}

function WhyTrust() {
  const cards: Array<[string, string, MockScreen]> = [
    [
      "A reader, not a feed",
      "Continuous, book-like text. Hairlines between hadiths. No tappable cards bouncing for attention.",
      "reader",
    ],
    [
      "AI you can audit",
      "Every translation is labeled by source with a link you can open. Rate, vote, or suggest a better one.",
      "translation",
    ],
    [
      "Calm community",
      "AI reviews submissions for meaning preservation and glossary consistency. Humble leaderboards, no gamification creep.",
      "community",
    ],
  ];
  return (
    <section className="trustBand" id="screenshots">
      <SectionTitle
        eyebrow="Why readers stay"
        title={
          <>
            Built for the way you
            <br />
            actually read.
          </>
        }
        sub="Three things matter most in a hadith reader: the text, the translation, and the trust."
      />
      <div className="trustGrid">
        {cards.map(([title, body, screen]) => (
          <article className="trustCard" key={title}>
            <div className="featureIcon">
              <Icon
                name={
                  screen === "reader"
                    ? "bookOpen"
                    : screen === "translation"
                      ? "sparkle"
                      : "community"
                }
                size={18}
                color={ACCENT}
              />
            </div>
            <h3>{title}</h3>
            <p>{body}</p>
            <div className="miniPhoneSlot">
              <PhoneMock screen={screen} small />
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function Pricing() {
  return (
    <section className="section" id="pricing">
      <SectionTitle
        eyebrow="Pricing"
        title="Free forever. Pro when you need it."
        sub="Basic reading and cached translations remain free, always. Pro funds AI generation and offline access."
      />
      <div className="pricingGrid">
        <PriceCard
          icon="bookOpen"
          title="Free"
          price="$0"
          sub="forever"
          features={[
            "Full reader · Arabic + English",
            "View all cached translations",
            "20 AI translations / month",
            "Bookmarks, favorites, notes",
            "Daily hadith notification",
          ]}
        />
        <PriceCard
          featured
          icon="sparkle"
          title="Pro · Annual"
          price="$29.99"
          sub="/ year"
          features={[
            "500 AI translations / month",
            "Priority translation queue",
            "Offline language packs",
            "Advanced contribution tools",
            "Everything in Free",
          ]}
        />
        <PriceCard
          icon="flame"
          title="Pro · Monthly"
          price="$3.99"
          sub="/ month"
          features={[
            "500 AI translations / month",
            "Priority translation queue",
            "Offline language packs",
            "Advanced contribution tools",
            "Everything in Free",
          ]}
        />
      </div>
      <p className="pricingNote">
        All prices in USD. Cached translations are always free to view.
      </p>
    </section>
  );
}

function DownloadCTA() {
  return (
    <section className="downloadShell">
      <div className="downloadCta">
        <div className="bismillah arabic">﷽</div>
        <h2 className="display">
          Download Hadithly.
          <br />
          Open the book in your language.
        </h2>
        <p>
          Scan the QR with your phone, or grab it from the store. Free forever.
        </p>
        <div className="downloadActions">
          <div className="qr" aria-hidden="true">
            <QRCode size={130} />
          </div>
          <div className="storeColumn">
            <StoreButton kind="apple" />
            <StoreButton kind="google" />
          </div>
        </div>
      </div>
    </section>
  );
}

function Testimonials() {
  return (
    <section className="section">
      <SectionTitle
        eyebrow="Stories"
        title={
          <>
            Quiet readers.
            <br />
            Real reflections.
          </>
        }
        sub="Hadithly is read in 30+ languages by people who want a calmer reader."
      />
      <div className="testimonialGrid">
        {testimonials.map(([name, loc, body]) => (
          <article className="testimonial" key={name}>
            <div className="testimonialTop">
              <Avatar name={name} size={36} />
              <div>
                <strong>{name}</strong>
                <small>{loc}</small>
              </div>
              <span style={{ display: "inline-flex", gap: 1 }}>
                {Array.from({ length: 5 }).map((_, i) => (
                  <Icon key={i} name="starFill" size={11} color={GOLD} />
                ))}
              </span>
            </div>
            <p className="serif">&ldquo;{body}&rdquo;</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="footer" id="contact">
      <div className="footerGrid">
        <div>
          <div className="footerBrand">
            <Image
              src="/brand/hadithly-logo-dark.png"
              width={30}
              height={30}
              alt=""
            />
            <span>Hadithly</span>
          </div>
          <p>
            Read the words that lit a world. Hadithly is a calm, modern hadith
            reader in the language you read.
          </p>
          <div style={{ display: "flex", gap: 8, marginTop: 18 }}>
            {(["globe", "mail", "chat", "sparkle"] as IconName[]).map((ic) => (
              <span
                key={ic}
                style={{
                  width: 32,
                  height: 32,
                  borderRadius: "50%",
                  background: "rgba(255,255,255,0.06)",
                  display: "inline-flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <Icon name={ic} size={14} color="#fff" />
              </span>
            ))}
          </div>
        </div>
        {(
          [
            [
              "Product",
              "Features",
              "Reader",
              "Languages",
              "Pricing",
              "Roadmap",
            ],
            ["Company", "About", "Blog", "Press", "Open source"],
            ["Resources", "FAQ", "Help center", "Status", "Sources"],
          ] as string[][]
        ).map(([title, ...links]) => (
          <div key={title}>
            <h3>{title}</h3>
            {links.map((link) => (
              <a href="#" key={link}>
                {link}
              </a>
            ))}
          </div>
        ))}
        <div>
          <h3>Stay close</h3>
          <p>One short email when new languages launch. Never more.</p>
          <div className="subscribe">
            <input placeholder="your@email.com" />
            <button>Subscribe</button>
          </div>
        </div>
      </div>
      <div className="legal">
        <span>© 2026 Hadithly. Made with care, for readers everywhere.</span>
        <span>Terms · Privacy · Cookies</span>
      </div>
    </footer>
  );
}

function SectionTitle({
  eyebrow,
  title,
  sub,
}: {
  eyebrow: string;
  title: ReactNode;
  sub: string;
}) {
  return (
    <div className="sectionTitle">
      <p className="eyebrow">{eyebrow}</p>
      <h2 className="display">{title}</h2>
      <p>{sub}</p>
    </div>
  );
}

function StoreButton({ kind }: { kind: "apple" | "google" }) {
  return (
    <a aria-disabled="true" className="storeButton" href="#">
      <Icon name={kind === "apple" ? "apple" : "play"} size={22} color="#fff" />
      <span className="storeText">
        <span>{kind === "apple" ? "Download on the" : "GET IT ON"}</span>
        <strong>{kind === "apple" ? "App Store" : "Google Play"}</strong>
      </span>
    </a>
  );
}

function FeatureCard({ item }: { item: [IconName, string, string] }) {
  return (
    <article className="feature">
      <div className="featureIcon">
        <Icon name={item[0]} size={18} color={ACCENT} />
      </div>
      <h3>{item[1]}</h3>
      <p>{item[2]}</p>
      <a href="#download">
        Learn more <Icon name="arrowR" size={12} color={ACCENT} />
      </a>
    </article>
  );
}

function PriceCard({
  title,
  price,
  sub,
  features: list,
  featured,
  icon,
}: {
  title: string;
  price: string;
  sub: string;
  features: string[];
  featured?: boolean;
  icon: IconName;
}) {
  const checkColor = featured ? "#fff" : ACCENT;
  return (
    <article className={featured ? "priceCard featured" : "priceCard"}>
      {featured ? <div className="ribbon">MOST POPULAR</div> : null}
      <div
        className="featureIcon"
        style={
          featured
            ? { background: "rgba(255,255,255,0.18)" }
            : { background: "var(--surface)" }
        }
      >
        <Icon name={icon} size={18} color={featured ? "#fff" : "var(--text)"} />
      </div>
      <h3>{title}</h3>
      <div className="price display">
        {price}
        <span>{sub}</span>
      </div>
      <ul>
        {list.map((label) => (
          <li
            key={label}
            style={{ display: "flex", alignItems: "center", gap: 9 }}
          >
            <Icon name="check" size={16} color={checkColor} strokeWidth={2.2} />{" "}
            {label}
          </li>
        ))}
      </ul>
      <a href="#download">{featured ? "Start 3-day trial" : "Get started"}</a>
    </article>
  );
}

/* ──────── Phone mockups ──────── */

type MockScreen = "home" | "reader" | "translation" | "community";

function PhoneMock({
  screen,
  dark,
  small,
}: {
  screen: MockScreen;
  dark?: boolean;
  small?: boolean;
}) {
  return (
    <div className={`${small ? "phone small" : "phone"} ${dark ? "dark" : ""}`}>
      <div className="phoneIsland" />
      {screen === "home" ? (
        <HomeMock />
      ) : screen === "community" ? (
        <CommunityMock />
      ) : screen === "translation" ? (
        <TranslationMock />
      ) : (
        <ReaderMock dark={dark} />
      )}
      <div className="homeIndicator" />
    </div>
  );
}

function ReaderChip({
  children,
  tone,
}: {
  children: ReactNode;
  tone?: "accent" | "gold";
}) {
  const color =
    tone === "accent" ? ACCENT : tone === "gold" ? GOLD : "var(--muted)";
  const bg =
    tone === "accent"
      ? "rgba(22,138,74,.12)"
      : tone === "gold"
        ? "rgba(184,137,59,.14)"
        : "rgba(120,120,120,.12)";
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 3,
        padding: "2px 7px",
        borderRadius: 7,
        fontSize: 9.5,
        fontWeight: 600,
        color,
        background: bg,
      }}
    >
      {children}
    </span>
  );
}

function HomeMock() {
  return (
    <div className="mockHome">
      <small>Friday · 23 Dhul Qi&apos;dah</small>
      <h3 className="display">Assalamu alaikum</h3>
      <div
        className="mockSearch"
        style={{ display: "flex", alignItems: "center", gap: 7 }}
      >
        <Icon name="search" size={14} color="var(--faint)" /> Search hadiths,
        collections…
      </div>
      <div className="mockCard">
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 5,
            marginBottom: 8,
          }}
        >
          <ReaderChip tone="accent">
            <Icon name="sparkle" size={9} color={ACCENT} /> Today&apos;s hadith
          </ReaderChip>
        </div>
        <p className="mockArabic">إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ</p>
        <p>Поистине, дела оцениваются по намерениям…</p>
      </div>
      <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
        {["Bukhari", "Muslim"].map((c) => (
          <div
            key={c}
            style={{
              flex: 1,
              border: "1px solid var(--hair)",
              borderRadius: 10,
              padding: "10px 12px",
            }}
          >
            <div style={{ fontSize: 12.5, fontWeight: 600 }}>{c}</div>
            <div
              style={{ fontSize: 10.5, color: "var(--muted)", marginTop: 2 }}
            >
              Sahih
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function ReaderMock({ dark }: { dark?: boolean }) {
  const muted = dark ? "rgba(245,239,227,0.55)" : "var(--muted)";
  return (
    <div className="mockReader">
      <div className="readerPill" />
      <h3 className="display">
        Book of Belief <span className="arabic">كِتَابُ الْإِيمَانِ</span>
      </h3>
      <small>Sahih al-Bukhari · 51 hadith</small>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 5,
          margin: "14px 0 10px",
        }}
      >
        <span style={{ fontSize: 10, color: muted, flex: 1 }}>2:8</span>
        <ReaderChip>Sahih</ReaderChip>
        <ReaderChip tone="accent">Official</ReaderChip>
      </div>
      <p className="mockArabic">بُنِيَ الْإِسْلَامُ عَلَى خَمْسٍ</p>
      <p>
        Islam is built upon five: the testimony that none has the right to be
        worshipped except Allah…
      </p>
      <div className={dark ? "floatBtns darkFloat" : "floatBtns"}>
        <span>
          <Icon name="home" size={18} color={dark ? "#f5efe3" : "#1b1a17"} />
        </span>
        <span>
          <Icon name="menu" size={18} color={dark ? "#f5efe3" : "#1b1a17"} />
        </span>
      </div>
    </div>
  );
}

function TranslationMock() {
  return (
    <div className="mockReader">
      <h3 className="display">Translation</h3>
      <small>Russian · on demand</small>
      <div className="mockCard">
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 5,
            marginBottom: 8,
          }}
        >
          <ReaderChip tone="accent">
            <Icon name="sparkle" size={9} color={ACCENT} /> Generated with AI
          </ReaderChip>
        </div>
        <p>Поистине, дела оцениваются лишь по намерениям…</p>
        <a
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 5,
            marginTop: 10,
            fontSize: 11.5,
            color: ACCENT,
            fontWeight: 600,
          }}
        >
          <Icon name="link" size={12} color={ACCENT} /> sunnah.com/bukhari:1
        </a>
      </div>
      <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
        <span
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 5,
            fontSize: 11.5,
            color: "var(--muted)",
          }}
        >
          <Icon name="thumbUp" size={14} color="var(--muted)" /> 92%
        </span>
        <span
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 5,
            fontSize: 11.5,
            color: "var(--muted)",
          }}
        >
          <Icon name="thumbDown" size={14} color="var(--muted)" />
        </span>
      </div>
      <button
        style={{
          marginTop: 16,
          width: "100%",
          background: ACCENT,
          color: "#fff",
          border: "none",
          borderRadius: 999,
          padding: "10px 14px",
          fontSize: 12.5,
          fontWeight: 600,
        }}
      >
        Suggest a better translation
      </button>
    </div>
  );
}

function CommunityMock() {
  return (
    <div className="mockHome">
      <h3 className="display">Community</h3>
      <div className="mockCard">
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontSize: 12.5,
            fontWeight: 600,
          }}
        >
          <span>Russian</span>
          <span style={{ color: "var(--muted)" }}>30%</span>
        </div>
        <div className="bar" style={{ marginTop: 8 }}>
          <i />
        </div>
        <p style={{ marginTop: 8 }}>Community 4% · AI cached 26%</p>
      </div>
      <small style={{ display: "block", marginTop: 16 }}>
        Leaderboard · Russian
      </small>
      {["Aisha", "Omar", "Layla"].map((name, i) => (
        <div
          key={name}
          style={{
            display: "flex",
            alignItems: "center",
            gap: 9,
            padding: "9px 0",
            borderBottom: "1px solid var(--hair)",
          }}
        >
          <span style={{ fontSize: 11, color: "var(--muted)", width: 14 }}>
            {i + 1}
          </span>
          <Avatar name={name} size={24} />
          <span style={{ fontSize: 12.5, flex: 1 }}>{name}</span>
          <span style={{ fontSize: 11, color: ACCENT, fontWeight: 600 }}>
            {120 - i * 18}
          </span>
        </div>
      ))}
    </div>
  );
}

/* ──────── Avatar ──────── */

function Avatar({
  name,
  size = 36,
  color,
  style,
}: {
  name: string;
  size?: number;
  color?: string;
  style?: CSSProperties;
}) {
  const initials = name
    .split(" ")
    .slice(0, 2)
    .map((w) => w[0])
    .join("");
  const bg = color ?? `hsl(${(name.charCodeAt(0) * 13) % 360} 45% 62%)`;
  return (
    <span
      style={{
        width: size,
        height: size,
        borderRadius: "50%",
        background: bg,
        color: "#fff",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize: size * 0.36,
        fontWeight: 700,
        flexShrink: 0,
        ...style,
      }}
    >
      {initials}
    </span>
  );
}

/* ──────── Decorative QR (not a real code) ──────── */

function QRCode({ size = 130 }: { size?: number }) {
  const cells = 21;
  const seed = (i: number, j: number) => {
    if ((i < 7 && j < 7) || (i < 7 && j > 13) || (i > 13 && j < 7)) {
      if (i === 0 || i === 6 || j === 0 || j === 6) return true;
      if (i >= 2 && i <= 4 && j >= 2 && j <= 4) return true;
      return false;
    }
    return (i * 73 + j * 137 + i * j * 13) % 100 < 48;
  };
  return (
    <svg
      viewBox={`0 0 ${cells} ${cells}`}
      width={size}
      height={size}
      aria-hidden="true"
    >
      {Array.from({ length: cells }).map((_, i) =>
        Array.from({ length: cells }).map((_, j) =>
          seed(i, j) ? (
            <rect
              key={`${i}-${j}`}
              x={j}
              y={i}
              width="1"
              height="1"
              fill="#0a0a0a"
            />
          ) : null,
        ),
      )}
    </svg>
  );
}

/* ──────── Icons (Hugeicons-style stroke set, ported from prototype) ──────── */

type IconName =
  | "home"
  | "book"
  | "bookOpen"
  | "community"
  | "user"
  | "search"
  | "bookmark"
  | "bookmarkFill"
  | "sparkle"
  | "bell"
  | "check"
  | "arrowR"
  | "shield"
  | "flame"
  | "star"
  | "starFill"
  | "globe"
  | "mail"
  | "chat"
  | "menu"
  | "apple"
  | "play"
  | "google"
  | "languages"
  | "link"
  | "thumbUp"
  | "thumbDown";

function Icon({
  name,
  size = 18,
  color = "currentColor",
  strokeWidth = 1.6,
  style,
}: {
  name: IconName;
  size?: number;
  color?: string;
  strokeWidth?: number;
  style?: CSSProperties;
}) {
  const c = {
    fill: "none",
    stroke: color,
    strokeWidth,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  };
  const paths: Record<IconName, ReactNode> = {
    home: (
      <path
        d="M3 11l9-7 9 7v9a2 2 0 0 1-2 2h-4v-7H9v7H5a2 2 0 0 1-2-2z"
        {...c}
      />
    ),
    book: (
      <>
        <path d="M4 4h7a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H4z" {...c} />
        <path d="M20 4h-3a3 3 0 0 0-3 3v13" {...c} />
      </>
    ),
    bookOpen: (
      <>
        <path
          d="M3 6c3-1 6-1 9 1 3-2 6-2 9-1v13c-3-1-6-1-9 1-3-2-6-2-9-1z"
          {...c}
        />
        <path d="M12 7v13" {...c} />
      </>
    ),
    community: (
      <>
        <circle cx="9" cy="8" r="3" {...c} />
        <path d="M2 20c0-3 3-5 7-5s7 2 7 5" {...c} />
        <circle cx="17" cy="9" r="2.5" {...c} />
        <path d="M14 14c4 0 8 1.5 8 4.5" {...c} />
      </>
    ),
    user: (
      <>
        <circle cx="12" cy="8" r="4" {...c} />
        <path d="M3 21c1.5-4 5-6 9-6s7.5 2 9 6" {...c} />
      </>
    ),
    search: (
      <>
        <circle cx="11" cy="11" r="6.5" {...c} />
        <path d="M16.5 16.5l4 4" {...c} />
      </>
    ),
    bookmark: <path d="M6 3h12v18l-6-4-6 4z" {...c} />,
    bookmarkFill: (
      <path
        d="M6 3h12v18l-6-4-6 4z"
        fill={color}
        stroke={color}
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
    ),
    sparkle: (
      <>
        <path
          d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5z"
          {...c}
        />
        <path
          d="M19 16l.6 1.4L21 18l-1.4.6L19 20l-.6-1.4L17 18l1.4-.6z"
          {...c}
        />
      </>
    ),
    bell: (
      <>
        <path d="M6 9a6 6 0 1 1 12 0c0 5 2 6 2 8H4c0-2 2-3 2-8z" {...c} />
        <path d="M10 21a2 2 0 0 0 4 0" {...c} />
      </>
    ),
    check: <path d="M5 12l5 5L20 7" {...c} />,
    arrowR: <path d="M5 12h14M13 6l6 6-6 6" {...c} />,
    shield: (
      <>
        <path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z" {...c} />
        <path d="M9 12l2 2 4-4" {...c} />
      </>
    ),
    flame: (
      <path
        d="M12 21c-4 0-7-3-7-7 0-3 3-4 3-7 0 0 3 2 3 5 0-3 2-5 4-7 0 0 4 5 4 9s-3 7-7 7z"
        {...c}
      />
    ),
    star: (
      <path
        d="M12 4l2.5 5 5.5.8-4 4 .9 5.5L12 17l-4.9 2.3.9-5.5-4-4 5.5-.8z"
        {...c}
      />
    ),
    starFill: (
      <path
        d="M12 4l2.5 5 5.5.8-4 4 .9 5.5L12 17l-4.9 2.3.9-5.5-4-4 5.5-.8z"
        fill={color}
        stroke={color}
        strokeLinejoin="round"
      />
    ),
    globe: (
      <>
        <circle cx="12" cy="12" r="9" {...c} />
        <path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" {...c} />
      </>
    ),
    mail: (
      <>
        <rect x="3" y="5" width="18" height="14" rx="2" {...c} />
        <path d="M3 7l9 7 9-7" {...c} />
      </>
    ),
    chat: (
      <path d="M21 12a8 8 0 1 1-3.4-6.5L21 4l-1.5 4A8 8 0 0 1 21 12z" {...c} />
    ),
    menu: <path d="M4 7h16M4 12h16M4 17h10" {...c} />,
    languages: (
      <>
        <path d="M3 4h10M8 3v2M10 4c-1 5-3 8-7 10" {...c} />
        <path d="M5 8c1.5 3 4 5 7 6" {...c} />
        <path d="M13 20l4-10 4 10M14.5 17h5" {...c} />
      </>
    ),
    link: (
      <path
        d="M10 14a4 4 0 0 1 0-5l3-3a4 4 0 0 1 5 5l-1.5 1.5M14 10a4 4 0 0 1 0 5l-3 3a4 4 0 0 1-5-5l1.5-1.5"
        {...c}
      />
    ),
    thumbUp: (
      <path
        d="M7 11v9H5a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2zM7 11l4-7c1.5 0 3 1 3 3v3h5a2 2 0 0 1 2 2.4l-1.4 6A2 2 0 0 1 17.6 20H7"
        {...c}
      />
    ),
    thumbDown: (
      <path
        d="M17 13V4h2a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2zM17 13l-4 7c-1.5 0-3-1-3-3v-3H5a2 2 0 0 1-2-2.4l1.4-6A2 2 0 0 1 6.4 4H17"
        {...c}
      />
    ),
    apple: (
      <path
        d="M16.5 12.5c0-2.5 2-3.6 2-3.6-1-1.5-2.7-1.7-3.3-1.7-1.4-.1-2.7.8-3.4.8-.7 0-1.8-.8-3-.8-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 3 2.3 1.2-.1 1.6-.8 3.1-.8 1.4 0 1.8.8 3.1.7 1.3 0 2.1-1.1 2.9-2.3.6-.8 1.1-1.7 1.4-2.6-2.3-.9-2.2-3.5-2.2-3.6zM14.4 5c.7-.8 1.1-1.9 1-3-.9.1-2.1.6-2.7 1.4-.6.7-1.2 1.8-1 2.9 1 0 2-.5 2.7-1.3z"
        fill={color}
      />
    ),
    google: (
      <>
        <path
          d="M21.4 12.2c0-.7-.1-1.4-.2-2H12v3.8h5.3c-.2 1.2-.9 2.2-2 2.9v2.4h3.2c1.9-1.7 2.9-4.2 2.9-7.1z"
          fill="#4285F4"
        />
        <path
          d="M12 21.5c2.7 0 5-.9 6.6-2.4l-3.2-2.4c-.9.6-2 1-3.4 1-2.6 0-4.8-1.7-5.6-4.1H3.1v2.5c1.7 3.3 5 5.4 8.9 5.4z"
          fill="#34A853"
        />
        <path
          d="M6.4 13.5c-.2-.6-.3-1.2-.3-1.9 0-.7.1-1.3.3-1.9V7.2H3.1c-.7 1.4-1.1 3-1.1 4.6 0 1.7.4 3.2 1.1 4.6z"
          fill="#FBBC04"
        />
        <path
          d="M12 6.6c1.5 0 2.8.5 3.8 1.5l2.9-2.8C16.9 3.7 14.7 2.5 12 2.5c-3.9 0-7.2 2.2-8.9 5.4l3.3 2.6C7.2 8.3 9.4 6.6 12 6.6z"
          fill="#EA4335"
        />
      </>
    ),
    play: (
      <path
        d="M7 4l13 8-13 8z"
        fill={color}
        stroke={color}
        strokeLinejoin="round"
      />
    ),
  };
  return (
    <svg
      viewBox="0 0 24 24"
      style={{
        width: size,
        height: size,
        display: "inline-block",
        verticalAlign: "middle",
        flexShrink: 0,
        ...style,
      }}
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}
