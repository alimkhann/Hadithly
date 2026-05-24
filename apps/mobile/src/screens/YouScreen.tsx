import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import { Bookmark, ChevronRight, Crown, Languages, LogIn, Settings, SlidersHorizontal } from "lucide-react-native";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Card, IconButton, ProgressBar, Row } from "@/components/Prototype";
import { Logo } from "@/components/Logo";
import { configurePurchases } from "@/lib/purchases";

const t = themes.light;
const go = (href: string) => router.push(href as never);

export function YouScreen() {
  return (
    <SafeAreaView edges={["top"]} style={styles.safe}>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.header}>
          <Text style={styles.title}>You</Text>
          <IconButton onPress={() => go("/settings")} size={34}><SlidersHorizontal color={t.text} size={17} /></IconButton>
        </View>

        <Card padding={16} style={styles.profile}>
          <Logo size={48} />
          <View style={styles.profileCopy}>
            <Text style={styles.profileName}>Guest reader</Text>
            <Text style={styles.profileMeta}>Russian · 38 approved · 91% avg</Text>
          </View>
          <Text style={styles.proBadge}>Free</Text>
        </Card>

        <Card padding={14} style={styles.proCard}>
          <View style={styles.proTop}>
            <View>
              <Text style={styles.proTitle}>Hadithly Pro</Text>
              <Text style={styles.proMeta}>20 / 20 AI translations used</Text>
            </View>
            <Crown color={t.gold} size={22} />
          </View>
          <ProgressBar height={5} value={100} />
          <Pressable onPress={() => configurePurchases()}><Text style={styles.upgrade}>Upgrade for 500 monthly generations</Text></Pressable>
        </Card>

        <Card padding={0} style={styles.actionCard}>
          <Row leading={<LogIn color={t.text} size={20} />} subtitle="Email, Apple, or Google when configured" title="Sign in with Clerk" />
          <Row leading={<Languages color={t.accent} size={20} />} subtitle="Russian · Change anytime" title="Preferred language" />
          <Row leading={<Bookmark color={t.gold} size={20} />} subtitle="24 saved" title="Bookmarks, favorites, notes" />
          <Row last leading={<Settings color={t.text} size={20} />} onPress={() => go("/settings")} subtitle="Theme, Arabic size, translation size" title="Reader settings" trailing={<ChevronRight color={t.textTer} size={16} />} />
        </Card>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { backgroundColor: t.bg, flex: 1 },
  content: { paddingBottom: 110, paddingHorizontal: 20, paddingTop: 8 },
  header: { alignItems: "center", flexDirection: "row", justifyContent: "space-between", marginTop: 4 },
  title: { color: t.text, fontSize: 28, fontWeight: "700", letterSpacing: -0.5 },
  profile: { alignItems: "center", flexDirection: "row", gap: 14, marginTop: 16 },
  profileCopy: { flex: 1 },
  profileName: { color: t.text, fontSize: 17, fontWeight: "700" },
  profileMeta: { color: t.textSec, fontSize: 12.5, marginTop: 3 },
  proBadge: { color: t.textTer, fontSize: 11.5, fontWeight: "700" },
  proCard: { marginTop: 12 },
  proTop: { alignItems: "center", flexDirection: "row", justifyContent: "space-between", marginBottom: 10 },
  proTitle: { color: t.text, fontSize: 15, fontWeight: "700" },
  proMeta: { color: t.textSec, fontSize: 12, marginTop: 2 },
  upgrade: { color: t.accent, fontSize: 12.5, fontWeight: "700", marginTop: 10 },
  actionCard: { marginTop: 18, paddingHorizontal: 14 }
});
