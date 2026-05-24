import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import {
  ArrowRight,
  BellDot,
  BookOpen,
  ChevronRight,
  Search,
  Sparkles,
} from "lucide-react-native";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import {
  Card,
  Chip,
  GlassIconButton,
  PrimaryButton,
  ProgressBar,
  SectionHeader,
  TopicChip,
} from "@/components/Prototype";
import { dailyHadith, topics } from "@/data/sample";
import { toCollectionCard, useBooks } from "@/lib/hadith";
import { registerDailyHadithNotifications } from "@/lib/notifications";

const t = themes.light;
const go = (href: string) => router.push(href as never);

export function HomeScreen() {
  const { books } = useBooks();
  const collections = books.map(toCollectionCard);

  return (
    <SafeAreaView edges={["top"]} style={styles.safe}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.header}>
          <View>
            <Text style={styles.date}>Friday · 23 Dhul Qi'dah</Text>
            <Text style={styles.greeting}>Assalamu alaikum</Text>
          </View>
          <GlassIconButton
            accessibilityLabel="Enable daily hadith notifications"
            onPress={() => void registerDailyHadithNotifications()}
            size={38}
            style={styles.headerButton}
          >
            <BellDot color={t.text} size={22} strokeWidth={1.7} />
          </GlassIconButton>
        </View>

        <Pressable onPress={() => go("/search")} style={styles.search}>
          <Search color={t.textSec} size={17} strokeWidth={1.8} />
          <Text style={styles.searchText}>
            Search hadiths, collections, topics…
          </Text>
        </Pressable>

        <View style={styles.section}>
          <SectionHeader>Today's hadith</SectionHeader>
          <Card padding={18}>
            <View style={styles.metaRow}>
              <Text style={styles.ref}>1:1</Text>
              <View style={styles.spacer} />
              <Chip variant="outline">{dailyHadith.grade}</Chip>
              <Chip variant="soft">
                <View style={styles.inlineChip}>
                  <Sparkles color={t.accent} size={10} />
                  <Text style={styles.softChipText}>AI</Text>
                </View>
              </Chip>
              <Text style={styles.rating}>{dailyHadith.ratingPercent}%</Text>
            </View>
            <Text style={styles.arabic}>{dailyHadith.arabic}</Text>
            <Text style={styles.translation}>
              Поистине, дела оцениваются по намерениям, и каждому достанется
              лишь то, что он намеревался обрести…
            </Text>
            <View style={styles.cardFooter}>
              <Text style={styles.narrator}>Narrated by Umar (ra)</Text>
              <Pressable onPress={() => go("/reader/bukhari")}>
                <PrimaryButton
                  iconRight={<ArrowRight color="#FFFFFF" size={13} />}
                >
                  Read today
                </PrimaryButton>
              </Pressable>
            </View>
          </Card>
        </View>

        <View style={styles.section}>
          <SectionHeader>Continue reading</SectionHeader>
          <Pressable onPress={() => go("/reader/bukhari")}>
            <Card padding={14} style={styles.continueCard}>
              <View style={styles.bookTile}>
                <BookOpen color="#FFFFFF" size={22} />
              </View>
              <View style={styles.continueText}>
                <Text style={styles.continueTitle}>Sahih al-Bukhari</Text>
                <Text style={styles.continueSubtitle}>
                  Book of Belief · Hadith 8
                </Text>
                <View style={styles.progressWrap}>
                  <ProgressBar value={11} />
                </View>
                <Text style={styles.continueTime}>11% · 2 hours ago</Text>
              </View>
              <ChevronRight color={t.textTer} size={18} />
            </Card>
          </Pressable>
        </View>

        <View style={styles.section}>
          <SectionHeader>Browse by topic</SectionHeader>
          <View style={styles.topicWrap}>
            {topics.map(({ label, color }) => (
              <Pressable
                key={label}
                onPress={() => go(`/topic/${label.toLowerCase()}`)}
              >
                <TopicChip color={color} label={label} />
              </Pressable>
            ))}
          </View>
        </View>

        <View style={styles.section}>
          <SectionHeader>Collections</SectionHeader>
          <ScrollView
            contentContainerStyle={styles.collectionRail}
            horizontal
            showsHorizontalScrollIndicator={false}
            style={styles.collectionScroll}
          >
            {collections.slice(0, 4).map((collection) => (
              <Pressable
                key={collection.slug}
                onPress={() => go(`/collection/${collection.slug}`)}
              >
                <Card padding={12} style={styles.collectionCard}>
                  <View style={styles.collectionBook}>
                    <Text style={styles.collectionGrade}>
                      {collection.grade.toUpperCase()}
                    </Text>
                  </View>
                  <Text numberOfLines={2} style={styles.collectionTitle}>
                    {collection.title}
                  </Text>
                  <Text style={styles.collectionArabic}>
                    {collection.arabic}
                  </Text>
                  <Text style={styles.collectionMeta}>
                    {collection.count.toLocaleString()} · {collection.coverage}%
                    RU
                  </Text>
                </Card>
              </Pressable>
            ))}
          </ScrollView>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    backgroundColor: t.bg,
    flex: 1,
  },
  content: {
    paddingBottom: 112,
    paddingHorizontal: 20,
    paddingTop: 8,
  },
  header: {
    alignItems: "flex-end",
    flexDirection: "row",
    justifyContent: "space-between",
    marginBottom: 18,
    marginTop: 4,
  },
  date: {
    color: t.textSec,
    fontSize: 12,
    marginBottom: 2,
  },
  greeting: {
    color: t.text,
    fontSize: 26,
    fontWeight: "600",
    letterSpacing: -0.2,
    lineHeight: 29,
  },
  headerButton: {
    borderRadius: 7,
  },
  search: {
    alignItems: "center",
    backgroundColor: t.surface2,
    borderRadius: 7,
    flexDirection: "row",
    gap: 9,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  searchText: {
    color: t.textTer,
    flex: 1,
    fontSize: 14,
  },
  section: {
    marginTop: 22,
  },
  metaRow: {
    alignItems: "center",
    flexDirection: "row",
    gap: 5,
    marginBottom: 12,
  },
  ref: {
    color: t.textTer,
    fontSize: 10.5,
    fontWeight: "600",
  },
  spacer: {
    flex: 1,
  },
  inlineChip: {
    alignItems: "center",
    flexDirection: "row",
    gap: 4,
  },
  softChipText: {
    color: t.accentText,
    fontSize: 10.5,
    fontWeight: "600",
  },
  rating: {
    color: t.textSec,
    fontSize: 10.5,
  },
  arabic: {
    color: t.text,
    fontSize: 22,
    lineHeight: 43,
    marginBottom: 12,
    textAlign: "right",
    writingDirection: "rtl",
  },
  translation: {
    color: t.textSec,
    fontFamily: "Georgia",
    fontSize: 14,
    lineHeight: 23,
    marginBottom: 14,
  },
  cardFooter: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  narrator: {
    color: t.textTer,
    flex: 1,
    fontSize: 11.5,
    marginRight: 10,
  },
  continueCard: {
    alignItems: "center",
    flexDirection: "row",
    gap: 12,
  },
  bookTile: {
    alignItems: "center",
    backgroundColor: t.accent,
    borderRadius: 5,
    height: 56,
    justifyContent: "center",
    width: 46,
  },
  continueText: {
    flex: 1,
    minWidth: 0,
  },
  continueTitle: {
    color: t.text,
    fontSize: 14.5,
    fontWeight: "600",
  },
  continueSubtitle: {
    color: t.textSec,
    fontSize: 12.5,
    marginTop: 2,
  },
  progressWrap: {
    marginTop: 7,
  },
  continueTime: {
    color: t.textTer,
    fontSize: 11,
    marginTop: 4,
  },
  topicWrap: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
  },
  collectionScroll: {
    marginHorizontal: -20,
  },
  collectionRail: {
    gap: 10,
    paddingHorizontal: 20,
  },
  collectionCard: {
    minHeight: 148,
    width: 130,
  },
  collectionBook: {
    alignItems: "flex-start",
    backgroundColor: t.accent,
    borderRadius: 4,
    height: 38,
    justifyContent: "flex-end",
    marginBottom: 10,
    padding: 5,
    width: 30,
  },
  collectionGrade: {
    color: "#FFFFFF",
    fontSize: 8.5,
    fontWeight: "800",
  },
  collectionTitle: {
    color: t.text,
    fontSize: 12.5,
    fontWeight: "600",
    lineHeight: 16,
  },
  collectionArabic: {
    color: t.textSec,
    fontSize: 12,
    marginTop: 2,
    textAlign: "right",
    writingDirection: "rtl",
  },
  collectionMeta: {
    color: t.textTer,
    fontSize: 10.5,
    marginTop: 8,
  },
});
