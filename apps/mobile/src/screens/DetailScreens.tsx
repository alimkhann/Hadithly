import { themes } from "@hadithly/design-tokens";
import { router, useLocalSearchParams } from "expo-router";
import { Bookmark, Check, ChevronLeft, Download, Edit3, Filter, Image as ImageIcon, Link, Search, Share2, Sparkles, X } from "lucide-react-native";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button, Card, Chip, IconButton, ProgressBar, Row, SectionHeader, TopicChip } from "@/components/Prototype";
import { bookRows, collections, hadiths, topics } from "@/data/sample";

const t = themes.light;
const go = (href: string) => router.push(href as never);

export function NotificationsScreen() {
  const items = [
    ["Your translation was approved", "\"Поистине, дела оцениваются...\" · Bukhari 1:1", "12m ago", true],
    ["Your translation reached 90% rating", "14 votes · Muslim 15 · Russian", "2h ago", true],
    ["AI accepted your suggestion", "Quality score 94 - published as default", "Yesterday", true],
    ["Today's hadith is ready", "Bukhari 1:1 · 7:30 AM", "Yesterday", false],
    ["You're now top 5 in Russian", "This month · 38 approved translations", "4 days ago", false]
  ] as const;
  return (
    <PlainShell title="Notifications">
      {items.map(([title, sub, time, unread], index) => (
        <View key={title} style={styles.notification}>
          <View style={styles.notifIcon}><Sparkles color={index < 3 ? t.accent : t.textSec} size={17} /></View>
          <View style={styles.notifCopy}><Text style={styles.notifTitle}>{title}</Text><Text style={styles.notifSub}>{sub}</Text><Text style={styles.notifTime}>{time}</Text></View>
          {unread ? <View style={styles.unreadDot} /> : null}
        </View>
      ))}
      <Button block style={styles.topGap} variant="ghost">Mark all as read</Button>
    </PlainShell>
  );
}

export function TopicDetailScreen() {
  const { slug } = useLocalSearchParams<{ slug?: string }>();
  const topic = topics.find((item) => item.label.toLowerCase() === slug) ?? topics[0];
  return (
    <PlainShell action={<IconButton size={32}><Filter color={t.text} size={17} /></IconButton>}>
      <View style={styles.topicHero}>
        <TopicChip color={topic.color} label={topic.label} />
        <Text style={styles.bigTitle}>{topic.label}</Text>
        <Text style={styles.subtitle}>247 hadiths · across 8 collections</Text>
      </View>
      <ScrollView contentContainerStyle={styles.filters} horizontal showsHorizontalScrollIndicator={false}>
        {["All", "Bukhari", "Muslim", "Sunan", "Sahih only", "Has my language"].map((filter, index) => <Chip key={filter} variant={index === 0 ? "primary" : "secondary"}>{filter}</Chip>)}
      </ScrollView>
      <Text style={styles.count}>{hadiths.length} of 247</Text>
      {hadiths.map((hadith) => <ResultRow key={hadith.id} hadith={hadith} />)}
    </PlainShell>
  );
}

export function CollectionDetailScreen() {
  const { slug } = useLocalSearchParams<{ slug?: string }>();
  const collection = collections.find((item) => item.slug === slug) ?? collections[0];
  return (
    <PlainShell action={<View style={styles.iconRow}><IconButton size={34}><Share2 color={t.text} size={17} /></IconButton><IconButton size={34}><Bookmark color={t.gold} fill={t.gold} size={17} /></IconButton></View>}>
      <View style={styles.collectionHero}>
        <View style={styles.bigBook}><Text style={styles.bigBookText}>{collection.grade.toUpperCase()}</Text></View>
        <View style={styles.collectionHeroCopy}>
          <Text style={styles.collectionHeroTitle}>{collection.title}</Text>
          <Text style={styles.collectionHeroArabic}>{collection.arabic}</Text>
          <Text style={styles.subtitle}>{collection.count.toLocaleString()} hadith · 97 books</Text>
        </View>
      </View>
      <Card padding={14} style={styles.topGap}>
        <View style={styles.coverageTop}><Text style={styles.coverageLabel}>Russian coverage</Text><Text style={styles.coverageValue}>38%</Text></View>
        <ProgressBar height={6} segments={[{ value: 4, color: t.gold }, { value: 26, color: t.accent }, { value: 8, color: t.textTer }]} />
      </Card>
      <View style={styles.buttonRow}>
        <Button block onPress={() => go(`/reader/${collection.slug}`)}>Continue reading</Button>
        <IconButton size={42}><Download color={t.text} size={18} /></IconButton>
      </View>
      <SectionHeader>Books</SectionHeader>
      {bookRows.map(([name, count, arabic, coverage], index) => (
        <Row
          key={name}
          leading={<View style={styles.bookNumber}><Text style={styles.bookNumberText}>{String(index + 1).padStart(2, "0")}</Text></View>}
          onPress={() => go(`/reader/${collection.slug}`)}
          subtitle={<Text style={styles.rowSubtitle}>{arabic} · {count} hadith · {coverage}% RU</Text>}
          title={name}
        />
      ))}
    </PlainShell>
  );
}

export function SearchScreen() {
  return (
    <PlainShell backLabel="Cancel" title="">
      <View style={styles.searchBar}><Search color={t.textSec} size={17} /><Text style={styles.searchText}>intention</Text><X color={t.textTer} size={15} /></View>
      <ScrollView contentContainerStyle={styles.filters} horizontal showsHorizontalScrollIndicator={false}>
        {["All", "Bukhari", "Muslim", "Sahih", "Topics", "Narrators"].map((filter, index) => <Chip key={filter} variant={index === 0 ? "primary" : "secondary"}>{filter}</Chip>)}
      </ScrollView>
      <Text style={styles.count}>32 results</Text>
      {hadiths.slice(0, 3).map((hadith) => <ResultRow key={hadith.id} hadith={hadith} />)}
    </PlainShell>
  );
}

export function SubmitTranslationScreen() {
  const h = hadiths[1];
  return (
    <PlainShell action={<Button disabled>Submit</Button>} close>
      <Text style={styles.micro}>2:8 · Russian</Text>
      <Text style={styles.submitArabic}>{h.arabic}</Text>
      <Text style={styles.submitEnglish}>Islam is built upon five: the testimony...</Text>
      <Text style={styles.micro}>Current · AI</Text>
      <Text style={styles.currentTranslation}>Ислам построен на пяти столпах: свидетельстве о единстве Аллаха и пророчестве Мухаммада...</Text>
      <Text style={styles.micro}>Your translation</Text>
      <View style={styles.editor}><Text style={styles.editorText}>{h.translation}<Text style={styles.cursor}>|</Text></Text></View>
      <View style={styles.editorMeta}><Text style={styles.muted}>Meaning over literalness</Text><Text style={styles.muted}>247 / 400</Text></View>
      <Text style={styles.micro}>Source · recommended</Text>
      <Text style={styles.subtitle}>A link, citation, or screenshot helps AI verify your translation.</Text>
      <View style={styles.buttonRow}>
        <Button icon={<Link color={t.text} size={14} />} variant="outline">Link</Button>
        <Button icon={<ImageIcon color={t.text} size={14} />} variant="outline">Screenshot</Button>
        <Button icon={<Edit3 color={t.text} size={14} />} variant="outline">Citation</Button>
      </View>
      <View style={styles.aiNote}><Sparkles color={t.accent} size={13} /><Text style={styles.aiNoteText}>AI reviews on submit. High-quality submissions publish immediately.</Text></View>
    </PlainShell>
  );
}

export function SettingsScreen() {
  return (
    <PlainShell title="Settings">
      <Card padding={0} style={styles.actionCard}>
        <Row subtitle="Arabic, translation, transliteration" title="Display" />
        <Row subtitle="Light · Dark · Sepia" title="Theme" />
        <Row subtitle="Arabic 26 pt · Translation 16 pt" title="Typography" />
        <Row last subtitle="Daily hadith · 07:30 local" title="Notifications" />
      </Card>
      <Card padding={0} style={styles.actionCard}>
        <Row subtitle="Clerk account and sync" title="Account" />
        <Row subtitle="RevenueCat entitlement" title="Hadithly Pro" />
        <Row last subtitle="Terms, Privacy, Sources" title="About" />
      </Card>
    </PlainShell>
  );
}

function ResultRow({ hadith }: { hadith: (typeof hadiths)[number] }) {
  return (
    <Pressable onPress={() => go(`/reader/${hadith.collectionSlug}?hadithId=${hadith.id}`)} style={styles.result}>
      <View style={styles.resultMeta}><Text style={styles.ref}>{hadith.ref}</Text><View style={styles.flex} /><Chip variant="outline">{hadith.grade}</Chip><Chip variant={hadith.sourceLabel === "Community" ? "soft" : "secondary"}>{hadith.sourceLabel === "Gemini AI" ? "AI" : hadith.sourceLabel}</Chip></View>
      <Text style={styles.resultArabic}>{hadith.arabic.slice(0, 80)}</Text>
      <Text style={styles.resultText}>{hadith.english}</Text>
    </Pressable>
  );
}

function PlainShell({ children, title, action, close, backLabel }: { children: React.ReactNode; title?: string; action?: React.ReactNode; close?: boolean; backLabel?: string }) {
  return (
    <SafeAreaView edges={["top"]} style={styles.safe}>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.topBar}>
          {close ? <IconButton onPress={() => router.back()} size={32}><X color={t.text} size={18} /></IconButton> : <IconButton onPress={() => router.back()} size={32}><ChevronLeft color={t.text} size={18} /></IconButton>}
          {title ? <Text style={styles.navTitle}>{title}</Text> : backLabel ? <Text onPress={() => router.back()} style={styles.cancel}>{backLabel}</Text> : <View style={styles.flex} />}
          {action ?? <View style={styles.headerPlaceholder} />}
        </View>
        {children}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { backgroundColor: t.bg, flex: 1 },
  content: { paddingBottom: 32, paddingHorizontal: 20, paddingTop: 6 },
  topBar: { alignItems: "center", flexDirection: "row", justifyContent: "space-between", marginBottom: 16 },
  navTitle: { color: t.text, fontSize: 18, fontWeight: "700" },
  headerPlaceholder: { width: 32 },
  cancel: { color: t.accent, fontSize: 14, fontWeight: "600" },
  flex: { flex: 1 },
  notification: { borderBottomColor: t.hair, borderBottomWidth: StyleSheet.hairlineWidth, flexDirection: "row", gap: 12, paddingVertical: 13 },
  notifIcon: { alignItems: "center", backgroundColor: t.accentSoft, borderRadius: 7, height: 36, justifyContent: "center", width: 36 },
  notifCopy: { flex: 1 },
  notifTitle: { color: t.text, fontSize: 13.5, fontWeight: "700", lineHeight: 18 },
  notifSub: { color: t.textSec, fontSize: 12.5, lineHeight: 18, marginTop: 2 },
  notifTime: { color: t.textTer, fontSize: 11, marginTop: 4 },
  unreadDot: { backgroundColor: t.accent, borderRadius: 4, height: 7, marginTop: 6, width: 7 },
  topGap: { marginTop: 16 },
  topicHero: { alignItems: "flex-start", gap: 8, marginBottom: 14 },
  bigTitle: { color: t.text, fontSize: 28, fontWeight: "700", letterSpacing: -0.5 },
  subtitle: { color: t.textSec, fontSize: 12.5, lineHeight: 18 },
  filters: { gap: 7, paddingBottom: 14 },
  count: { color: t.textTer, fontSize: 11.5, marginBottom: 4 },
  result: { borderBottomColor: t.hair, borderBottomWidth: StyleSheet.hairlineWidth, paddingVertical: 14 },
  resultMeta: { alignItems: "center", flexDirection: "row", gap: 5, marginBottom: 7 },
  ref: { color: t.textTer, fontSize: 10.5, fontWeight: "700" },
  resultArabic: { color: t.text, fontSize: 17, lineHeight: 31, marginBottom: 7, textAlign: "right", writingDirection: "rtl" },
  resultText: { color: t.textSec, fontFamily: "Georgia", fontSize: 14, lineHeight: 22 },
  iconRow: { flexDirection: "row", gap: 6 },
  collectionHero: { flexDirection: "row", gap: 14 },
  bigBook: { alignItems: "flex-start", backgroundColor: t.accent, borderRadius: 6, height: 100, justifyContent: "flex-end", padding: 9, width: 78 },
  bigBookText: { color: "#FFFFFF", fontSize: 10, fontWeight: "800" },
  collectionHeroCopy: { flex: 1, paddingTop: 2 },
  collectionHeroTitle: { color: t.text, fontSize: 22, fontWeight: "700", lineHeight: 25 },
  collectionHeroArabic: { color: t.textSec, fontSize: 17, marginTop: 4, textAlign: "right", writingDirection: "rtl" },
  coverageTop: { alignItems: "center", flexDirection: "row", justifyContent: "space-between", marginBottom: 8 },
  coverageLabel: { color: t.textSec, fontSize: 12, fontWeight: "600" },
  coverageValue: { color: t.text, fontSize: 13, fontWeight: "700" },
  buttonRow: { flexDirection: "row", gap: 8, marginVertical: 14 },
  bookNumber: { alignItems: "center", backgroundColor: t.surface2, borderRadius: 5, height: 30, justifyContent: "center", width: 30 },
  bookNumberText: { color: t.textSec, fontSize: 12.5, fontWeight: "700" },
  rowSubtitle: { color: t.textSec, fontSize: 12, marginTop: 2 },
  searchBar: { alignItems: "center", backgroundColor: t.surface2, borderRadius: 7, flexDirection: "row", gap: 9, marginBottom: 14, paddingHorizontal: 13, paddingVertical: 10 },
  searchText: { color: t.text, flex: 1, fontSize: 14.5 },
  micro: { color: t.textTer, fontSize: 11, fontWeight: "700", letterSpacing: 0.5, marginBottom: 8, textTransform: "uppercase" },
  submitArabic: { color: t.text, fontSize: 19, lineHeight: 36, marginBottom: 8, textAlign: "right", writingDirection: "rtl" },
  submitEnglish: { color: t.textSec, fontFamily: "Georgia", fontSize: 13, lineHeight: 21, marginBottom: 22 },
  currentTranslation: { borderLeftColor: t.hair, borderLeftWidth: 2, color: t.textSec, fontFamily: "Georgia", fontSize: 13, lineHeight: 21, marginBottom: 20, paddingLeft: 10 },
  editor: { borderColor: t.accent, borderRadius: 7, borderWidth: 1, minHeight: 100, paddingHorizontal: 12, paddingVertical: 10 },
  editorText: { color: t.text, fontFamily: "Georgia", fontSize: 14, lineHeight: 23 },
  cursor: { color: t.accent },
  editorMeta: { flexDirection: "row", justifyContent: "space-between", marginBottom: 22, marginTop: 5 },
  muted: { color: t.textTer, fontSize: 10.5 },
  aiNote: { alignItems: "flex-start", flexDirection: "row", gap: 8, marginTop: 8 },
  aiNoteText: { color: t.textSec, flex: 1, fontSize: 11.5, lineHeight: 17 },
  actionCard: { marginBottom: 14, paddingHorizontal: 14 }
});
