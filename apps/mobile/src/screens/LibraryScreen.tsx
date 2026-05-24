import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import { Filter } from "lucide-react-native";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Chip, IconButton, ProgressBar } from "@/components/Prototype";
import { toCollectionCard, useBooks } from "@/lib/hadith";

const t = themes.light;
const go = (href: string) => router.push(href as never);

export function LibraryScreen() {
  const { books } = useBooks();
  const collections = books.map(toCollectionCard);

  return (
    <SafeAreaView edges={["top"]} style={styles.safe}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.header}>
          <Text style={styles.title}>Library</Text>
          <IconButton size={34}>
            <Filter color={t.text} size={17} />
          </IconButton>
        </View>
        <ScrollView
          contentContainerStyle={styles.filters}
          horizontal
          showsHorizontalScrollIndicator={false}
        >
          {[
            "All",
            "Sahih",
            "Sunan",
            "Popular",
            "My language",
            "Downloaded",
          ].map((filter, index) => (
            <Chip key={filter} variant={index === 0 ? "primary" : "secondary"}>
              {filter}
            </Chip>
          ))}
        </ScrollView>
        {collections.map((collection) => (
          <Pressable
            key={collection.slug}
            onPress={() => go(`/collection/${collection.slug}`)}
            style={styles.collection}
          >
            <View style={styles.bookTile}>
              <Text style={styles.bookTileText}>
                {collection.grade.toUpperCase()}
              </Text>
            </View>
            <View style={styles.copy}>
              <Text style={styles.collectionTitle}>{collection.title}</Text>
              <Text style={styles.arabic}>{collection.arabic}</Text>
              <Text style={styles.meta}>
                {collection.count.toLocaleString()} hadith ·{" "}
                {collection.coverage}% RU
              </Text>
              <View style={styles.progress}>
                <ProgressBar height={2.5} value={collection.coverage} />
              </View>
            </View>
            <Text style={styles.chevron}>›</Text>
          </Pressable>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { backgroundColor: t.bg, flex: 1 },
  content: { paddingBottom: 110, paddingHorizontal: 20, paddingTop: 10 },
  header: {
    alignItems: "flex-end",
    flexDirection: "row",
    justifyContent: "space-between",
    marginBottom: 14,
    marginTop: 4,
  },
  title: {
    color: t.text,
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.5,
  },
  filters: { gap: 7, paddingBottom: 12 },
  collection: {
    alignItems: "center",
    borderBottomColor: t.hair,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 13,
    paddingVertical: 14,
  },
  bookTile: {
    alignItems: "flex-start",
    backgroundColor: t.accent,
    borderRadius: 5,
    height: 54,
    justifyContent: "flex-end",
    padding: 6,
    width: 42,
  },
  bookTileText: {
    color: "#FFFFFF",
    fontSize: 9,
    fontWeight: "800",
    letterSpacing: 0.4,
  },
  copy: { flex: 1, minWidth: 0 },
  collectionTitle: { color: t.text, fontSize: 15, fontWeight: "700" },
  arabic: {
    color: t.textSec,
    fontSize: 13,
    marginTop: 1,
    textAlign: "right",
    writingDirection: "rtl",
  },
  meta: { color: t.textTer, fontSize: 11.5, marginTop: 5 },
  progress: { marginTop: 5, width: 130 },
  chevron: { color: t.textTer, fontSize: 26, fontWeight: "300" },
});
