import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import { ChevronDown, Sparkles } from "lucide-react-native";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import {
  Button,
  Card,
  ProgressBar,
  SectionHeader,
  StatCard,
} from "@/components/Prototype";

const t = themes.light;
const go = (href: string) => router.push(href as never);

export function CommunityScreen() {
  return (
    <SafeAreaView edges={["top"]} style={styles.safe}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <Text style={styles.title}>Community</Text>
        <Text style={styles.subtitle}>Help bring hadith to more languages</Text>

        <Card padding={16} style={styles.languageCard}>
          <View style={styles.languageHeader}>
            <View style={styles.languageLeft}>
              <Text style={styles.flag}>RU</Text>
              <View>
                <Text style={styles.languageName}>Russian</Text>
                <Text style={styles.languageSub}>Translation progress</Text>
              </View>
            </View>
            <ChevronDown color={t.textTer} size={16} />
          </View>
          <ProgressBar height={8} value={0} />
          <View style={styles.legendGrid}>
            <Legend color={t.gold} label="Community pending data" />
            <Legend color={t.accent} label="AI cache pending data" />
            <Legend color="#D97706" label="Review queue pending" />
            <Legend color={`${t.textTer}88`} label="Coverage job not run" />
          </View>
        </Card>

        <View style={styles.section}>
          <SectionHeader>Leaderboard · Russian</SectionHeader>
          <Text style={styles.emptyText}>
            Leaderboards will appear after real approved translation data
            exists.
          </Text>
        </View>

        <View style={styles.section}>
          <SectionHeader>My contributions · Russian</SectionHeader>
          <View style={styles.stats}>
            <StatCard label="Approved" value="0" />
            <StatCard label="Pending" value="0" />
            <StatCard label="Avg rating" value="-" />
          </View>
        </View>

        <Pressable onPress={() => go("/submit-translation")}>
          <Button block icon={<Sparkles color="#FFFFFF" size={16} />}>
            Submit a translation
          </Button>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <View style={styles.legend}>
      <View style={[styles.legendDot, { backgroundColor: color }]} />
      <Text style={styles.legendText}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safe: { backgroundColor: t.bg, flex: 1 },
  content: { paddingBottom: 110, paddingHorizontal: 20, paddingTop: 8 },
  title: {
    color: t.text,
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.5,
    marginTop: 4,
  },
  subtitle: { color: t.textSec, fontSize: 13.5, marginTop: 4 },
  languageCard: { marginTop: 16 },
  languageHeader: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
    marginBottom: 13,
  },
  languageLeft: { alignItems: "center", flexDirection: "row", gap: 10 },
  flag: { color: t.text, fontSize: 16, fontWeight: "800" },
  languageName: { color: t.text, fontSize: 15, fontWeight: "700" },
  languageSub: { color: t.textSec, fontSize: 11.5 },
  legendGrid: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 11 },
  legend: { alignItems: "center", flexDirection: "row", gap: 5, width: "47%" },
  legendDot: { borderRadius: 4, height: 7, width: 7 },
  legendText: { color: t.text, fontSize: 11.5 },
  section: { marginTop: 22 },
  stats: { flexDirection: "row", gap: 8, marginBottom: 24 },
  emptyText: { color: t.textSec, fontSize: 12.5, lineHeight: 18 },
});
