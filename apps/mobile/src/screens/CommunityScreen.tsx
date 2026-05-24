import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import { ChevronDown, Sparkles, Star } from "lucide-react-native";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button, Card, ProgressBar, Row, SectionHeader, Segmented, StatCard } from "@/components/Prototype";

const t = themes.light;
const go = (href: string) => router.push(href as never);

export function CommunityScreen() {
  return (
    <SafeAreaView edges={["top"]} style={styles.safe}>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
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
          <ProgressBar height={8} segments={[
            { value: 4, color: t.gold },
            { value: 26, color: t.accent },
            { value: 6, color: "#D97706" },
            { value: 64, color: `${t.textTer}55` }
          ]} />
          <View style={styles.legendGrid}>
            <Legend color={t.gold} label="Community 4%" />
            <Legend color={t.accent} label="AI cached 26%" />
            <Legend color="#D97706" label="Needs review 6%" />
            <Legend color={`${t.textTer}88`} label="Missing 64%" />
          </View>
        </Card>

        <View style={styles.section}>
          <SectionHeader right={<Segmented options={["Monthly", "All time"]} value="Monthly" />}>Leaderboard · Russian</SectionHeader>
          {[
            ["1", "Aigerim N.", "124 approved · 96% avg", t.gold],
            ["2", "Ruslan K.", "98 approved · 92% avg", "#9CA3AF"],
            ["3", "Aliya S.", "74 approved · 94% avg", "#B8893B"],
            ["4", "You", "38 approved · 91% avg", t.accent],
            ["5", "Damir T.", "26 approved · 89% avg", t.textTer]
          ].map(([rank, name, stats, color], index) => (
            <Row
              key={name}
              leading={<View style={styles.rankRow}><Text style={styles.rank}>{rank}</Text><View style={[styles.avatar, { backgroundColor: color }]}><Text style={styles.avatarText}>{String(name).slice(0, 1)}</Text></View></View>}
              title={<Text style={[styles.rowTitle, name === "You" && styles.you]}>{name}</Text>}
              subtitle={stats}
              trailing={index < 3 ? <Star color={String(color)} size={15} /> : undefined}
            />
          ))}
        </View>

        <View style={styles.section}>
          <SectionHeader>My contributions · Russian</SectionHeader>
          <View style={styles.stats}>
            <StatCard label="Approved" value="38" />
            <StatCard label="Pending" value="7" />
            <StatCard label="Avg rating" value="91%" />
          </View>
        </View>

        <Pressable onPress={() => go("/submit-translation")}>
          <Button block icon={<Sparkles color="#FFFFFF" size={16} />}>Submit a translation</Button>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <View style={styles.legend}><View style={[styles.legendDot, { backgroundColor: color }]} /><Text style={styles.legendText}>{label}</Text></View>
  );
}

const styles = StyleSheet.create({
  safe: { backgroundColor: t.bg, flex: 1 },
  content: { paddingBottom: 110, paddingHorizontal: 20, paddingTop: 8 },
  title: { color: t.text, fontSize: 28, fontWeight: "700", letterSpacing: -0.5, marginTop: 4 },
  subtitle: { color: t.textSec, fontSize: 13.5, marginTop: 4 },
  languageCard: { marginTop: 16 },
  languageHeader: { alignItems: "center", flexDirection: "row", justifyContent: "space-between", marginBottom: 13 },
  languageLeft: { alignItems: "center", flexDirection: "row", gap: 10 },
  flag: { color: t.text, fontSize: 16, fontWeight: "800" },
  languageName: { color: t.text, fontSize: 15, fontWeight: "700" },
  languageSub: { color: t.textSec, fontSize: 11.5 },
  legendGrid: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 11 },
  legend: { alignItems: "center", flexDirection: "row", gap: 5, width: "47%" },
  legendDot: { borderRadius: 4, height: 7, width: 7 },
  legendText: { color: t.text, fontSize: 11.5 },
  section: { marginTop: 22 },
  rankRow: { alignItems: "center", flexDirection: "row", gap: 11 },
  rank: { color: t.textSec, fontSize: 13, fontWeight: "700", width: 18 },
  avatar: { alignItems: "center", borderRadius: 16, height: 32, justifyContent: "center", width: 32 },
  avatarText: { color: "#FFFFFF", fontSize: 13, fontWeight: "800" },
  rowTitle: { color: t.text, fontSize: 14.5, fontWeight: "600" },
  you: { color: t.accent, fontWeight: "800" },
  stats: { flexDirection: "row", gap: 8, marginBottom: 24 }
});
