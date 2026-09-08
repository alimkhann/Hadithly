// Main app screens — Home, Library, Collection, Search, Community, You, Settings
// + new: Notifications, Topic detail, Submit translation w/ proof

const HomeScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: 'calc(100% - 83px)', overflowY: 'auto', padding: '8px 20px 90px' }}>
        {/* Header — bell replaces avatar */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: 4, marginBottom: 18 }}>
          <div>
            <div style={{ fontSize: 12, color: t.textSec, marginBottom: 2, letterSpacing: '-0.005em' }}>Friday · 23 Dhul Qi'dah</div>
            <div className="display" style={{ fontSize: 26, color: t.text, letterSpacing: '-0.022em', lineHeight: 1.1, fontWeight: 600 }}>Assalamu alaikum</div>
          </div>
          <IconButton name="bellDot" theme={theme} size={38} iconSize={22} color={t.text} />
        </div>

        {/* Search bar */}
        <div style={{
          display: 'flex', gap: 9, alignItems: 'center', padding: '10px 12px',
          background: t.surface2, borderRadius: RADIUS.md
        }}>
          <Icon name="search" size={17} color={t.textSec} />
          <div style={{ flex: 1, fontSize: 14, color: t.textTer, letterSpacing: '-0.005em' }}>Search hadiths, collections, topics…</div>
        </div>

        {/* Daily hadith card */}
        <div style={{ marginTop: 18 }}>
          <SectionHeader theme={theme}>Today's hadith</SectionHeader>
          <Card theme={theme} padding={18}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 12, flexWrap: 'nowrap' }}>
              <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>1:1</span>
              <div style={{ flex: 1 }} />
              <Chip variant="outline" theme={theme} size="xs">Sahih</Chip>
              <Chip variant="soft" theme={theme} size="xs"><Icon name="sparkle" size={9} color={t.accent} />AI</Chip>
              <span style={{ fontSize: 10.5, color: t.textSec }}>94%</span>
            </div>
            <div className="arabic" style={{ fontSize: 22, lineHeight: 1.95, color: t.text, textAlign: 'right', marginBottom: 12 }}>
              إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ
            </div>
            <div className="serif" style={{ fontSize: 14, lineHeight: 1.65, color: t.textSec, marginBottom: 14 }}>
              Поистине, дела оцениваются по намерениям, и каждому достанется лишь то, что он намеревался обрести…
            </div>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{ fontSize: 11.5, color: t.textTer, letterSpacing: '-0.005em' }}>Narrated by Umar (ra)</span>
              <Button variant="primary" theme={theme} size="sm" iconRight={<Icon name="arrowR" size={13} />}>Read today</Button>
            </div>
          </Card>
        </div>

        {/* Continue */}
        <div style={{ marginTop: 22 }}>
          <SectionHeader theme={theme}>Continue reading</SectionHeader>
          <Card theme={theme} padding={14} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 46, height: 56, borderRadius: RADIUS.sm,
              background: t.accent,
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0
            }}>
              <Icon name="bookOpen" size={22} color={t.primaryFg} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14.5, color: t.text, fontWeight: 600, letterSpacing: '-0.005em' }}>Sahih al-Bukhari</div>
              <div style={{ fontSize: 12.5, color: t.textSec, marginTop: 2 }}>Book of Belief · Hadith 8</div>
              <div style={{ marginTop: 7 }}><ProgressBar value={11} theme={theme} height={3} /></div>
              <div style={{ fontSize: 11, color: t.textTer, marginTop: 4 }}>11% · 2 hours ago</div>
            </div>
            <Icon name="chevronR" size={18} color={t.textTer} />
          </Card>
        </div>

        {/* Topics — tappable, varied tints per category (not following the green accent) */}
        <div style={{ marginTop: 22 }}>
          <SectionHeader theme={theme}>Browse by topic</SectionHeader>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {TOPICS.map((topic) => {
              const color = TOPIC_COLORS[topic] || 'oklch(0.65 0.04 285)';
              const isDark = theme === 'dark';
              return (
                <div key={topic} style={{
                  display: 'inline-flex', alignItems: 'center', gap: 6,
                  padding: '6px 12px', borderRadius: 999,
                  background: isDark ? `${color} / 0.18` : `color-mix(in oklch, ${color} 14%, transparent)`,
                  color: isDark ? `color-mix(in oklch, ${color} 80%, white)` : `color-mix(in oklch, ${color} 60%, black)`,
                  fontSize: 13, fontWeight: 500, cursor: 'pointer',
                  border: `1px solid color-mix(in oklch, ${color} 22%, transparent)`,
                  letterSpacing: '-0.005em',
                }}>
                  <span style={{ width: 6, height: 6, borderRadius: 3, background: color, flexShrink: 0 }} />
                  {topic}
                </div>
              );
            })}
          </div>
        </div>

        {/* Collections — quick access */}
        <div style={{ marginTop: 22 }}>
          <SectionHeader theme={theme}>Collections</SectionHeader>
          <div style={{ display: 'flex', gap: 10, overflowX: 'auto', marginLeft: -20, marginRight: -20, paddingLeft: 20, paddingRight: 20 }}>
            {COLLECTIONS.slice(0, 4).map((c) =>
            <Card key={c.slug} theme={theme} padding={12} style={{ minWidth: 130, flexShrink: 0 }}>
                <div style={{
                width: 30, height: 38, borderRadius: 4, background: t.accent,
                marginBottom: 10, display: 'flex', alignItems: 'flex-end', padding: 5
              }}>
                  <div style={{ fontSize: 8.5, color: t.primaryFg, fontWeight: 700, letterSpacing: '0.04em' }}>{c.grade.toUpperCase()}</div>
                </div>
                <div style={{ fontSize: 12.5, fontWeight: 600, color: t.text, lineHeight: 1.25, letterSpacing: '-0.005em' }}>{c.en}</div>
                <div className="arabic" style={{ fontSize: 12, color: t.textSec, marginTop: 2, textAlign: 'right' }}>{c.ar}</div>
                <div style={{ fontSize: 10.5, color: t.textTer, marginTop: 8 }}>{c.count.toLocaleString()} · {c.coverage}% RU</div>
              </Card>
            )}
          </div>
        </div>
      </div>
      <TabBar theme={theme} active="home" />
    </div>);

};

// Notifications screen
const NotificationsScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  const notifs = [
  {
    kind: 'translation_approved', icon: 'check', color: t.accent,
    title: 'Your translation was approved',
    sub: '"Поистине, дела оцениваются…" · Bukhari 1:1',
    time: '12m ago', unread: true
  },
  {
    kind: 'community_milestone', icon: 'star', color: t.gold,
    title: 'Your translation reached 90% rating',
    sub: '14 votes · Muslim 15 · Russian',
    time: '2h ago', unread: true
  },
  {
    kind: 'community_review', icon: 'sparkle', color: t.accent,
    title: 'AI accepted your suggestion',
    sub: 'Quality score 94 — published as default',
    time: 'Yesterday', unread: true
  },
  {
    kind: 'daily', icon: 'bell', color: t.textSec,
    title: 'Today\'s hadith is ready',
    sub: 'Bukhari 1:1 · 7:30 AM',
    time: 'Yesterday'
  },
  {
    kind: 'translation_rejected', icon: 'info', color: t.warning,
    title: 'A translation you submitted was rejected',
    sub: 'AI flagged: glossary inconsistency · Tirmidhi 2517',
    time: '2 days ago'
  },
  {
    kind: 'leaderboard', icon: 'crown', color: t.gold,
    title: 'You\'re now top 5 in Russian',
    sub: 'This month · 38 approved translations',
    time: '4 days ago'
  },
  {
    kind: 'language_milestone', icon: 'languages', color: t.accent,
    title: 'Russian coverage passed 30%',
    sub: 'Thanks to your contributions',
    time: 'Last week'
  }];

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: '100%', overflowY: 'auto', padding: '6px 20px 30px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
          <IconButton name="chevronL" theme={theme} size={32} iconSize={18} />
          <div className="display" style={{ fontSize: 18, color: t.text, fontWeight: 600, letterSpacing: '-0.015em' }}>Notifications</div>
          <IconButton name="sliders" theme={theme} size={32} iconSize={17} />
        </div>

        <Segmented theme={theme} options={['All', 'Community', 'Daily']} value="All" block />

        <div style={{ marginTop: 16 }}>
          {notifs.map((n, i) =>
          <div key={i} style={{
            display: 'flex', gap: 12, padding: '13px 0',
            borderBottom: i === notifs.length - 1 ? 'none' : `1px solid ${t.hair}`,
            position: 'relative'
          }}>
              <div style={{
              width: 36, height: 36, borderRadius: RADIUS.md,
              background: `${n.color}1f`, color: n.color,
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0
            }}>
                <Icon name={n.icon} size={17} color={n.color} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13.5, color: t.text, fontWeight: 600, lineHeight: 1.3, letterSpacing: '-0.005em' }}>{n.title}</div>
                <div style={{ fontSize: 12.5, color: t.textSec, marginTop: 2, lineHeight: 1.4 }}>{n.sub}</div>
                <div style={{ fontSize: 11, color: t.textTer, marginTop: 4 }}>{n.time}</div>
              </div>
              {n.unread && <div style={{ width: 7, height: 7, borderRadius: 4, background: t.accent, marginTop: 6, flexShrink: 0 }} />}
            </div>
          )}
        </div>

        <Button variant="ghost" theme={theme} size="sm" block style={{ marginTop: 14, color: t.textSec }}>Mark all as read</Button>
      </div>
    </div>);

};

// Topic detail — list of hadiths under a topic
const TopicDetailScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  const hadiths = [
  { ref: '1:1', book: 'Bukhari', source: 'Sahih al-Bukhari', text: 'Actions are but by intention, and every man shall have only that which he intended…', grade: 'Sahih', kind: 'gemini', rating: 94 },
  { ref: '8', book: 'Muslim', source: 'Sahih Muslim', text: 'None of you truly believes until he loves for his brother what he loves for himself.', grade: 'Sahih', kind: 'community', rating: 96 },
  { ref: '8', book: 'Bukhari', source: 'Sahih al-Bukhari', text: 'Islam is built upon five: the testimony…', grade: 'Sahih', kind: 'community', rating: 96 },
  { ref: '15', book: 'Muslim', source: 'Sahih Muslim', text: 'Whoever believes in Allah and the Last Day, let him speak good or remain silent…', grade: 'Sahih', kind: 'gemini', rating: null, votes: 3 },
  { ref: '2517', book: 'Tirmidhi', source: 'Jami\u02BB at-Tirmidhi', text: 'Leave that which makes you doubt for that which does not make you doubt.', grade: 'Hasan Sahih', kind: 'official' },
  { ref: '224', book: 'Ibn Majah', source: 'Sunan Ibn Majah', text: 'The seeking of knowledge is an obligation upon every Muslim.', grade: 'Sahih', kind: 'gemini', rating: 89 }];

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: '100%', overflowY: 'auto', padding: '6px 20px 30px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <IconButton name="chevronL" theme={theme} size={32} iconSize={18} />
          <IconButton name="filter" theme={theme} size={32} iconSize={17} />
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 6 }}>
          <div style={{
            width: 44, height: 44, borderRadius: RADIUS.md,
            background: `color-mix(in oklch, ${TOPIC_COLORS.Faith} 16%, transparent)`,
            border: `1px solid color-mix(in oklch, ${TOPIC_COLORS.Faith} 30%, transparent)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center'
          }}>
            <Icon name="star" size={22} color={TOPIC_COLORS.Faith} />
          </div>
          <div>
            <div className="display" style={{ fontSize: 28, color: t.text, fontWeight: 600, letterSpacing: '-0.022em' }}>Faith</div>
            <div style={{ fontSize: 12.5, color: t.textSec }}>247 hadiths · across 8 collections</div>
          </div>
        </div>

        <div style={{ display: 'flex', gap: 7, overflowX: 'auto', marginLeft: -20, marginRight: -20, paddingLeft: 20, paddingRight: 20, marginTop: 14, marginBottom: 10 }}>
          {['All', 'Bukhari', 'Muslim', 'Sunan', 'Sahih only', 'Has my language'].map((f, i) =>
          <Chip key={f} variant={i === 0 ? 'primary' : 'secondary'} theme={theme} size="md" style={{ flexShrink: 0 }}>{f}</Chip>
          )}
        </div>

        <div style={{ fontSize: 11, color: t.textTer, marginBottom: 4 }}>{hadiths.length} of 247</div>

        {hadiths.map((h, i) => {
          const sourceColor = h.kind === 'gemini' ? t.accent : h.kind === 'community' ? t.gold : t.textSec;
          const rl = h.votes && h.votes < 5 ? 'New' : h.rating ? `${h.rating}%` : '—';
          return (
            <div key={i} style={{ padding: '13px 0', borderBottom: i === hadiths.length - 1 ? 'none' : `1px solid ${t.hair}` }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 7, flexWrap: 'nowrap' }}>
                <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>{h.book} {h.ref}</span>
                <div style={{ flex: 1 }} />
                <Chip variant="outline" theme={theme} size="xs">{h.grade}</Chip>
                <Chip variant="soft" theme={theme} size="xs" style={{ color: sourceColor, background: theme === 'dark' ? `${sourceColor}28` : `${sourceColor}15` }}>
                  {h.kind === 'gemini' && <Icon name="sparkle" size={9} color={sourceColor} />}
                  {h.kind === 'gemini' ? 'AI' : h.kind === 'community' ? 'Community' : 'Official EN'}
                </Chip>
                <span style={{ fontSize: 10.5, color: t.textSec }}>{rl}</span>
              </div>
              <div className="serif" style={{ fontSize: 14, lineHeight: 1.55, color: t.text }}>{h.text}</div>
            </div>);

        })}
      </div>
    </div>);

};

const LibraryScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: 'calc(100% - 83px)', overflowY: 'auto', padding: '10px 20px 90px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: 4, marginBottom: 14 }}>
          <div className="display" style={{ fontSize: 28, color: t.text, letterSpacing: '-0.022em', fontWeight: 600 }}>Library</div>
          <IconButton name="filter" theme={theme} size={34} iconSize={17} variant="secondary" />
        </div>

        <div style={{ display: 'flex', gap: 7, overflowX: 'auto', marginLeft: -20, marginRight: -20, paddingLeft: 20, paddingRight: 20, marginBottom: 12 }}>
          {['All', 'Sahih', 'Sunan', 'Popular', 'My language', 'Downloaded'].map((f, i) =>
          <Chip key={f} variant={i === 0 ? 'primary' : 'secondary'} theme={theme} size="md" style={{ flexShrink: 0 }}>{f}</Chip>
          )}
        </div>

        {COLLECTIONS.map((c) =>
        <div key={c.slug} style={{
          padding: '14px 0', borderBottom: `1px solid ${t.hair}`,
          display: 'flex', alignItems: 'center', gap: 13
        }}>
            <div style={{
            width: 42, height: 54, borderRadius: 5,
            background: t.accent,
            flexShrink: 0, display: 'flex', alignItems: 'flex-end', padding: 6
          }}>
              <div style={{ fontSize: 9, color: t.primaryFg, fontWeight: 700, letterSpacing: '0.05em' }}>{c.grade.toUpperCase()}</div>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 15, color: t.text, fontWeight: 600, letterSpacing: '-0.005em' }}>{c.en}</div>
              <div className="arabic" style={{ fontSize: 13, color: t.textSec, textAlign: 'right', direction: 'rtl', marginTop: 1 }}>{c.ar}</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 5, fontSize: 11.5, color: t.textTer }}>
                <span>{c.count.toLocaleString()} hadith</span>
                <span style={{ width: 3, height: 3, borderRadius: 2, background: t.textTer }} />
                <span>{c.coverage}% RU</span>
              </div>
              <div style={{ marginTop: 5, width: 130 }}><ProgressBar value={c.coverage} theme={theme} height={2.5} /></div>
            </div>
            <Icon name="chevronR" size={17} color={t.textTer} />
          </div>
        )}
      </div>
      <TabBar theme={theme} active="library" />
    </div>);

};

const CollectionDetailScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  const c = COLLECTIONS[0];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 16 }}>
        <div style={{ padding: '8px 20px 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 14 }}>
            <IconButton name="chevronL" theme={theme} size={34} iconSize={18} />
            <div style={{ display: 'flex', gap: 6 }}>
              <IconButton name="share" theme={theme} size={34} iconSize={17} />
              {/* Bookmark icon on collection — marks the collection as a favorite so it pins to the top of Library */}
              <IconButton name="bookmarkFill" theme={theme} size={34} iconSize={17} color={t.gold} />
            </div>
          </div>
          <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
            <div style={{
              width: 78, height: 100, borderRadius: 6,
              background: t.accent,
              display: 'flex', alignItems: 'flex-end', padding: 9,
              boxShadow: `0 12px 32px ${t.accent}40`
            }}>
              <div style={{ fontSize: 10, color: t.primaryFg, fontWeight: 700, letterSpacing: '0.05em' }}>{c.grade.toUpperCase()}</div>
            </div>
            <div style={{ flex: 1, paddingTop: 2 }}>
              <div className="display" style={{ fontSize: 22, color: t.text, lineHeight: 1.15, letterSpacing: '-0.02em', fontWeight: 600 }}>{c.en}</div>
              <div className="arabic" style={{ fontSize: 17, color: t.textSec, textAlign: 'right', direction: 'rtl', marginTop: 4 }}>{c.ar}</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 7, fontSize: 12, color: t.textSec }}>
                <span>{c.count.toLocaleString()} hadith</span><span>·</span><span>97 books</span>
              </div>
            </div>
          </div>

          {/* Coverage panel */}
          <Card theme={theme} style={{ marginTop: 14, padding: '12px 14px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
              <div style={{ fontSize: 12, color: t.textSec, fontWeight: 500 }}>Russian coverage</div>
              <div style={{ fontSize: 13, color: t.text, fontWeight: 600 }}>38%</div>
            </div>
            <ProgressBar theme={theme} height={6} segments={[
            { value: 4, color: t.gold },
            { value: 26, color: t.accent },
            { value: 8, color: t.textTer }]
            } />
            <div style={{ display: 'flex', gap: 10, marginTop: 8, fontSize: 11, color: t.textSec, flexWrap: 'wrap' }}>
              <span><span style={{ display: 'inline-block', width: 7, height: 7, borderRadius: 4, background: t.gold, marginRight: 5 }} />Community</span>
              <span><span style={{ display: 'inline-block', width: 7, height: 7, borderRadius: 4, background: t.accent, marginRight: 5 }} />AI cached</span>
              <span><span style={{ display: 'inline-block', width: 7, height: 7, borderRadius: 4, background: t.textTer, marginRight: 5 }} />Missing</span>
            </div>
          </Card>

          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            <Button variant="primary" theme={theme} size="md" style={{ flex: 1 }}>Continue reading</Button>
            <IconButton name="download" theme={theme} size={42} iconSize={18} variant="outline" />
          </div>
        </div>

        <div style={{ padding: '6px 20px 24px' }}>
          <SectionHeader theme={theme}>Books</SectionHeader>
          {[
          ['Revelation', 7, 'الوحي', 100],
          ['Belief', 51, 'الإيمان', 11],
          ['Knowledge', 76, 'العلم', 88],
          ['Ablutions', 113, 'الوضوء', 22],
          ['Ghusl', 41, 'الغسل', 6],
          ['Menses', 31, 'الحيض', 14],
          ['Tayammum', 16, 'التيمم', 0]].
          map(([name, count, ar, cov], i) =>
          <Row key={name} theme={theme}
          leading={<div style={{ width: 30, height: 30, borderRadius: RADIUS.sm, background: t.surface2, color: t.textSec, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12.5, fontWeight: 600 }}>{String(i + 1).padStart(2, '0')}</div>}
          title={name}
          subtitle={<span><span className="arabic">{ar}</span> · {count} hadith · {cov}% RU</span>}
          trailing={<Icon name="chevronR" size={16} color={t.textTer} />} />

          )}
        </div>
      </div>
    </div>);

};

const SearchScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: '100%', overflowY: 'auto', padding: '6px 16px 24px' }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 14 }}>
          <div style={{
            flex: 1, display: 'flex', alignItems: 'center', gap: 9,
            padding: '10px 13px', background: t.surface2, borderRadius: RADIUS.md
          }}>
            <Icon name="search" size={17} color={t.textSec} />
            <span style={{ fontSize: 14.5, color: t.text, letterSpacing: '-0.005em' }}>intention</span>
            <div style={{ flex: 1 }} />
            <Icon name="close" size={15} color={t.textTer} />
          </div>
          <button style={{ background: 'none', border: 'none', fontSize: 14, color: t.accent, padding: 0, cursor: 'pointer', fontWeight: 500, fontFamily: 'Outfit, sans-serif' }}>Cancel</button>
        </div>

        {/* Filter chips — no language filter now */}
        <div style={{ display: 'flex', gap: 7, overflowX: 'auto', marginLeft: -16, marginRight: -16, paddingLeft: 16, paddingRight: 16, marginBottom: 14 }}>
          {['All', 'Bukhari', 'Muslim', 'Sahih', 'Topics', 'Narrators'].map((f, i) =>
          <Chip key={f} variant={i === 0 ? 'primary' : 'secondary'} theme={theme} size="md" style={{ flexShrink: 0 }}>{f}</Chip>
          )}
        </div>

        <div style={{ fontSize: 11.5, color: t.textTer, marginBottom: 4 }}>32 results</div>

        {[
        {
          ref: '1:1', book: 'Bukhari', source: 'Revelation', grade: 'Sahih',
          arabic: 'إِنَّمَا الْأَعْمَالُ بِالنِّ', mark: 'يَّ', tail: 'اتِ',
          text: 'Actions are but by ', markText: 'intention', tail2: ', and every man shall have only that which he intended.'
        },
        {
          ref: '4904', book: 'Muslim', source: 'Government', grade: 'Sahih', kind: 'community',
          text: 'Verily, deeds are by their ', markText: 'intentions', tail2: ', and every person will be rewarded according to what he intended…'
        },
        {
          ref: '1', book: 'Nawawi 40', source: 'Hadith 1', grade: 'Sahih', kind: 'gemini',
          text: 'Поистине, дела оцениваются по на', markText: 'мерениям', tail2: ', и каждому достанется лишь то, что он намеревался…'
        }].
        map((r, i) =>
        <div key={i} style={{ padding: '14px 0', borderBottom: `1px solid ${t.hair}` }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 7 }}>
              <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>{r.book} {r.ref}</span>
              <div style={{ flex: 1 }} />
              <Chip variant="outline" theme={theme} size="xs">{r.grade}</Chip>
              {r.kind === 'community' && <Chip variant="soft" theme={theme} size="xs" style={{ color: t.gold, background: `${t.gold}1f` }}>Community</Chip>}
              {r.kind === 'gemini' && <Chip variant="soft" theme={theme} size="xs"><Icon name="sparkle" size={9} color={t.accent} />AI</Chip>}
            </div>
            {r.arabic &&
          <div className="arabic" style={{ fontSize: 17, lineHeight: 1.85, color: t.text, textAlign: 'right', marginBottom: 7 }}>
                {r.arabic}<mark style={{ background: `${t.accent}33`, color: t.text, padding: 0 }}>{r.mark}</mark>{r.tail}
              </div>
          }
            <div className="serif" style={{ fontSize: 14, lineHeight: 1.55, color: t.textSec }}>
              {r.text}<mark style={{ background: `${t.accent}33`, color: t.text, padding: '0 1px' }}>{r.markText}</mark>{r.tail2}
            </div>
          </div>
        )}
      </div>
    </div>);

};

// Community — no Help Review section (AI handles reviews)
const CommunityScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: 'calc(100% - 83px)', overflowY: 'auto', padding: '8px 20px 90px' }}>
        <div className="display" style={{ fontSize: 28, color: t.text, letterSpacing: '-0.022em', marginTop: 4, fontWeight: 600 }}>Community</div>
        <div style={{ fontSize: 13.5, color: t.textSec, marginTop: 4 }}>Help bring hadith to more languages</div>

        {/* Language stats */}
        <Card theme={theme} style={{ marginTop: 16, padding: '14px 16px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 13 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span style={{ fontSize: 22 }}>🇷🇺</span>
              <div>
                <div style={{ fontSize: 15, fontWeight: 600, color: t.text, letterSpacing: '-0.005em' }}>Russian</div>
                <div style={{ fontSize: 11.5, color: t.textSec }}>Translation progress</div>
              </div>
            </div>
            <Icon name="chevronD" size={16} color={t.textTer} />
          </div>
          <ProgressBar theme={theme} height={8} segments={[
          { value: 4, color: t.gold },
          { value: 26, color: t.accent },
          { value: 6, color: t.warning },
          { value: 64, color: t.textTer + '55' }]
          } />
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, marginTop: 11, fontSize: 11.5 }}>
            <div style={{ color: t.text }}><span style={{ display: 'inline-block', width: 7, height: 7, borderRadius: 4, background: t.gold, marginRight: 5 }} />Community 4%</div>
            <div style={{ color: t.text }}><span style={{ display: 'inline-block', width: 7, height: 7, borderRadius: 4, background: t.accent, marginRight: 5 }} />AI cached 26%</div>
            <div style={{ color: t.text }}><span style={{ display: 'inline-block', width: 7, height: 7, borderRadius: 4, background: t.warning, marginRight: 5 }} />Needs review 6%</div>
            <div style={{ color: t.text }}><span style={{ display: 'inline-block', width: 7, height: 7, borderRadius: 4, background: t.textTer + '88', marginRight: 5 }} />Missing 64%</div>
          </div>
        </Card>

        {/* Leaderboard */}
        <div style={{ marginTop: 22 }}>
          <SectionHeader theme={theme} right={<Segmented theme={theme} options={['Monthly', 'All time']} value="Monthly" />}>Leaderboard · Russian</SectionHeader>
          {[
          { rank: 1, name: 'Aigerim N.', stats: '124 approved · 96% avg', color: t.gold },
          { rank: 2, name: 'Ruslan K.', stats: '98 approved · 92% avg', color: 'oklch(0.7 0.02 285)' },
          { rank: 3, name: 'Aliya S.', stats: '74 approved · 94% avg', color: 'oklch(0.65 0.1 60)' },
          { rank: 4, name: 'You', stats: '38 approved · 91% avg', color: t.accent, you: true },
          { rank: 5, name: 'Damir T.', stats: '26 approved · 89% avg', color: t.textTer }].
          map((p) =>
          <Row key={p.rank} theme={theme}
          leading={
          <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
                  <div style={{ fontSize: 13, color: t.textSec, fontWeight: 600, width: 18 }}>{p.rank}</div>
                  <Avatar name={p.name} color={p.color} size={32} />
                </div>
          }
          title={<span style={{ color: p.you ? t.accent : t.text, fontWeight: p.you ? 700 : 500 }}>{p.name}</span>}
          subtitle={p.stats}
          trailing={p.rank <= 3 && <Icon name="star" size={15} color={p.color} />} />

          )}
        </div>

        {/* My contributions */}
        <div style={{ marginTop: 22 }}>
          <SectionHeader theme={theme}>My contributions · Russian</SectionHeader>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
            {[['38', 'Approved'], ['7', 'Pending'], ['91%', 'Avg rating']].map(([n, l]) =>
            <Card key={l} theme={theme} padding={12} style={{ textAlign: 'center' }}>
                <div className="display" style={{ fontSize: 20, color: t.text, fontWeight: 600, letterSpacing: '-0.015em' }}>{n}</div>
                <div style={{ fontSize: 11, color: t.textSec, marginTop: 1 }}>{l}</div>
              </Card>
            )}
          </div>
        </div>
      </div>
      <TabBar theme={theme} active="community" />
    </div>);

};

// Submit translation — with required source/proof
const SubmitTranslationScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  const h = HADITHS[1];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: '100%', overflowY: 'auto', padding: '6px 22px 30px' }}>
        {/* Top bar — minimal: close + actions only, no big title */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 22 }}>
          <IconButton name="close" theme={theme} size={32} iconSize={18} />
          <Button variant="primary" theme={theme} size="sm" disabled>Submit</Button>
        </div>

        {/* Hadith — flat, no card */}
        <div style={{ fontSize: 11, color: t.textTer, letterSpacing: '0.04em', textTransform: 'uppercase', fontWeight: 600, marginBottom: 8 }}>2:8 · Russian</div>
        <div className="arabic" style={{ fontSize: 19, lineHeight: 1.9, color: t.text, textAlign: 'right', marginBottom: 8 }}>{h.arabic}</div>
        <div className="serif" style={{ fontSize: 13, lineHeight: 1.55, color: t.textSec, marginBottom: 22 }}>
          Islam is built upon five: the testimony…
        </div>

        {/* Current */}
        <div style={{ fontSize: 11, color: t.textTer, letterSpacing: '0.04em', textTransform: 'uppercase', fontWeight: 600, marginBottom: 6 }}>Current · AI</div>
        <div className="serif" style={{ fontSize: 13, lineHeight: 1.55, color: t.textSec, marginBottom: 20, paddingLeft: 10, borderLeft: `2px solid ${t.hair}` }}>
          Ислам построен на пяти столпах: свидетельстве о единстве Аллаха и пророчестве Мухаммада…
        </div>

        {/* Editor */}
        <div style={{ fontSize: 11, color: t.textTer, letterSpacing: '0.04em', textTransform: 'uppercase', fontWeight: 600, marginBottom: 6 }}>Your translation</div>
        <div className="serif" style={{
          padding: '10px 12px', borderRadius: RADIUS.md, background: 'transparent',
          border: `1px solid ${t.accent}`, fontSize: 14, lineHeight: 1.6, color: t.text,
          minHeight: 100
        }}>
          Ислам основан на пяти столпах: свидетельстве, что нет божества, кроме Аллаха, и что Мухаммад — Посланник Аллаха; совершении молитвы; выплате закята; паломничестве; и посте в месяц Рамадан.
          <span style={{ display: 'inline-block', width: 1.5, height: 15, background: t.accent, marginLeft: 1, verticalAlign: 'text-bottom' }} />
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10.5, color: t.textTer, marginTop: 5, marginBottom: 22 }}>
          <span>Meaning over literalness</span>
          <span>247 / 400</span>
        </div>

        {/* Source — recommended (not required) */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
          <div style={{ fontSize: 11, color: t.textTer, letterSpacing: '0.04em', textTransform: 'uppercase', fontWeight: 600 }}>Source</div>
          <span style={{ fontSize: 10.5, color: t.textTer, fontWeight: 500 }}>· recommended</span>
        </div>
        <div style={{ fontSize: 11.5, color: t.textSec, marginBottom: 10, lineHeight: 1.45 }}>
          A link, citation, or screenshot helps AI verify your translation.
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <Button variant="outline" theme={theme} size="sm" icon={<Icon name="link" size={14} />} style={{ flex: 1 }}>Link</Button>
          <Button variant="outline" theme={theme} size="sm" icon={<Icon name="image" size={14} />} style={{ flex: 1 }}>Screenshot</Button>
          <Button variant="outline" theme={theme} size="sm" icon={<Icon name="edit" size={14} />} style={{ flex: 1 }}>Citation</Button>
        </div>

        {/* Tiny inline AI note — no card */}
        <div style={{ marginTop: 22, display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: 11.5, color: t.textSec, lineHeight: 1.5 }}>
          <Icon name="sparkle" size={13} color={t.accent} style={{ marginTop: 2 }} />
          <span>AI reviews on submit. High-quality submissions publish immediately.</span>
        </div>
      </div>
    </div>);

};

const YouScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: 'calc(100% - 83px)', overflowY: 'auto', padding: '8px 20px 90px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 4 }}>
          <div className="display" style={{ fontSize: 28, color: t.text, letterSpacing: '-0.022em', fontWeight: 600 }}>You</div>
          <IconButton name="sliders" theme={theme} size={34} iconSize={17} variant="secondary" />
        </div>

        <Card theme={theme} style={{ marginTop: 14, padding: 16, display: 'flex', alignItems: 'center', gap: 13 }}>
          <Avatar name="Aigerim Nurlan" color={t.accent} size={54} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
              <div style={{ fontSize: 17, fontWeight: 600, color: t.text, letterSpacing: '-0.005em' }}>Aigerim Nurlan</div>
              <Chip variant="primary" theme={theme} size="xs"><Icon name="crown" size={10} color={t.primaryFg} />Pro</Chip>
            </div>
            <div style={{ fontSize: 13, color: t.textSec, marginTop: 2 }}>Reading in Russian</div>
            <div style={{ fontSize: 11.5, color: t.textTer, marginTop: 4 }}>Joined March 2025 · @aigerim_n</div>
          </div>
        </Card>

        <div style={{ marginTop: 14, display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
          {[
          ['12', 'day streak', 'flame', t.warning],
          ['247', 'hadiths read', 'book', t.accent],
          ['38', 'contributions', 'edit', t.gold]].
          map(([num, label, icon, color]) =>
          <Card key={label} theme={theme} padding={12} style={{ textAlign: 'center' }}>
              <Icon name={icon} size={18} color={color} />
              <div className="display" style={{ fontSize: 22, color: t.text, marginTop: 4, fontWeight: 600, letterSpacing: '-0.015em' }}>{num}</div>
              <div style={{ fontSize: 10.5, color: t.textSec, marginTop: 1 }}>{label}</div>
            </Card>
          )}
        </div>

        <Card theme={theme} style={{ marginTop: 16, padding: '0 14px' }}>
          {[
          ['bookmark', 'Bookmarks', '24'],
          ['heart', 'Favorites', '8'],
          ['note', 'Notes', '12'],
          ['edit', 'My translations', '38']].
          map(([icon, title, count], i, arr) =>
          <Row key={title} theme={theme} noBorder={i === arr.length - 1}
          leading={<div style={{ width: 30, height: 30, borderRadius: RADIUS.md, background: t.surface2, color: t.textSec, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={icon} size={16} color={t.textSec} /></div>}
          title={title}
          trailing={<div style={{ display: 'flex', alignItems: 'center', gap: 6, color: t.textTer, fontSize: 12 }}>{count} <Icon name="chevronR" size={15} color={t.textTer} /></div>} />

          )}
        </Card>

        <Card theme={theme} style={{ marginTop: 14, padding: '0 14px' }}>
          {[
          ['globe', 'Reading language', 'Russian'],
          ['crown', 'Manage subscription', 'Annual · renews Jul 2026'],
          ['sliders', 'Settings', null]].
          map(([icon, title, sub], i, arr) =>
          <Row key={title} theme={theme} noBorder={i === arr.length - 1}
          leading={<div style={{ width: 30, height: 30, borderRadius: RADIUS.md, background: t.surface2, color: t.textSec, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={icon} size={16} color={t.textSec} /></div>}
          title={title} subtitle={sub}
          trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />

          )}
        </Card>

        <div style={{ marginTop: 20, textAlign: 'center', fontSize: 11, color: t.textTer }}>Hadithly v1.0.0 (build 142)</div>
      </div>
      <TabBar theme={theme} active="you" />
    </div>);

};

// Settings — separate UI language; no privacy section
const SettingsScreen = ({ theme = 'light' }) => {
  const t = themes[theme];
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div style={{ height: '100%', overflowY: 'auto', padding: '6px 20px 30px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <IconButton name="chevronL" theme={theme} size={32} iconSize={18} />
          <div className="display" style={{ fontSize: 17, color: t.text, fontWeight: 600 }}>Settings</div>
          <div style={{ width: 32 }} />
        </div>

        <SectionHeader theme={theme}>Languages</SectionHeader>
        <Card theme={theme} style={{ padding: '0 14px', marginBottom: 16 }}>
          <Row theme={theme} title="Reading language" subtitle="Russian (Русский)"
          leading={<Icon name="bookOpen" size={18} color={t.textSec} />}
          trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
          <Row theme={theme} noBorder title="App language" subtitle="English"
          leading={<Icon name="languages" size={18} color={t.textSec} />}
          trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
        </Card>

        <SectionHeader theme={theme}>Notifications</SectionHeader>
        <Card theme={theme} style={{ padding: '0 14px', marginBottom: 16 }}>
          <Row theme={theme} title="Allow notifications"
          leading={<Icon name="bell" size={18} color={t.textSec} />}
          trailing={<Switch on theme={theme} small />} />
          <Row theme={theme} title="Daily hadith" subtitle="07:30 — Russian"
          leading={<Icon name="sun" size={18} color={t.textSec} />}
          trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
          <Row theme={theme} title="Translation approved" subtitle="When your suggestion goes live"
          leading={<Icon name="check" size={18} color={t.textSec} />}
          trailing={<Switch on theme={theme} small />} />
          <Row theme={theme} title="Community milestones" subtitle="Ratings, leaderboard, coverage"
          leading={<Icon name="star" size={18} color={t.textSec} />}
          trailing={<Switch on theme={theme} small />} />
          <Row theme={theme} noBorder title="Translation rejected" subtitle="AI flagged issues with your submission"
          leading={<Icon name="info" size={18} color={t.textSec} />}
          trailing={<Switch on={false} theme={theme} small />} />
        </Card>

        <SectionHeader theme={theme}>Reading</SectionHeader>
        <Card theme={theme} style={{ padding: '0 14px', marginBottom: 16 }}>
          <Row theme={theme} title="Reader settings" subtitle="Typography, theme, layout"
          leading={<Icon name="type" size={18} color={t.textSec} />}
          trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
          <Row theme={theme} noBorder title="Color theme" subtitle="System"
          leading={<Icon name="sun" size={18} color={t.textSec} />}
          trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
        </Card>

        <SectionHeader theme={theme}>Translations</SectionHeader>
        <Card theme={theme} style={{ padding: '0 14px', marginBottom: 16 }}>
          <Row theme={theme} title="AI translations this month" subtitle="142 / 500"
          trailing={<div style={{ width: 80 }}><ProgressBar value={28} theme={theme} height={4} /></div>} />
          <Row theme={theme} title="Show AI badge always" trailing={<Switch on theme={theme} />} />
          <Row theme={theme} noBorder title="Show low-rated warning" subtitle="Below 70% rating" trailing={<Switch on theme={theme} />} />
        </Card>

        <SectionHeader theme={theme}>About</SectionHeader>
        <Card theme={theme} style={{ padding: '0 14px', marginBottom: 16 }}>
          <Row theme={theme} title="Hadith data source" subtitle="sunnah.now"
          trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
          <Row theme={theme} title="Help & feedback" trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
          <Row theme={theme} title="Terms" trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
          <Row theme={theme} noBorder title="Privacy policy" trailing={<Icon name="chevronR" size={15} color={t.textTer} />} />
        </Card>

        <Button variant="ghost" theme={theme} size="md" block style={{ color: t.danger, marginTop: 6 }}>Sign out</Button>
      </div>
    </div>);

};

Object.assign(window, { HomeScreen, NotificationsScreen, TopicDetailScreen, LibraryScreen, CollectionDetailScreen, SearchScreen, CommunityScreen, SubmitTranslationScreen, YouScreen, SettingsScreen });