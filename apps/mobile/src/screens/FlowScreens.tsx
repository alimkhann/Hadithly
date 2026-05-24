import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import { ArrowRight, Check, ChevronLeft, Info, Mail, Sparkles, X } from "lucide-react-native";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Button, Card, Chip, IconButton, ProgressBar, Row, Switch } from "@/components/Prototype";
import { Logo } from "@/components/Logo";
import { dailyHadith, languages } from "@/data/sample";

const t = themes.light;
const go = (href: string, replace = false) => (replace ? router.replace(href as never) : router.push(href as never));

export function SplashPrototypeScreen() {
  return (
    <SafeAreaView style={styles.splash}>
      <View style={styles.splashHalo} />
      <Logo size={88} />
      <Text style={styles.splashTitle}>Hadithly</Text>
      <Text style={styles.splashArabic}>حَدِيْثلِيْ</Text>
      <View style={styles.splashLine} />
      <Text style={styles.splashTag}>Read the words that lit a world</Text>
    </SafeAreaView>
  );
}

export function WelcomeScreen() {
  return (
    <FlowShell>
      <Logo size={36} />
      <Text style={styles.heroTitle}>Read hadith{"\n"}in your language.</Text>
      <Text style={styles.lede}>Arabic and English source text, with translations generated on the spot when missing and improved over time by the community.</Text>
      <Card padding={20} style={styles.reminder}>
        <Text style={styles.reminderLabel}>A reminder</Text>
        <Text style={styles.reminderArabic}>طَلَبُ الْعِلْمِ فَرِيضَةٌ عَلَى كُلِّ مُسْلِمٍ</Text>
        <Text style={styles.reminderText}>"The seeking of knowledge is an obligation upon every Muslim."</Text>
        <Text style={styles.muted}>- Ibn Majah 224</Text>
      </Card>
      <View style={styles.flex} />
      <Button block iconRight={<ArrowRight color="#FFFFFF" size={16} />} onPress={() => go("/onboarding/language")}>Begin</Button>
      <Text style={styles.terms}>By continuing you agree to our Terms and Privacy.</Text>
    </FlowShell>
  );
}

export function LanguageScreen() {
  return (
    <FlowShell step="1/3" progress={33}>
      <Text style={styles.stepTitle}>Choose your{"\n"}reading language</Text>
      <Text style={styles.lede}>Hadithly shows coverage per language. Missing translations are generated automatically.</Text>
      <ScrollView contentContainerStyle={styles.languageList} showsVerticalScrollIndicator={false}>
        {languages.map((language) => {
          const selected = language.code === "ru";
          return (
            <View key={language.code} style={[styles.languageRow, selected && styles.selectedLanguage]}>
              <Text style={styles.flag}>{language.flag}</Text>
              <View style={styles.languageCopy}>
                <View style={styles.languageTitleRow}>
                  <Text style={styles.languageTitle}>{language.title}</Text>
                  <Text style={styles.languageNative}>{language.native}</Text>
                </View>
                <Text style={styles.languageMeta}>
                  {language.status === "community" ? `${language.coverage}% community · AI on demand` : language.status}
                </Text>
              </View>
              <View style={[styles.radio, selected && styles.radioSelected]}>{selected ? <Check color="#FFFFFF" size={13} strokeWidth={2.6} /> : null}</View>
            </View>
          );
        })}
      </ScrollView>
      <Button block iconRight={<ArrowRight color="#FFFFFF" size={15} />} onPress={() => go("/onboarding/notifications")}>Continue</Button>
    </FlowShell>
  );
}

export function NotificationSetupScreen() {
  return (
    <FlowShell step="2/3" progress={66}>
      <Text style={styles.stepTitle}>A hadith,{"\n"}every morning.</Text>
      <Text style={styles.lede}>One short hadith delivered at a time you choose, in the language you read.</Text>
      <Card padding={14} style={styles.pushPreview}>
        <View style={styles.appIcon}><Logo size={22} /></View>
        <View style={styles.pushCopy}>
          <View style={styles.pushTop}><Text style={styles.pushApp}>Hadithly</Text><Text style={styles.muted}>now</Text></View>
          <Text style={styles.pushTitle}>Today's hadith - 1:1</Text>
          <Text style={styles.pushBody}>Actions are but by intention, and every man shall have only that which he intended...</Text>
        </View>
      </Card>
      <Card padding={4} style={styles.settingsCard}>
        <Row last={false} subtitle="One short hadith each morning" title="Daily hadith" trailing={<Switch />} />
        <Row last={false} subtitle="07:30 - local" title="Time" />
        <Row last subtitle="Russian" title="Notification language" />
      </Card>
      <View style={styles.flex} />
      <Button block onPress={() => go("/onboarding/preview")}>Allow notifications</Button>
      <Button block onPress={() => go("/onboarding/preview")} variant="ghost">Not now</Button>
    </FlowShell>
  );
}

export function PreviewScreen() {
  return (
    <FlowShell step="3/3" progress={100}>
      <Text style={styles.stepTitle}>The same hadith,{"\n"}in your language.</Text>
      <Text style={styles.lede}>When a translation is missing, AI generates one instantly. The community improves it over time.</Text>
      <Card padding={16} style={styles.previewCard}>
        <View style={styles.metaRow}>
          <Text style={styles.ref}>1:1</Text>
          <Chip variant="outline">Sahih</Chip>
          <Chip variant="soft"><Text style={styles.softChipText}>AI</Text></Chip>
          <Text style={styles.muted}>New</Text>
        </View>
        <Text style={styles.previewArabic}>إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ</Text>
        <Text style={styles.previewEnglish}>Actions are but by intention, and every man shall have only that which he intended.</Text>
        <View style={styles.divider} />
        <Chip variant="soft"><Text style={styles.softChipText}>Russian · just now</Text></Chip>
        <Text style={styles.previewRussian}>Поистине, дела оцениваются по намерениям, и каждому достанется лишь то, что он намеревался обрести.</Text>
      </Card>
      <View style={styles.flex} />
      <Button block iconRight={<ArrowRight color="#FFFFFF" size={15} />} onPress={() => go("/onboarding/auth")}>Show me the reader</Button>
    </FlowShell>
  );
}

export function AuthScreen() {
  return (
    <FlowShell>
      <Logo size={32} />
      <Text style={styles.stepTitle}>Sign in to sync</Text>
      <Text style={styles.lede}>Keep notes, bookmarks, and contributions across devices. Or continue as a guest.</Text>
      <View style={styles.authStack}>
        <Button block style={styles.appleButton}>Continue with Apple</Button>
        <Button block icon={<Sparkles color={t.text} size={18} />} variant="outline">Continue with Google</Button>
        <Button block icon={<Mail color={t.text} size={18} />} variant="outline">Continue with email</Button>
      </View>
      <View style={styles.orRow}><View style={styles.dividerFlex} /><Text style={styles.or}>OR</Text><View style={styles.dividerFlex} /></View>
      <Button block onPress={() => go("/home", true)} variant="ghost">Continue as guest</Button>
      <View style={styles.flex} />
      <Text style={styles.terms}>Your reading is yours. We do not share notes, bookmarks, or vote activity.</Text>
    </FlowShell>
  );
}

export function SoftPaywallScreen() {
  return <Paywall kind="soft" />;
}

export function QuotaPaywallScreen() {
  return <Paywall kind="quota" />;
}

function Paywall({ kind }: { kind: "soft" | "quota" }) {
  return (
    <FlowShell>
      <View style={styles.closeRow}><IconButton onPress={() => router.back()} size={32}><X color={t.text} size={16} /></IconButton></View>
      {kind === "quota" ? (
        <Card padding={16}>
          <View style={styles.infoRow}><Info color="#D97706" size={16} /><Text style={styles.infoTitle}>20 / 20 AI translations used this month</Text></View>
          <ProgressBar height={5} value={100} />
          <Text style={styles.mutedBlock}>Resets June 1. Already-translated hadiths remain free to view, always.</Text>
        </Card>
      ) : (
        <View style={styles.paywallIcon}><Logo size={36} /></View>
      )}
      <Text style={styles.paywallTitle}>{kind === "quota" ? "Continue translating\nwith AI" : "Bring hadith to\nevery language"}</Text>
      <Text style={styles.lede}>Pro funds AI translations and helps the community improve them.</Text>
      <View style={styles.benefits}>
        {["500 AI translations / month", "Priority translation queue", "Offline language packs", "Advanced contribution tools"].map((label) => (
          <View key={label} style={styles.benefit}><Check color={t.accent} size={18} strokeWidth={2.5} /><Text style={styles.benefitText}>{label}</Text></View>
        ))}
      </View>
      <View style={styles.planRow}>
        <Card padding={14} style={styles.planCard}><Text style={styles.muted}>Monthly</Text><Text style={styles.planPrice}>$3.99</Text><Text style={styles.muted}>per month</Text></Card>
        <Card padding={14} style={[styles.planCard, styles.planActive]}><Text style={styles.planAccent}>Annual</Text><Text style={styles.planPrice}>$29.99</Text><Text style={styles.muted}>$2.50 / month</Text></Card>
      </View>
      <View style={styles.flex} />
      <Button block>Start 3-day free trial</Button>
      <Button block onPress={() => go("/home", true)} variant="ghost">Continue free</Button>
    </FlowShell>
  );
}

function FlowShell({ children, step, progress }: { children: React.ReactNode; step?: string; progress?: number }) {
  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.flow}>
        {step ? (
          <View style={styles.progressHeader}>
            <IconButton onPress={() => router.back()} size={32}><ChevronLeft color={t.text} size={18} /></IconButton>
            <View style={styles.progress}><ProgressBar value={progress} height={4} /></View>
            <Text style={styles.step}>{step}</Text>
          </View>
        ) : null}
        {children}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { backgroundColor: t.bg, flex: 1 },
  flow: { flex: 1, padding: 24 },
  splash: { alignItems: "center", backgroundColor: t.bg, flex: 1, justifyContent: "center" },
  splashHalo: { backgroundColor: t.accentSoft, borderRadius: 120, height: 240, opacity: 0.75, position: "absolute", top: "25%", width: 240 },
  splashTitle: { color: t.text, fontSize: 38, fontWeight: "700", letterSpacing: -0.5, marginTop: 18 },
  splashArabic: { color: t.textSec, fontSize: 18, marginTop: -7, writingDirection: "rtl" },
  splashLine: { backgroundColor: t.hair, height: 1, marginTop: 96, width: 60 },
  splashTag: { color: t.textTer, fontSize: 12, fontWeight: "600", letterSpacing: 0.8, marginTop: 28, textTransform: "uppercase" },
  heroTitle: { color: t.text, fontSize: 38, fontWeight: "700", letterSpacing: -0.8, lineHeight: 40, marginTop: 30 },
  stepTitle: { color: t.text, fontSize: 28, fontWeight: "700", letterSpacing: -0.5, lineHeight: 31, marginTop: 8 },
  lede: { color: t.textSec, fontSize: 14.5, lineHeight: 22, marginTop: 10 },
  reminder: { marginTop: 28 },
  reminderLabel: { alignSelf: "flex-start", backgroundColor: t.bg, color: t.textTer, fontSize: 10, fontWeight: "700", letterSpacing: 0.7, marginTop: -28, paddingHorizontal: 8, textTransform: "uppercase" },
  reminderArabic: { color: t.text, fontSize: 20, lineHeight: 37, marginTop: 10, textAlign: "right", writingDirection: "rtl" },
  reminderText: { color: t.textSec, fontFamily: "Georgia", fontSize: 14.5, lineHeight: 23, marginTop: 10 },
  muted: { color: t.textTer, fontSize: 11.5 },
  terms: { color: t.textTer, fontSize: 11.5, lineHeight: 17, marginTop: 12, textAlign: "center" },
  flex: { flex: 1 },
  progressHeader: { alignItems: "center", flexDirection: "row", gap: 10, marginBottom: 22 },
  progress: { flex: 1 },
  step: { color: t.textSec, fontSize: 12, fontWeight: "600" },
  languageList: { gap: 2, paddingVertical: 18 },
  languageRow: { alignItems: "center", borderColor: "transparent", borderRadius: 7, borderWidth: 1, flexDirection: "row", gap: 12, paddingHorizontal: 14, paddingVertical: 12 },
  selectedLanguage: { backgroundColor: "#EFFBF4", borderColor: t.accent },
  flag: { color: t.text, fontSize: 13, fontWeight: "800", width: 24 },
  languageCopy: { flex: 1 },
  languageTitleRow: { alignItems: "baseline", flexDirection: "row", gap: 8 },
  languageTitle: { color: t.text, fontSize: 15.5, fontWeight: "700" },
  languageNative: { color: t.textSec, fontSize: 13 },
  languageMeta: { color: t.textSec, fontSize: 11.5, marginTop: 4 },
  radio: { alignItems: "center", borderColor: t.hair, borderRadius: 11, borderWidth: 1.5, height: 22, justifyContent: "center", width: 22 },
  radioSelected: { backgroundColor: t.accent, borderColor: t.accent },
  pushPreview: { alignItems: "flex-start", flexDirection: "row", gap: 11, marginTop: 22 },
  appIcon: { alignItems: "center", backgroundColor: t.text, borderRadius: 9, height: 38, justifyContent: "center", width: 38 },
  pushCopy: { flex: 1 },
  pushTop: { flexDirection: "row", justifyContent: "space-between" },
  pushApp: { color: t.text, fontSize: 13, fontWeight: "700" },
  pushTitle: { color: t.text, fontSize: 13.5, fontWeight: "600", marginTop: 2 },
  pushBody: { color: t.textSec, fontSize: 12.5, lineHeight: 18, marginTop: 1 },
  settingsCard: { marginTop: 22, paddingHorizontal: 16 },
  previewCard: { marginTop: 16 },
  metaRow: { alignItems: "center", flexDirection: "row", flexWrap: "wrap", gap: 6, marginBottom: 10 },
  ref: { color: t.textTer, fontSize: 10.5, fontWeight: "600" },
  softChipText: { color: t.accentText, fontSize: 10.5, fontWeight: "700" },
  previewArabic: { color: t.text, fontSize: 21, lineHeight: 42, textAlign: "right", writingDirection: "rtl" },
  previewEnglish: { color: t.text, fontFamily: "Georgia", fontSize: 14, lineHeight: 23, marginTop: 10 },
  divider: { backgroundColor: t.hair, height: StyleSheet.hairlineWidth, marginVertical: 12 },
  previewRussian: { color: t.textSec, fontFamily: "Georgia", fontSize: 14, fontStyle: "italic", lineHeight: 23, marginTop: 10 },
  authStack: { gap: 10, marginTop: 32 },
  appleButton: { backgroundColor: "#000000" },
  orRow: { alignItems: "center", flexDirection: "row", gap: 10, marginVertical: 24 },
  dividerFlex: { backgroundColor: t.hair, flex: 1, height: StyleSheet.hairlineWidth },
  or: { color: t.textTer, fontSize: 10.5, fontWeight: "700", letterSpacing: 0.8 },
  closeRow: { alignItems: "flex-end" },
  paywallIcon: { alignItems: "center", alignSelf: "center", backgroundColor: t.accent, borderRadius: 14, height: 60, justifyContent: "center", marginTop: 12, width: 60 },
  paywallTitle: { color: t.text, fontSize: 28, fontWeight: "700", letterSpacing: -0.7, lineHeight: 31, marginTop: 18, textAlign: "center" },
  benefits: { gap: 11, marginTop: 22 },
  benefit: { alignItems: "center", flexDirection: "row", gap: 12 },
  benefitText: { color: t.text, fontSize: 14.5 },
  planRow: { flexDirection: "row", gap: 10, marginTop: 22 },
  planCard: { flex: 1 },
  planActive: { backgroundColor: "#EFFBF4", borderColor: t.accent },
  planAccent: { color: t.accent, fontSize: 11.5, fontWeight: "700" },
  planPrice: { color: t.text, fontSize: 22, fontWeight: "700", marginTop: 4 },
  infoRow: { alignItems: "center", flexDirection: "row", gap: 8, marginBottom: 8 },
  infoTitle: { color: t.text, fontSize: 13, fontWeight: "700" },
  mutedBlock: { color: t.textSec, fontSize: 12, lineHeight: 18, marginTop: 8 }
});
