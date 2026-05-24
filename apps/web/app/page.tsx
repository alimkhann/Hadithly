import Image from "next/image";
import type { ReactNode } from "react";

const features = [
  ["bookOpen", "Beautiful, book-like reader", "Continuous text, no cards. Arabic right-aligned. Translation below. Light, dark, sepia."],
  ["sparkle", "AI when you need it", "When a translation is missing, AI generates one instantly. Every output is labeled and rateable."],
  ["shield", "Authenticity, transparent", "Grade and source dataset shown for every hadith. AI never decides authenticity."],
  ["community", "A humble community", "Suggest better translations with a source. AI reviews quality. No public argument threads."],
  ["bookmark", "Bookmarks, favorites, notes", "Sync across devices. Pin a passage, save a quote, add a thought."],
  ["bell", "A hadith every morning", "One short hadith at the time you choose, in the language you read."]
];

const testimonials = [
  ["Aigerim N.", "Almaty", "Reading hadith in Kazakh used to mean piecing together broken translations. Hadithly just works."],
  ["Yusuf K.", "Istanbul", "The reader feels like a book, not an app. I sit with one hadith and the app gets out of the way."],
  ["Ahmad S.", "Dhaka", "The AI badge plus rating is honest. I trust what I am reading because nothing is hidden."],
  ["Fatima R.", "Casablanca", "The community translation flow is calm. I submitted improvements and two went live the same day."],
  ["Bilal A.", "Manchester", "I bookmark a hadith, write a note, and my younger brother sees it the next morning."],
  ["Aliya S.", "Bishkek", "Daily hadith at 7:30. One short line each morning. It changed the rhythm of my day."]
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
        <Image src="/brand/hadithly-logo-light.png" width={30} height={30} alt="" priority />
        <span>Hadithly</span>
      </a>
      <div className="navLinks">
        {["Home", "Features", "Screenshots", "Pricing", "FAQ", "Contact"].map((label, index) => (
          <a className={index === 0 ? "active" : ""} href={index === 0 ? "#top" : `#${label.toLowerCase()}`} key={label}>{label}</a>
        ))}
      </div>
      <a className="navCta" href="#download">Download app <span>→</span></a>
    </nav>
  );
}

function Hero() {
  return (
    <section className="heroShell" id="top">
      <div className="hero">
        <p className="eyebrow">The clear hadith reader</p>
        <h1>Read hadith in<br />your language.</h1>
        <p className="lede">Arabic and English source, AI-assisted translations into 30+ languages, and a community that keeps making them better - all in one calm reader.</p>
        <div className="storeRow" id="download">
          <StoreButton kind="apple" />
          <StoreButton kind="google" />
        </div>
        <div className="phoneStage">
          <div className="phoneWrap phoneLeft"><PhoneMock screen="home" /></div>
          <div className="phoneWrap phoneCenter"><PhoneMock screen="reader" /></div>
          <div className="phoneWrap phoneRight"><PhoneMock dark screen="dark" /></div>
          <div className="callout calloutReaders"><span className="avatars">Aa Bb Cc</span><strong>4k+ readers</strong><small>across 30 languages</small></div>
          <div className="callout calloutAi"><strong>✦ AI translation</strong><small>in 30+ languages</small></div>
          <div className="callout calloutSaved"><strong>247 saved</strong><small>bookmarks & notes</small></div>
        </div>
      </div>
    </section>
  );
}

function FeaturesGrid() {
  return (
    <section className="section" id="features">
      <SectionTitle eyebrow="Features" title={<>Everything you need.<br />Nothing you do not.</>} sub="Sacred text deserves a calm, modern reader. Hadithly is built around that single idea." />
      <div className="featureGrid">
        <FeatureCard item={features[0]} />
        <div className="readerFeature">
          <div>
            <h3>The reader.</h3>
            <p>Open the book. Begin again.</p>
          </div>
          <PhoneMock dark screen="dark" />
        </div>
        {features.slice(1, 4).map((feature) => <FeatureCard item={feature} key={feature[1]} />)}
      </div>
      <a className="roundCta" href="#pricing">Explore all features <span>→</span></a>
    </section>
  );
}

function WhyTrust() {
  const cards = [
    ["A reader, not a feed", "Continuous, book-like text. Hairlines between hadiths. No tappable cards bouncing for attention.", "reader"],
    ["AI you can audit", "Every translation is labeled by source. Rate, vote, or suggest a better one with a source link or screenshot.", "translation"],
    ["Calm community", "AI reviews submissions for meaning preservation and glossary consistency. Humble leaderboards, no gamification creep.", "community"]
  ];
  return (
    <section className="trustBand" id="screenshots">
      <SectionTitle eyebrow="Why readers stay" title={<>Built for the way you<br />actually read.</>} sub="Three things matter most in a hadith reader: the text, the translation, and the trust." />
      <div className="trustGrid">
        {cards.map(([title, body, screen]) => (
          <article className="trustCard" key={title}>
            <div className="featureIcon">✦</div>
            <h3>{title}</h3>
            <p>{body}</p>
            <div className="miniPhoneSlot"><PhoneMock screen={screen} small /></div>
          </article>
        ))}
      </div>
    </section>
  );
}

function Pricing() {
  return (
    <section className="section" id="pricing">
      <SectionTitle eyebrow="Pricing" title="Free forever. Pro when you need it." sub="Basic reading and cached translations remain free, always. Pro funds AI generation and offline access." />
      <div className="pricingGrid">
        <PriceCard title="Free" price="$0" sub="forever" features={["Full reader · Arabic + English", "View all cached translations", "20 AI translations / month", "Bookmarks, favorites, notes", "Daily hadith notification"]} />
        <PriceCard featured title="Pro · Annual" price="$29.99" sub="/ year" features={["500 AI translations / month", "Priority translation queue", "Offline language packs", "Advanced contribution tools", "Everything in Free"]} />
        <PriceCard title="Pro · Monthly" price="$3.99" sub="/ month" features={["500 AI translations / month", "Priority translation queue", "Offline language packs", "Advanced contribution tools", "Everything in Free"]} />
      </div>
      <p className="pricingNote">All prices in USD. Cached translations are always free to view.</p>
    </section>
  );
}

function DownloadCTA() {
  return (
    <section className="downloadShell">
      <div className="downloadCta">
        <div className="bismillah">﷽</div>
        <h2>Download Hadithly.<br />Open the book in your language.</h2>
        <p>Scan the QR with your phone, or grab it from the store. Free forever.</p>
        <div className="downloadActions">
          <div className="qr" aria-hidden="true">{Array.from({ length: 121 }).map((_, index) => <span className={(index * 17 + index / 3) % 5 < 2 ? "on" : ""} key={index} />)}</div>
          <div className="storeColumn"><StoreButton kind="apple" /><StoreButton kind="google" /></div>
        </div>
      </div>
    </section>
  );
}

function Testimonials() {
  return (
    <section className="section">
      <SectionTitle eyebrow="Stories" title={<>Quiet readers.<br />Real reflections.</>} sub="Hadithly is read in 30+ languages by people who want a calmer reader." />
      <div className="testimonialGrid">
        {testimonials.map(([name, loc, body]) => (
          <article className="testimonial" key={name}>
            <div className="testimonialTop"><Avatar name={name} /><div><strong>{name}</strong><small>{loc}</small></div><span>★★★★★</span></div>
            <p>"{body}"</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="footer">
      <div className="footerGrid">
        <div>
          <div className="footerBrand"><Image src="/brand/hadithly-logo-dark.png" width={30} height={30} alt="" /><span>Hadithly</span></div>
          <p>Read the words that lit a world. Hadithly is a calm, modern hadith reader in the language you read.</p>
        </div>
        {[
          ["Product", "Features", "Reader", "Languages", "Pricing", "Roadmap"],
          ["Company", "About", "Blog", "Press", "Open source"],
          ["Resources", "FAQ", "Help center", "Status", "Sources"]
        ].map(([title, ...links]) => (
          <div key={title}><h3>{title}</h3>{links.map((link) => <a href="#" key={link}>{link}</a>)}</div>
        ))}
        <div>
          <h3>Stay close</h3>
          <p>One short email when new languages launch. Never more.</p>
          <div className="subscribe"><input placeholder="your@email.com" /><button>Subscribe</button></div>
        </div>
      </div>
      <div className="legal"><span>© 2026 Hadithly. Made with care, for readers everywhere.</span><span>Terms · Privacy · Cookies</span></div>
    </footer>
  );
}

function SectionTitle({ eyebrow, title, sub }: { eyebrow: string; title: ReactNode; sub: string }) {
  return <div className="sectionTitle"><p className="eyebrow">{eyebrow}</p><h2>{title}</h2><p>{sub}</p></div>;
}

function StoreButton({ kind }: { kind: "apple" | "google" }) {
  return <a aria-disabled="true" className="storeButton" href="#"><span>{kind === "apple" ? "Download on the" : "GET IT ON"}</span><strong>{kind === "apple" ? "App Store" : "Google Play"}</strong></a>;
}

function FeatureCard({ item }: { item: string[] }) {
  return <article className="feature"><div className="featureIcon">{iconFor(item[0])}</div><h3>{item[1]}</h3><p>{item[2]}</p><a href="#download">Learn more →</a></article>;
}

function PriceCard({ title, price, sub, features: list, featured }: { title: string; price: string; sub: string; features: string[]; featured?: boolean }) {
  return <article className={featured ? "priceCard featured" : "priceCard"}>{featured ? <div className="ribbon">MOST POPULAR</div> : null}<h3>{title}</h3><div className="price">{price}<span>{sub}</span></div><ul>{list.map((item) => <li key={item}>✓ {item}</li>)}</ul><a href="#download">{featured ? "Start 3-day trial" : "Get started"}</a></article>;
}

function PhoneMock({ screen, dark, small }: { screen: string; dark?: boolean; small?: boolean }) {
  return (
    <div className={`${small ? "phone small" : "phone"} ${dark ? "dark" : ""}`}>
      <div className="phoneIsland" />
      {screen === "home" ? <HomeMock /> : screen === "community" ? <CommunityMock /> : screen === "translation" ? <TranslationMock /> : <ReaderMock dark={dark} />}
      <div className="homeIndicator" />
    </div>
  );
}

function HomeMock() {
  return <div className="mockHome"><small>Friday · 23 Dhul Qi'dah</small><h3>Assalamu alaikum</h3><div className="mockSearch">Search hadiths, collections, topics...</div><div className="mockCard"><b>Today's hadith</b><p className="mockArabic">إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ</p><p>Поистине, дела оцениваются по намерениям...</p></div></div>;
}

function ReaderMock({ dark }: { dark?: boolean }) {
  return <div className="mockReader"><div className="readerPill" /><h3>Book of Belief <span>كِتَابُ الْإِيمَانِ</span></h3><small>Sahih al-Bukhari · 51 hadith</small><p className="mockArabic">بُنِيَ الْإِسْلَامُ عَلَى خَمْسٍ</p><p>Islam is built upon five: the testimony that none has the right to be worshipped except Allah...</p><div className={dark ? "floatBtns darkFloat" : "floatBtns"}><span>⌂</span><span>☰</span></div></div>;
}

function TranslationMock() {
  return <div className="mockReader"><h3>Translation</h3><div className="mockCard"><b>Generated with AI</b><p>This translation was generated by AI and may contain mistakes.</p></div><button>Suggest a better translation</button></div>;
}

function CommunityMock() {
  return <div className="mockHome"><h3>Community</h3><div className="mockCard"><b>Russian</b><div className="bar"><i /></div><p>Community 4% · AI cached 26%</p></div><p>Leaderboard · Russian</p></div>;
}

function Avatar({ name }: { name: string }) {
  return <span className="avatar">{name.slice(0, 1)}</span>;
}

function iconFor(name: string) {
  const icons: Record<string, string> = { bookOpen: "☰", sparkle: "✦", shield: "◇", community: "◎", bookmark: "▰", bell: "◌" };
  return icons[name] ?? "✦";
}
