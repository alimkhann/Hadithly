import { useAuth } from "@clerk/expo";
import { themes } from "@hadithly/design-tokens";
import BottomSheet, { BottomSheetView } from "@gorhom/bottom-sheet";
import { router, useLocalSearchParams } from "expo-router";
import {
  Bookmark,
  ChevronLeft,
  ChevronRight,
  Home,
  Languages,
  Link2,
  List,
  Menu,
  Minus,
  Moon,
  Plus,
  Search,
  Settings,
  Share2,
  Sparkles,
  Type,
} from "lucide-react-native";
import React, { useMemo, useRef } from "react";
import {
  Linking,
  PanResponder,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import {
  Card,
  Chip,
  GlassIconButton,
  ProgressBar,
  ReaderRow,
} from "@/components/Prototype";
import { ApiError } from "@/lib/api";
import { useAuthRuntime } from "@/lib/auth-runtime";
import {
  generateTranslation,
  toReaderHadith,
  useHadithPage,
  type ApiTranslationResponse,
} from "@/lib/hadith";
import { useOnboardingState } from "@/lib/onboarding";
import {
  buildReaderHref,
  isReaderFeedbackVisible,
  normalizeReaderPage,
  normalizeReaderPageSize,
  pageProgressPercent,
  readerChromeReducer,
  swipeReaderPage,
} from "@/lib/reader-state";
import {
  nextFontScale,
  useReaderPreferences,
  type ReaderThemeName,
} from "@/lib/reader-prefs";

const t = themes.sepia;
const light = themes.light;
const replace = (href: string) => router.replace(href as never);

export function ReaderScreen() {
  const { clerkEnabled } = useAuthRuntime();
  if (clerkEnabled) return <AuthenticatedReaderScreen />;
  return <ReaderContent />;
}

function AuthenticatedReaderScreen() {
  const { getToken, isSignedIn } = useAuth();
  return (
    <ReaderContent
      getAuthToken={() => getToken()}
      signedIn={Boolean(isSignedIn)}
    />
  );
}

function ReaderContent({
  getAuthToken,
  signedIn = false,
}: {
  getAuthToken?: () => Promise<string | null>;
  signedIn?: boolean;
}) {
  const params = useLocalSearchParams<{
    collectionSlug?: string;
    page?: string;
    pageSize?: string;
    volumeId?: string;
    chapterId?: string;
  }>();
  const collectionSlug = params.collectionSlug ?? "bukhari";
  const page = normalizeReaderPage(params.page);
  const pageSize = normalizeReaderPageSize(params.pageSize);
  const volumeId = scalarParam(params.volumeId);
  const chapterId = scalarParam(params.chapterId);
  const { state: onboardingState } = useOnboardingState();
  const preferredLanguage = onboardingState.preferredLanguage;
  const { prefs, update: updateReaderPrefs } = useReaderPreferences();
  const palette = themes[prefs.theme];
  const dyn = React.useMemo(
    () => makeReaderStyles(palette, prefs.fontScale),
    [palette, prefs.fontScale],
  );
  const { items, hasMore, isLoading, error } = useHadithPage({
    collectionSlug,
    page,
    pageSize,
    volumeId,
    chapterId,
  });
  const orderedHadiths = items.map(toReaderHadith);
  const [translations, setTranslations] = React.useState<
    Record<string, ApiTranslationResponse>
  >({});
  const [translatingId, setTranslatingId] = React.useState<string | null>(null);
  const [translationErrors, setTranslationErrors] = React.useState<
    Record<string, string>
  >({});
  const [chrome, setChrome] = React.useState({
    chromeVisible: false,
    menuOpen: false,
  });
  const requestedTranslationIds = React.useRef(new Set<string>());
  const sheetRef = useRef<BottomSheet>(null);
  const snapPoints = useMemo(() => ["42%", "66%"], []);
  const firstHadith = items[0];
  const collectionName = firstHadith?.collectionName ?? collectionSlug;
  const chapterName = firstHadith?.chapterName;
  const progress = pageProgressPercent({ page, hasMore });
  const previousHref =
    page > 1
      ? buildReaderHref({
          collectionSlug,
          page: page - 1,
          pageSize,
          volumeId,
          chapterId,
        })
      : null;
  const nextHref = hasMore
    ? buildReaderHref({
        collectionSlug,
        page: page + 1,
        pageSize,
        volumeId,
        chapterId,
      })
    : null;
  const navigateToPage = React.useCallback(
    (targetPage: number) => {
      replace(
        buildReaderHref({
          collectionSlug,
          page: targetPage,
          pageSize,
          volumeId,
          chapterId,
        }),
      );
    },
    [chapterId, collectionSlug, pageSize, volumeId],
  );
  const panResponder = React.useMemo(
    () =>
      PanResponder.create({
        onMoveShouldSetPanResponder: (_event, gesture) =>
          Math.abs(gesture.dx) > 34 &&
          Math.abs(gesture.dx) > Math.abs(gesture.dy) * 1.2,
        onPanResponderRelease: (_event, gesture) => {
          if (gesture.dx < -70) {
            const target = swipeReaderPage({ page, hasMore }, "left");
            if (target !== page) navigateToPage(target);
          }
          if (gesture.dx > 70) {
            const target = swipeReaderPage({ page, hasMore }, "right");
            if (target !== page) navigateToPage(target);
          }
        },
      }),
    [hasMore, navigateToPage, page],
  );

  React.useEffect(() => {
    void saveReaderProgress({
      collectionSlug,
      page,
      pageSize,
      visibleHadithId: items[0]?.id,
    });
  }, [collectionSlug, items, page, pageSize]);

  const requestTranslation = React.useCallback(
    async (hadithId: string) => {
      if (preferredLanguage === "en" || preferredLanguage === "ar") return;
      const requestKey = `${hadithId}:${preferredLanguage}`;
      if (!getAuthToken || !signedIn) {
        return;
      }
      if (requestedTranslationIds.current.has(requestKey)) return;
      requestedTranslationIds.current.add(requestKey);
      setTranslationErrors((current) => {
        if (!current[hadithId]) return current;
        const next = { ...current };
        delete next[hadithId];
        return next;
      });
      setTranslatingId(hadithId);
      try {
        const token = await getAuthToken();
        if (!token) {
          return;
        }
        const result = await generateTranslation({
          hadithId,
          targetLanguage: preferredLanguage,
          token,
        });
        setTranslations((current) => ({ ...current, [hadithId]: result }));
      } catch (error) {
        // Only the quota wall is a paywall moment; allow a retry of other errors.
        requestedTranslationIds.current.delete(requestKey);
        if (error instanceof ApiError && error.status === 402) {
          router.push("/paywall/quota");
        } else {
          setTranslationErrors((current) => ({
            ...current,
            [hadithId]: "Translation failed. Tap to retry.",
          }));
        }
      } finally {
        setTranslatingId(null);
      }
    },
    [getAuthToken, preferredLanguage, signedIn],
  );

  React.useEffect(() => {
    if (preferredLanguage === "en" || preferredLanguage === "ar") return;
    for (const hadith of orderedHadiths) {
      if (!translations[hadith.id] && translatingId !== hadith.id) {
        void requestTranslation(hadith.id);
      }
    }
  }, [
    orderedHadiths,
    preferredLanguage,
    requestTranslation,
    translatingId,
    translations,
  ]);

  const toggleChrome = () => {
    setChrome((current) => readerChromeReducer(current, "tap"));
  };

  const openMenu = () => {
    setChrome((current) => readerChromeReducer(current, "open-menu"));
    sheetRef.current?.snapToIndex(0);
  };

  const closeMenu = () => {
    sheetRef.current?.close();
    setChrome((current) => readerChromeReducer(current, "close-menu"));
  };

  const openContents = () => {
    closeMenu();
    router.push(`/collection/${collectionSlug}` as never);
  };

  const shareCurrentPage = async () => {
    await Share.share({
      message: `${collectionName} · page ${page}\n${buildReaderHref({
        collectionSlug,
        page,
        pageSize,
        volumeId,
        chapterId,
      })}`,
    });
  };

  return (
    <SafeAreaView
      edges={["top", "left", "right"]}
      style={[styles.safe, dyn.safe]}
    >
      {chrome.chromeVisible ? (
        <View style={styles.progressPill}>
          <Text style={[styles.progressLabel, dyn.progressLabel]}>
            Page {page}
          </Text>
          <View style={styles.progressTrack}>
            <View
              style={[
                styles.progressFill,
                dyn.progressFill,
                { width: `${progress}%` },
              ]}
            />
          </View>
        </View>
      ) : null}

      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        {...panResponder.panHandlers}
      >
        <Pressable onPress={toggleChrome}>
          <View style={styles.bookHeader}>
            <Text style={[styles.bookTitle, dyn.bookTitle]}>
              {chapterName ?? collectionName}
            </Text>
            <Text style={[styles.bookArabic, dyn.bookArabic]}>
              {collectionName}
            </Text>
          </View>
          <Text style={[styles.bookMeta, dyn.bookMeta]}>
            {collectionName} · {items.length} loaded · page {page}
          </Text>
          <View style={[styles.hairline, dyn.hairline]} />

          {isLoading ? (
            <Text style={[styles.statusText, dyn.statusText]}>
              Loading page...
            </Text>
          ) : null}
          {error ? (
            <Text style={[styles.statusText, dyn.statusText]}>
              Could not load this reader page.
            </Text>
          ) : null}
          {!isLoading && !error && orderedHadiths.length === 0 ? (
            <Text style={[styles.statusText, dyn.statusText]}>
              No hadiths found for this page.
            </Text>
          ) : null}

          {orderedHadiths.map((hadith, index) => {
            const aiTranslation = translations[hadith.id];
            const aiFeedbackVisible = aiTranslation
              ? isReaderFeedbackVisible(aiTranslation.sourceLabel)
              : false;
            return (
              <View
                key={hadith.id}
                style={[
                  styles.hadithBlock,
                  dyn.hadithBlock,
                  index === orderedHadiths.length - 1 && styles.lastHadith,
                ]}
              >
                <View style={styles.metaRow}>
                  <Text style={[styles.ref, dyn.ref]}>
                    {hadith.reference.replace("Sahih al-Bukhari · Hadith ", "")}
                  </Text>
                  <View style={styles.spacer} />
                  <Chip variant="outline">{hadith.grade}</Chip>
                  <Chip variant="secondary">Official</Chip>
                </View>
                <Text style={[styles.arabic, dyn.arabic]}>{hadith.arabic}</Text>
                <Text style={[styles.translation, dyn.translation]}>
                  {hadith.translation}
                </Text>
                {aiTranslation ? (
                  <View
                    style={[styles.aiTranslationBlock, dyn.aiTranslationBlock]}
                  >
                    <View style={styles.metaRow}>
                      <Chip variant="soft">
                        <View style={styles.inlineChip}>
                          <Sparkles color={light.accent} size={9} />
                          <Text style={styles.softChipText}>
                            {aiTranslation.sourceLabel} ·{" "}
                            {aiTranslation.cached ? "cached" : "new"}
                          </Text>
                        </View>
                      </Chip>
                      {aiFeedbackVisible && aiTranslation.ratingPercent ? (
                        <Text style={[styles.rating, dyn.aiMeta]}>
                          {aiTranslation.ratingPercent}%
                        </Text>
                      ) : null}
                    </View>
                    <Text style={[styles.translation, dyn.translation]}>
                      {aiTranslation.translation}
                    </Text>
                    {aiTranslation.riskFlags.length ? (
                      <Text style={[styles.aiMeta, dyn.aiMeta]}>
                        Risk flags: {aiTranslation.riskFlags.join(", ")}
                      </Text>
                    ) : null}
                    <TranslationSources
                      translation={aiTranslation}
                      linkStyle={dyn.sourceLink}
                      labelStyle={dyn.sourcesLabel}
                    />
                  </View>
                ) : preferredLanguage !== "en" &&
                  preferredLanguage !== "ar" &&
                  !signedIn ? (
                  <Text style={[styles.aiMeta, dyn.aiMeta]}>
                    Sign in to generate missing{" "}
                    {preferredLanguage.toUpperCase()} AI translations. Cached
                    translations appear automatically.
                  </Text>
                ) : translatingId === hadith.id ? (
                  <Text style={[styles.aiMeta, dyn.aiMeta]}>
                    Generating {preferredLanguage.toUpperCase()} translation...
                  </Text>
                ) : translationErrors[hadith.id] ? (
                  <Pressable onPress={() => void requestTranslation(hadith.id)}>
                    <Text style={styles.aiError}>
                      {translationErrors[hadith.id]}
                    </Text>
                  </Pressable>
                ) : null}
              </View>
            );
          })}

          <View style={styles.pageControls}>
            <Pressable
              disabled={!previousHref}
              onPress={() => previousHref && replace(previousHref)}
              style={[
                styles.pageButton,
                dyn.pageButton,
                !previousHref && styles.disabledPage,
              ]}
            >
              <ChevronLeft
                color={previousHref ? palette.text : palette.textTer}
                size={17}
              />
              <Text style={[styles.pageButtonText, dyn.pageButtonText]}>
                Previous
              </Text>
            </Pressable>
            <Pressable
              disabled={!nextHref}
              onPress={() => nextHref && replace(nextHref)}
              style={[
                styles.pageButton,
                dyn.pageButton,
                !nextHref && styles.disabledPage,
              ]}
            >
              <Text style={[styles.pageButtonText, dyn.pageButtonText]}>
                Next
              </Text>
              <ChevronRight
                color={nextHref ? palette.text : palette.textTer}
                size={17}
              />
            </Pressable>
          </View>
        </Pressable>
      </ScrollView>

      {chrome.chromeVisible ? (
        <View style={styles.leftChrome}>
          <GlassIconButton
            accessibilityLabel="Home"
            onPress={() => replace("/home")}
            size={44}
          >
            <Home color={palette.text} size={20} strokeWidth={1.7} />
          </GlassIconButton>
        </View>
      ) : null}
      {chrome.chromeVisible ? (
        <View style={styles.rightChrome}>
          <GlassIconButton
            accessibilityLabel="Open reader menu"
            onPress={openMenu}
            size={44}
          >
            <Menu color={palette.text} size={20} strokeWidth={1.7} />
          </GlassIconButton>
        </View>
      ) : null}

      <BottomSheet
        backgroundStyle={styles.sheetBg}
        enablePanDownToClose
        handleIndicatorStyle={styles.sheetHandle}
        index={-1}
        onChange={(index) => {
          if (index < 0) {
            setChrome((current) => readerChromeReducer(current, "close-menu"));
          }
        }}
        ref={sheetRef}
        snapPoints={snapPoints}
      >
        <BottomSheetView style={styles.sheet}>
          <Text style={styles.sheetTitle}>Menu</Text>

          <Card padding={14} style={styles.readingCard}>
            <Text style={styles.readingEyebrow}>You&apos;re reading</Text>
            <Text style={styles.readingTitle}>{collectionName}</Text>
            <View style={styles.readingProgress}>
              <View style={styles.progressFlex}>
                <ProgressBar value={progress} />
              </View>
              <Text style={styles.readingMeta}>
                {progress}% · Page {page}
              </Text>
            </View>
          </Card>

          <Card padding={14} style={styles.displayCard}>
            <Text style={styles.displayLabel}>Display</Text>
            <View style={styles.themeRow}>
              {(["light", "sepia", "dark"] as ReaderThemeName[]).map((name) => {
                const active = prefs.theme === name;
                return (
                  <Pressable
                    key={name}
                    onPress={() => void updateReaderPrefs({ theme: name })}
                    style={
                      active
                        ? [styles.themeChip, styles.themeChipActive]
                        : styles.themeChip
                    }
                  >
                    <View
                      style={[
                        styles.themeDot,
                        { backgroundColor: themes[name].bg },
                      ]}
                    />
                    <Text
                      style={
                        active
                          ? [styles.themeChipText, styles.themeChipTextActive]
                          : styles.themeChipText
                      }
                    >
                      {name === "light"
                        ? "Light"
                        : name === "sepia"
                          ? "Sepia"
                          : "Dark"}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
            <View style={styles.fontRow}>
              <Type color={light.textSec} size={16} />
              <Text style={styles.fontLabel}>Text size</Text>
              <View style={styles.spacer} />
              <Pressable
                onPress={() =>
                  void updateReaderPrefs({
                    fontScale: nextFontScale(prefs.fontScale, "down"),
                  })
                }
                style={styles.fontButton}
              >
                <Minus color={light.text} size={16} />
              </Pressable>
              <Text style={styles.fontValue}>
                {Math.round(prefs.fontScale * 100)}%
              </Text>
              <Pressable
                onPress={() =>
                  void updateReaderPrefs({
                    fontScale: nextFontScale(prefs.fontScale, "up"),
                  })
                }
                style={styles.fontButton}
              >
                <Plus color={light.text} size={16} />
              </Pressable>
            </View>
          </Card>

          <Card padding={0} style={styles.actionCard}>
            <ReaderRow
              icon={<List color={light.textSec} size={19} />}
              onPress={openContents}
              title="Book contents"
              subtitle="Jump to any book or hadith"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Bookmark color={light.textSec} size={18} />}
              onPress={() => router.push("/settings" as never)}
              title="Bookmarks, favorites, notes"
              subtitle="Synced after sign-in"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Search color={light.textSec} size={18} />}
              onPress={() => router.push("/search" as never)}
              title="Search in this book"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Settings color={light.textSec} size={18} />}
              onPress={() => router.push("/settings" as never)}
              title="Reader settings"
              subtitle="Typography, theme, display"
              trailing={<ChevronRight color={light.textTer} size={15} />}
            />
            <ReaderRow
              icon={<Share2 color={light.textSec} size={18} />}
              last
              onPress={shareCurrentPage}
              title="Share page"
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

function scalarParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function TranslationSources({
  translation,
  linkStyle,
  labelStyle,
}: {
  translation: ApiTranslationResponse;
  linkStyle: { color: string };
  labelStyle: { color: string };
}) {
  const citations = translation.citations ?? [];
  const referenceUrl = translation.sourceReferenceUrl;
  if (citations.length === 0 && !referenceUrl) return null;
  const open = (url: string) => {
    void Linking.openURL(url).catch(() => undefined);
  };
  return (
    <View style={styles.sources}>
      <Text style={[styles.sourcesLabel, labelStyle]}>Sources</Text>
      {citations.slice(0, 3).map((citation) => (
        <Pressable
          key={citation.url}
          onPress={() => open(citation.url)}
          style={styles.sourceRow}
        >
          <Link2 color={linkStyle.color} size={12} />
          <Text numberOfLines={1} style={[styles.sourceLink, linkStyle]}>
            {citation.domain ?? citation.title ?? citation.url}
          </Text>
        </Pressable>
      ))}
      {referenceUrl ? (
        <Pressable onPress={() => open(referenceUrl)} style={styles.sourceRow}>
          <Link2 color={linkStyle.color} size={12} />
          <Text numberOfLines={1} style={[styles.sourceLink, linkStyle]}>
            {referenceUrl.replace(/^https?:\/\//, "")}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

type ReaderPalette = (typeof themes)[ReaderThemeName];

function makeReaderStyles(palette: ReaderPalette, scale: number) {
  return {
    safe: { backgroundColor: palette.bg },
    bookTitle: { color: palette.text },
    bookArabic: { color: palette.textSec },
    bookMeta: { color: palette.textTer },
    hairline: { backgroundColor: palette.hair },
    statusText: { color: palette.textSec },
    hadithBlock: { borderBottomColor: palette.hair },
    ref: { color: palette.textTer },
    arabic: {
      color: palette.text,
      fontSize: 26 * scale,
      lineHeight: 53 * scale,
    },
    translation: {
      color: palette.text,
      fontSize: 16.5 * scale,
      lineHeight: 28 * scale,
    },
    aiMeta: { color: palette.textTer },
    aiTranslationBlock: { borderLeftColor: palette.hair },
    pageButton: { borderColor: palette.hair },
    pageButtonText: { color: palette.text },
    progressLabel: { color: palette.text },
    progressFill: { backgroundColor: palette.accent },
    sourcesLabel: { color: palette.textTer },
    sourceLink: { color: palette.accentText },
  } as const;
}

async function saveReaderProgress(progress: {
  collectionSlug: string;
  page: number;
  pageSize: number;
  visibleHadithId?: string;
  scrollOffset?: number;
}) {
  const storage = await import("@react-native-async-storage/async-storage");
  await storage.default.setItem(
    `hadithly:reader-progress:v1:${progress.collectionSlug}`,
    JSON.stringify({
      ...progress,
      updatedAt: Date.now(),
    }),
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
  statusText: {
    color: t.textSec,
    fontSize: 13,
    lineHeight: 20,
    paddingVertical: 18,
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
  aiTranslationBlock: {
    borderLeftColor: t.hair,
    borderLeftWidth: 2,
    marginTop: 16,
    paddingLeft: 12,
  },
  aiMeta: {
    color: t.textTer,
    fontSize: 11,
    lineHeight: 16,
    marginTop: 4,
  },
  aiError: {
    color: t.danger,
    fontSize: 11.5,
    fontWeight: "600",
    lineHeight: 16,
    marginTop: 4,
  },
  sources: {
    gap: 4,
    marginTop: 12,
  },
  sourcesLabel: {
    color: t.textTer,
    fontSize: 10,
    fontWeight: "700",
    letterSpacing: 0.6,
    textTransform: "uppercase",
  },
  sourceRow: {
    alignItems: "center",
    flexDirection: "row",
    gap: 6,
  },
  sourceLink: {
    color: t.accentText,
    flexShrink: 1,
    fontSize: 12,
    fontWeight: "600",
    textDecorationLine: "underline",
  },
  displayCard: {
    backgroundColor: light.surface2,
    borderWidth: 0,
    gap: 12,
  },
  displayLabel: {
    color: light.textTer,
    fontSize: 11,
    fontWeight: "700",
    letterSpacing: 0.6,
    textTransform: "uppercase",
  },
  themeRow: {
    flexDirection: "row",
    gap: 8,
  },
  themeChip: {
    alignItems: "center",
    borderColor: light.hair,
    borderRadius: 9,
    borderWidth: 1,
    flex: 1,
    flexDirection: "row",
    gap: 7,
    justifyContent: "center",
    paddingVertical: 8,
  },
  themeChipActive: {
    backgroundColor: "#FFFFFF",
    borderColor: light.accent,
  },
  themeDot: {
    borderColor: light.hair,
    borderRadius: 6,
    borderWidth: 1,
    height: 12,
    width: 12,
  },
  themeChipText: {
    color: light.textSec,
    fontSize: 12,
    fontWeight: "600",
  },
  themeChipTextActive: {
    color: light.text,
  },
  fontRow: {
    alignItems: "center",
    flexDirection: "row",
    gap: 8,
  },
  fontLabel: {
    color: light.text,
    fontSize: 13,
    fontWeight: "600",
  },
  fontButton: {
    alignItems: "center",
    backgroundColor: "#FFFFFF",
    borderColor: light.hair,
    borderRadius: 8,
    borderWidth: 1,
    height: 30,
    justifyContent: "center",
    width: 34,
  },
  fontValue: {
    color: light.text,
    fontSize: 12.5,
    fontWeight: "700",
    minWidth: 42,
    textAlign: "center",
  },
  translateButton: {
    alignItems: "center",
    alignSelf: "flex-start",
    flexDirection: "row",
    gap: 7,
    marginTop: 16,
  },
  translateButtonText: {
    color: light.accent,
    fontSize: 12,
    fontWeight: "700",
  },
  pageControls: {
    flexDirection: "row",
    gap: 10,
    justifyContent: "space-between",
    paddingTop: 24,
  },
  pageButton: {
    alignItems: "center",
    borderColor: t.hair,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 6,
    justifyContent: "center",
    minHeight: 42,
    paddingHorizontal: 14,
  },
  disabledPage: {
    opacity: 0.45,
  },
  pageButtonText: {
    color: t.text,
    fontSize: 12,
    fontWeight: "700",
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
