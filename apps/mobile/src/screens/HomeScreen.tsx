import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import {
  ArrowRight,
  BellDot,
  BookOpen,
  ChevronRight,
  Search,
} from "lucide-react-native";
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import {
  Card,
  Chip,
  GlassIconButton,
  PrimaryButton,
  ProgressBar,
  SectionHeader,
} from "@/components/Prototype";
import {
  toCollectionCard,
  toReaderHadith,
  useBooks,
  useHadithPage,
} from "@/lib/hadith";
import { registerDailyHadithNotifications } from "@/lib/notifications";
import { buildReaderHref } from "@/lib/reader-state";

const t = themes.light;
const go = (href: string) => router.push(href as never);

export function HomeScreen() {
  const { height } = useWindowDimensions();
  const { books, isLoading: booksLoading } = useBooks();
  const dailyPage = useHadithPage({
    collectionSlug: "bukhari",
    page: 1,
    pageSize: 1,
  });
  const collections = books.map(toCollectionCard);
  const dailyHadith = dailyPage.items[0]
    ? toReaderHadith(dailyPage.items[0])
    : null;
  const continueCollection = collections[0];
  const continueHref = continueCollection
    ? buildReaderHref({ collectionSlug: continueCollection.slug, page: 1 })
    : "/reader/bukhari?page=1&pageSize=8";

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
          <Text style={styles.searchText}>Search hadiths and collections…</Text>
        </Pressable>

        <View style={styles.section}>
          <SectionHeader>Today's hadith</SectionHeader>
          <Card
            padding={18}
            style={[styles.dailyCard, { maxHeight: Math.floor(height * 0.46) }]}
          >
            {dailyHadith ? (
              <>
                <View style={styles.metaRow}>
                  <Text style={styles.ref}>{dailyHadith.providerHadithId}</Text>
                  <View style={styles.spacer} />
                  <Chip variant="outline">{dailyHadith.grade}</Chip>
                  <Chip variant="secondary">Official</Chip>
                </View>
                <Text numberOfLines={7} style={styles.arabic}>
                  {dailyHadith.arabic}
                </Text>
                <Text numberOfLines={3} style={styles.translation}>
                  {dailyHadith.translation}
                </Text>
                <View style={styles.cardFooter}>
                  <Text style={styles.narrator}>
                    {dailyHadith.narrator || dailyHadith.book}
                  </Text>
                  <Pressable onPress={() => go(continueHref)}>
                    <PrimaryButton
                      iconRight={<ArrowRight color="#FFFFFF" size={13} />}
                    >
                      Read today
                    </PrimaryButton>
                  </Pressable>
                </View>
              </>
            ) : (
              <Text style={styles.emptyText}>
                {dailyPage.isLoading
                  ? "Loading today's hadith..."
                  : "Today's hadith is unavailable. Check the API connection."}
              </Text>
            )}
          </Card>
        </View>

        {continueCollection ? (
          <View style={styles.section}>
            <SectionHeader>Continue reading</SectionHeader>
            <Pressable onPress={() => go(continueHref)}>
              <Card padding={14} style={styles.continueCard}>
                <View style={styles.bookTile}>
                  <BookOpen color="#FFFFFF" size={22} />
                </View>
                <View style={styles.continueText}>
                  <Text style={styles.continueTitle}>
                    {continueCollection.title}
                  </Text>
                  <Text style={styles.continueSubtitle}>
                    Start reading collection
                  </Text>
                  <View style={styles.progressWrap}>
                    <ProgressBar value={0} />
                  </View>
                  <Text style={styles.continueTime}>Page 1</Text>
                </View>
                <ChevronRight color={t.textTer} size={18} />
              </Card>
            </Pressable>
          </View>
        ) : null}

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
                  {collection.arabic ? (
                    <Text style={styles.collectionArabic}>
                      {collection.arabic}
                    </Text>
                  ) : null}
                  <Text style={styles.collectionMeta}>
                    {collection.count
                      ? `${collection.count.toLocaleString()} hadith`
                      : "Provider collection"}
                  </Text>
                </Card>
              </Pressable>
            ))}
            {!booksLoading && collections.length === 0 ? (
              <Text style={styles.emptyText}>
                No provider collections loaded.
              </Text>
            ) : null}
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
  emptyText: {
    color: t.textSec,
    fontSize: 13,
    lineHeight: 20,
  },
  dailyCard: {
    overflow: "hidden",
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
