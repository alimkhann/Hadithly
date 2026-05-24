import { themes } from "@hadithly/design-tokens";
import BottomSheet, { BottomSheetView } from "@gorhom/bottom-sheet";
import { router, useLocalSearchParams } from "expo-router";
import {
  Bookmark,
  ChevronRight,
  Home,
  Languages,
  List,
  Menu,
  Moon,
  Search,
  Settings,
  Share2,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
} from "lucide-react-native";
import { useMemo, useRef } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import {
  Card,
  Chip,
  GlassIconButton,
  ProgressBar,
  ReaderRow,
} from "@/components/Prototype";
import { toReaderHadith, useHadithPage } from "@/lib/hadith";

const t = themes.sepia;
const light = themes.light;
const replace = (href: string) => router.replace(href as never);

export function ReaderScreen() {
  const params = useLocalSearchParams<{ collectionSlug?: string }>();
  const collectionSlug = params.collectionSlug ?? "bukhari";
  const { items, fallback } = useHadithPage(collectionSlug, 20);
  const orderedHadiths =
    items.length > 0
      ? items.slice(0, 8).map(toReaderHadith)
      : fallback.map((hadith) => hadith);
  const sheetRef = useRef<BottomSheet>(null);
  const snapPoints = useMemo(() => ["42%", "66%"], []);

  return (
    <SafeAreaView edges={["top", "left", "right"]} style={styles.safe}>
      <View style={styles.progressPill}>
        <Text style={styles.progressLabel}>Page 12</Text>
        <View style={styles.progressTrack}>
          <View style={styles.progressFill} />
        </View>
      </View>

      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.bookHeader}>
          <Text style={styles.bookTitle}>Book of Belief</Text>
          <Text style={styles.bookArabic}>كِتَابُ الْإِيمَانِ</Text>
        </View>
        <Text style={styles.bookMeta}>Sahih al-Bukhari · 51 hadith</Text>
        <View style={styles.hairline} />

        {orderedHadiths.map((hadith, index) => (
          <View
            key={hadith.id}
            style={[
              styles.hadithBlock,
              index === orderedHadiths.length - 1 && styles.lastHadith,
            ]}
          >
            <View style={styles.metaRow}>
              <Text style={styles.ref}>
                {hadith.reference.replace("Sahih al-Bukhari · Hadith ", "")}
              </Text>
              <View style={styles.spacer} />
              <Chip variant="outline">{hadith.grade}</Chip>
              <Chip
                variant={
                  hadith.sourceLabel === "Official" ? "secondary" : "soft"
                }
              >
                <View style={styles.inlineChip}>
                  {hadith.sourceLabel !== "Official" ? (
                    <Sparkles color={light.accent} size={9} />
                  ) : null}
                  <Text
                    style={
                      hadith.sourceLabel === "Official"
                        ? styles.secondaryChipText
                        : styles.softChipText
                    }
                  >
                    {hadith.sourceLabel === "Official" ? "Official" : "AI"}
                  </Text>
                </View>
              </Chip>
              <Text style={styles.rating}>
                {hadith.ratingPercent ? `${hadith.ratingPercent}%` : "—"}
              </Text>
              <ThumbsUp color={light.accent} size={15} strokeWidth={1.7} />
              <ThumbsDown color={t.textTer} size={15} strokeWidth={1.7} />
            </View>
            <Text style={styles.arabic}>{hadith.arabic}</Text>
            <Text style={styles.translation}>{hadith.translation}</Text>
          </View>
        ))}
      </ScrollView>

      <View style={styles.leftChrome}>
        <GlassIconButton
          accessibilityLabel="Home"
          onPress={() => replace("/home")}
          size={44}
        >
          <Home color={t.text} size={20} strokeWidth={1.7} />
        </GlassIconButton>
      </View>
      <View style={styles.rightChrome}>
        <GlassIconButton
          accessibilityLabel="Open reader menu"
          onPress={() => sheetRef.current?.snapToIndex(0)}
          size={44}
        >
          <Menu color={t.text} size={20} strokeWidth={1.7} />
        </GlassIconButton>
      </View>
      <View style={styles.sideChrome}>
        <GlassIconButton accessibilityLabel="Bookmark hadith" size={40}>
          <Bookmark color={t.text} size={17} strokeWidth={1.7} />
        </GlassIconButton>
        <GlassIconButton accessibilityLabel="Search this book" size={40}>
          <Search color={t.text} size={17} strokeWidth={1.7} />
        </GlassIconButton>
      </View>

      <BottomSheet
        backgroundStyle={styles.sheetBg}
        enablePanDownToClose
        handleIndicatorStyle={styles.sheetHandle}
        index={-1}
        ref={sheetRef}
        snapPoints={snapPoints}
      >
        <BottomSheetView style={styles.sheet}>
          <Text style={styles.sheetTitle}>Menu</Text>

          <Card padding={14} style={styles.readingCard}>
            <Text style={styles.readingEyebrow}>You&apos;re reading</Text>
            <Text style={styles.readingTitle}>Sahih al-Bukhari · Belief</Text>
            <View style={styles.readingProgress}>
              <View style={styles.progressFlex}>
                <ProgressBar value={11} />
              </View>
              <Text style={styles.readingMeta}>11% · Hadith 8 of 51</Text>
            </View>
          </Card>

          <Card padding={0} style={styles.actionCard}>
            <ReaderRow
              icon={<List color={light.textSec} size={19} />}
              title="Book contents"
              subtitle="Jump to any book or hadith"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Bookmark color={light.textSec} size={18} />}
              title="Bookmarks, favorites, notes"
              subtitle="24 saved"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Search color={light.textSec} size={18} />}
              title="Search in this book"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Settings color={light.textSec} size={18} />}
              title="Reader settings"
              subtitle="Typography, theme, display"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Share2 color={light.textSec} size={18} />}
              last
              title="Share hadith"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
          </Card>

          <View style={styles.disclaimer}>
            <Languages color={light.accent} size={18} />
            <Text style={styles.disclaimerText}>
              Gemini AI translations may contain mistakes. Authenticity grades
              are never determined by AI.
            </Text>
            <Moon color={light.textTer} size={17} />
          </View>
        </BottomSheetView>
      </BottomSheet>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    backgroundColor: t.bg,
    flex: 1,
  },
  progressPill: {
    alignItems: "center",
    left: 0,
    position: "absolute",
    right: 0,
    top: 8,
    zIndex: 10,
  },
  progressLabel: {
    color: t.text,
    fontSize: 11,
    fontWeight: "700",
    marginBottom: 4,
  },
  progressTrack: {
    backgroundColor: "rgba(0,0,0,0.12)",
    borderRadius: 3,
    height: 5,
    overflow: "hidden",
    width: 90,
  },
  progressFill: {
    backgroundColor: t.accent,
    height: "100%",
    width: "11%",
  },
  content: {
    paddingBottom: 132,
    paddingHorizontal: 22,
    paddingTop: 36,
  },
  bookHeader: {
    alignItems: "baseline",
    flexDirection: "row",
    gap: 12,
    justifyContent: "space-between",
    marginBottom: 4,
  },
  bookTitle: {
    color: t.text,
    fontSize: 20,
    fontWeight: "600",
    letterSpacing: -0.2,
  },
  bookArabic: {
    color: t.textSec,
    fontSize: 16,
    textAlign: "right",
    writingDirection: "rtl",
  },
  bookMeta: {
    color: t.textTer,
    fontSize: 10.5,
    fontWeight: "700",
    letterSpacing: 0.8,
    marginBottom: 14,
    textTransform: "uppercase",
  },
  hairline: {
    backgroundColor: t.hair,
    height: StyleSheet.hairlineWidth,
  },
  hadithBlock: {
    borderBottomColor: t.hair,
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingVertical: 22,
  },
  lastHadith: {
    borderBottomWidth: 0,
  },
  metaRow: {
    alignItems: "center",
    flexDirection: "row",
    flexWrap: "nowrap",
    gap: 5,
    marginBottom: 17,
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
    color: light.accentText,
    fontSize: 10.5,
    fontWeight: "600",
  },
  secondaryChipText: {
    color: light.text,
    fontSize: 10.5,
    fontWeight: "600",
  },
  rating: {
    color: t.textSec,
    fontSize: 10.5,
  },
  arabic: {
    color: t.text,
    fontSize: 26,
    lineHeight: 53,
    textAlign: "right",
    writingDirection: "rtl",
  },
  translation: {
    color: t.text,
    fontFamily: "Georgia",
    fontSize: 16.5,
    lineHeight: 28,
    marginTop: 13,
  },
  leftChrome: {
    bottom: 28,
    left: 18,
    position: "absolute",
    zIndex: 20,
  },
  rightChrome: {
    bottom: 28,
    position: "absolute",
    right: 18,
    zIndex: 20,
  },
  sideChrome: {
    gap: 9,
    position: "absolute",
    right: 18,
    top: "46%",
    zIndex: 20,
  },
  sheetBg: {
    backgroundColor: light.bg,
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
  },
  sheetHandle: {
    backgroundColor: light.hair,
    width: 44,
  },
  sheet: {
    gap: 12,
    paddingHorizontal: 20,
    paddingTop: 2,
  },
  sheetTitle: {
    color: light.text,
    fontSize: 18,
    fontWeight: "700",
    marginBottom: 2,
    textAlign: "center",
  },
  readingCard: {
    backgroundColor: light.surface2,
    borderWidth: 0,
  },
  readingEyebrow: {
    color: light.textTer,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.7,
    textTransform: "uppercase",
  },
  readingTitle: {
    color: light.text,
    fontSize: 15,
    fontWeight: "700",
    marginTop: 4,
  },
  readingProgress: {
    alignItems: "center",
    flexDirection: "row",
    gap: 8,
    marginTop: 8,
  },
  progressFlex: {
    flex: 1,
  },
  readingMeta: {
    color: light.textSec,
    fontSize: 11,
  },
  actionCard: {
    paddingHorizontal: 14,
  },
  disclaimer: {
    alignItems: "center",
    backgroundColor: light.surface2,
    borderRadius: 10,
    flexDirection: "row",
    gap: 10,
    padding: 12,
  },
  disclaimerText: {
    color: light.textSec,
    flex: 1,
    fontSize: 12,
    lineHeight: 17,
  },
});
