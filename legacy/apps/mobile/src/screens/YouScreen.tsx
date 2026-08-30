import { useAuth, useUser } from "@clerk/expo";
import { themes } from "@hadithly/design-tokens";
import { useQuery } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { router } from "expo-router";
import {
  Bookmark,
  ChevronRight,
  Crown,
  Languages,
  LogIn,
  Settings,
  SlidersHorizontal,
} from "lucide-react-native";
import { useEffect } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Card, IconButton, ProgressBar, Row } from "@/components/Prototype";
import { Logo } from "@/components/Logo";
import { useAuthRuntime } from "@/lib/auth-runtime";
import { useOnboardingState } from "@/lib/onboarding";
import { configurePurchases } from "@/lib/purchases";

const t = themes.light;
const go = (href: string) => router.push(href as never);

type ConvexUser = {
  aiGenerationsThisMonth: number;
  aiGenerationLimit: number;
  subscriptionTier: "guest" | "free" | "trial" | "pro";
} | null;

const getByClerkId = makeFunctionReference<
  "query",
  { clerkId: string },
  ConvexUser
>("users:getByClerkId");

export function YouScreen() {
  const { clerkEnabled } = useAuthRuntime();
  if (clerkEnabled) return <SignedInAwareYouScreen />;
  return <YouContent signedIn={false} />;
}

function SignedInAwareYouScreen() {
  const { isSignedIn } = useAuth();
  const { user } = useUser();
  const { convexEnabled } = useAuthRuntime();
  const signedIn = Boolean(isSignedIn);
  const avatarName =
    user?.fullName ?? user?.username ?? user?.primaryEmailAddress?.emailAddress;

  if (convexEnabled && signedIn && user?.id) {
    return <YouContentWithQuota avatarName={avatarName} userId={user.id} />;
  }
  return (
    <YouContent avatarName={avatarName} signedIn={signedIn} userId={user?.id} />
  );
}

function YouContentWithQuota({
  avatarName,
  userId,
}: {
  avatarName?: string | null;
  userId: string;
}) {
  const profile = useQuery(getByClerkId, { clerkId: userId });

  useEffect(() => {
    configurePurchases(userId);
  }, [userId]);

  return (
    <YouContent
      avatarName={avatarName}
      signedIn
      userId={userId}
      quotaUsed={profile?.aiGenerationsThisMonth}
      quotaLimit={profile?.aiGenerationLimit}
      tier={profile?.subscriptionTier}
    />
  );
}

function YouContent({
  avatarName,
  signedIn,
  userId,
  quotaUsed,
  quotaLimit,
  tier,
}: {
  avatarName?: string | null;
  signedIn: boolean;
  userId?: string;
  quotaUsed?: number;
  quotaLimit?: number;
  tier?: "guest" | "free" | "trial" | "pro";
}) {
  const { state } = useOnboardingState();
  const isPro = tier === "pro";
  const resolvedUsed = quotaUsed ?? 0;
  const resolvedLimit = quotaLimit ?? (signedIn ? 20 : 0);
  const quotaProgress = resolvedLimit
    ? Math.min(100, Math.round((resolvedUsed / resolvedLimit) * 100))
    : 0;
  const tierLabel = !signedIn
    ? "Guest"
    : isPro
      ? "Pro"
      : tier === "trial"
        ? "Trial"
        : "Free";

  return (
    <SafeAreaView edges={["top"]} style={styles.safe}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.header}>
          <Text style={styles.title}>You</Text>
          <IconButton onPress={() => go("/settings")} size={34}>
            <SlidersHorizontal color={t.text} size={17} />
          </IconButton>
        </View>

        <Card padding={16} style={styles.profile}>
          <Logo size={48} />
          <View style={styles.profileCopy}>
            <Text style={styles.profileName}>
              {avatarName ?? "Guest reader"}
            </Text>
            <Text style={styles.profileMeta}>
              {state.preferredLanguage.toUpperCase()} ·{" "}
              {signedIn ? "Synced with Clerk" : "Local guest profile"}
            </Text>
          </View>
          <Text style={[styles.proBadge, isPro && styles.proBadgeActive]}>
            {tierLabel}
          </Text>
        </Card>

        <Card padding={14} style={styles.proCard}>
          <View style={styles.proTop}>
            <View>
              <Text style={styles.proTitle}>Hadithly Pro</Text>
              <Text style={styles.proMeta}>
                {signedIn
                  ? `${resolvedUsed} / ${resolvedLimit} AI translations used`
                  : "Sign in to generate AI translations"}
              </Text>
            </View>
            <Crown color={t.gold} size={22} />
          </View>
          <ProgressBar height={5} value={quotaProgress} />
          {isPro ? (
            <Text style={styles.proActive}>
              You have Pro — 500 generations every month.
            </Text>
          ) : (
            <Pressable onPress={() => go("/paywall/soft")}>
              <Text style={styles.upgrade}>
                Upgrade for 500 monthly generations
              </Text>
            </Pressable>
          )}
        </Card>

        <Card padding={0} style={styles.actionCard}>
          <Row
            leading={<LogIn color={t.text} size={20} />}
            onPress={() => go("/onboarding/auth")}
            subtitle={signedIn ? "Signed in" : "Email, Apple, or Google"}
            title={signedIn ? "Account" : "Sign in with Clerk"}
          />
          <Row
            leading={<Languages color={t.accent} size={20} />}
            subtitle={`${state.preferredLanguage.toUpperCase()} · Change from onboarding/settings`}
            title="Preferred language"
          />
          <Row
            leading={<Bookmark color={t.gold} size={20} />}
            subtitle="Synced after sign-in"
            title="Bookmarks, favorites, notes"
          />
          <Row
            last
            leading={<Settings color={t.text} size={20} />}
            onPress={() => go("/settings")}
            subtitle="Theme, Arabic size, translation size"
            title="Reader settings"
            trailing={<ChevronRight color={t.textTer} size={16} />}
          />
        </Card>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { backgroundColor: t.bg, flex: 1 },
  content: { paddingBottom: 110, paddingHorizontal: 20, paddingTop: 8 },
  header: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
    marginTop: 4,
  },
  title: {
    color: t.text,
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.5,
  },
  profile: {
    alignItems: "center",
    flexDirection: "row",
    gap: 14,
    marginTop: 16,
  },
  profileCopy: { flex: 1 },
  profileName: { color: t.text, fontSize: 17, fontWeight: "700" },
  profileMeta: { color: t.textSec, fontSize: 12.5, marginTop: 3 },
  proBadge: { color: t.textTer, fontSize: 11.5, fontWeight: "700" },
  proBadgeActive: { color: t.accent },
  proCard: { marginTop: 12 },
  proTop: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
    marginBottom: 10,
  },
  proTitle: { color: t.text, fontSize: 15, fontWeight: "700" },
  proMeta: { color: t.textSec, fontSize: 12, marginTop: 2 },
  upgrade: {
    color: t.accent,
    fontSize: 12.5,
    fontWeight: "700",
    marginTop: 10,
  },
  proActive: { color: t.textSec, fontSize: 12, marginTop: 10 },
  actionCard: { marginTop: 18, paddingHorizontal: 14 },
});
