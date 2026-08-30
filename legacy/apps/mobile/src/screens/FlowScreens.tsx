import { useSignIn, useSignUp, useClerk, useSSO, useUser } from "@clerk/expo";
import { themes } from "@hadithly/design-tokens";
import { router } from "expo-router";
import { useLocalSearchParams } from "expo-router";
import * as Linking from "expo-linking";
import {
  ArrowRight,
  BookOpen,
  Check,
  ChevronLeft,
  Info,
  Mail,
  RotateCcw,
  Sparkles,
  X,
} from "lucide-react-native";
import React from "react";
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import type { PurchasesPackage } from "react-native-purchases";
import { SafeAreaView } from "react-native-safe-area-context";

import {
  Button,
  Card,
  Chip,
  IconButton,
  ProgressBar,
  Row,
  Switch,
} from "@/components/Prototype";
import { Logo } from "@/components/Logo";
import { useAuthRuntime } from "@/lib/auth-runtime";
import { translateUi } from "@/lib/i18n";
import { registerDailyHadithNotifications } from "@/lib/notifications";
import { SUPPORTED_LANGUAGES, useOnboardingState } from "@/lib/onboarding";
import {
  configurePurchases,
  getCurrentOffering,
  purchasePackage,
  restorePurchases,
} from "@/lib/purchases";

const t = themes.light;
const go = (href: string, replace = false) =>
  replace ? router.replace(href as never) : router.push(href as never);

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
      <View style={styles.onboardingTop}>
        <Logo size={36} />
        <Text style={styles.heroTitle}>Read hadith{"\n"}in your language.</Text>
        <Text style={styles.lede}>
          Arabic and English source text, with translations generated on the
          spot when missing and improved over time by the community.
        </Text>
      </View>
      <OnboardingImageSlot
        caption="A calm, book-like reader"
        icon={<BookOpen color={t.accent} size={52} strokeWidth={1.4} />}
      />
      <View style={styles.onboardingBottom}>
        <Button
          block
          iconRight={<ArrowRight color="#FFFFFF" size={16} />}
          onPress={() => go("/onboarding/language")}
        >
          Begin
        </Button>
        <Text style={styles.terms}>
          By continuing you agree to our Terms and Privacy.
        </Text>
      </View>
    </FlowShell>
  );
}

function OnboardingImageSlot({
  caption,
  icon,
}: {
  caption?: string;
  icon: React.ReactNode;
}) {
  return (
    <View style={styles.imageSlotWrap}>
      <View style={styles.imageSlot}>
        <View style={styles.imageSlotTile}>{icon}</View>
        {caption ? <Text style={styles.imageCaption}>{caption}</Text> : null}
      </View>
    </View>
  );
}

export function LanguageScreen() {
  const { state, update } = useOnboardingState();
  return (
    <FlowShell step="1/3" progress={33}>
      <Text style={styles.stepTitle}>
        {translateUi(state.preferredLanguage, "readerLanguageTitle")}
      </Text>
      <Text style={styles.lede}>
        Hadithly shows coverage per language. Missing translations are generated
        automatically.
      </Text>
      <ScrollView
        contentContainerStyle={styles.languageList}
        showsVerticalScrollIndicator={false}
      >
        {SUPPORTED_LANGUAGES.map((language) => {
          const selected = language.code === state.preferredLanguage;
          return (
            <Pressable
              key={language.code}
              onPress={() => void update({ preferredLanguage: language.code })}
              style={[styles.languageRow, selected && styles.selectedLanguage]}
            >
              <Text style={styles.flag}>{language.code.toUpperCase()}</Text>
              <View style={styles.languageCopy}>
                <View style={styles.languageTitleRow}>
                  <Text style={styles.languageTitle}>{language.title}</Text>
                  <Text style={styles.languageNative}>{language.native}</Text>
                </View>
                <Text style={styles.languageMeta}>{language.status}</Text>
              </View>
              <View style={[styles.radio, selected && styles.radioSelected]}>
                {selected ? (
                  <Check color="#FFFFFF" size={13} strokeWidth={2.6} />
                ) : null}
              </View>
            </Pressable>
          );
        })}
      </ScrollView>
      <Button
        block
        iconRight={<ArrowRight color="#FFFFFF" size={15} />}
        onPress={() => go("/onboarding/notifications")}
      >
        {translateUi(state.preferredLanguage, "continue")}
      </Button>
    </FlowShell>
  );
}

export function NotificationSetupScreen() {
  const { state, update } = useOnboardingState();
  const handleAllow = async () => {
    const token = await registerDailyHadithNotifications();
    await update({ notificationsEnabled: Boolean(token) });
    go("/onboarding/preview");
  };

  return (
    <FlowShell step="2/3" progress={66}>
      <Text style={styles.stepTitle}>A hadith,{"\n"}every morning.</Text>
      <Text style={styles.lede}>
        One short hadith delivered at a time you choose, in the language you
        read.
      </Text>
      <Card padding={14} style={styles.pushPreview}>
        <View style={styles.appIcon}>
          <Logo size={22} />
        </View>
        <View style={styles.pushCopy}>
          <View style={styles.pushTop}>
            <Text style={styles.pushApp}>Hadithly</Text>
            <Text style={styles.muted}>now</Text>
          </View>
          <Text style={styles.pushTitle}>Today's hadith - 1:1</Text>
          <Text style={styles.pushBody}>
            Actions are but by intention, and every man shall have only that
            which he intended...
          </Text>
        </View>
      </Card>
      <Card padding={4} style={styles.settingsCard}>
        <Row
          last={false}
          subtitle="One short hadith each morning"
          title="Daily hadith"
          trailing={<Switch />}
        />
        <Row
          last={false}
          subtitle={`${state.notificationTime} - local`}
          title="Time"
        />
        <Row
          last
          subtitle={languageTitle(state.preferredLanguage)}
          title="Notification language"
        />
      </Card>
      <View style={styles.flex} />
      <Button block onPress={handleAllow}>
        Allow notifications
      </Button>
      <Button
        block
        onPress={() =>
          void update({ notificationsEnabled: false }).then(() =>
            go("/onboarding/preview"),
          )
        }
        variant="ghost"
      >
        Not now
      </Button>
    </FlowShell>
  );
}

export function PreviewScreen() {
  const { state } = useOnboardingState();
  const selectedLanguage = languageTitle(state.preferredLanguage);
  return (
    <FlowShell progress={100} step="3/3">
      <View style={styles.onboardingTop}>
        <Text style={styles.stepTitle}>
          The same hadith,{"\n"}in your language.
        </Text>
        <Text style={styles.lede}>
          When a translation is missing, AI generates one instantly — grounded
          in real sources and clearly labeled. The community improves it over
          time.
        </Text>
      </View>
      <OnboardingImageSlot
        caption={`${selectedLanguage} · AI on demand`}
        icon={<Sparkles color={t.accent} size={52} strokeWidth={1.4} />}
      />
      <View style={styles.onboardingBottom}>
        <Button
          block
          iconRight={<ArrowRight color="#FFFFFF" size={15} />}
          onPress={() => go("/onboarding/auth")}
        >
          Show me the reader
        </Button>
      </View>
    </FlowShell>
  );
}

export function AuthScreen() {
  const { clerkEnabled } = useAuthRuntime();
  const { state, update } = useOnboardingState();
  const finishGuest = async () => {
    await update({
      authMode: "guest",
      onboardingComplete: true,
      completedAt: Date.now(),
    });
    go("/home", true);
  };

  return (
    <FlowShell>
      <Logo size={32} />
      <Text style={styles.stepTitle}>
        {translateUi(state.preferredLanguage, "signInToSync")}
      </Text>
      <Text style={styles.lede}>
        Keep notes, bookmarks, and contributions across devices. Or continue as
        a guest.
      </Text>
      {clerkEnabled ? <ClerkAuthPanel /> : <MissingClerkPanel />}
      <View style={styles.orRow}>
        <View style={styles.dividerFlex} />
        <Text style={styles.or}>OR</Text>
        <View style={styles.dividerFlex} />
      </View>
      <Button block onPress={finishGuest} variant="ghost">
        {translateUi(state.preferredLanguage, "continueAsGuest")}
      </Button>
      <View style={styles.flex} />
      <Text style={styles.terms}>
        Your reading is yours. We do not share notes, bookmarks, or vote
        activity.
      </Text>
    </FlowShell>
  );
}

function ClerkAuthPanel() {
  const { state, update } = useOnboardingState();
  const { startSSOFlow } = useSSO();
  const [error, setError] = React.useState<string | null>(null);
  const [busy, setBusy] = React.useState(false);

  const finishSignedIn = async () => {
    await update({
      authMode: "signed-in",
      onboardingComplete: true,
      completedAt: Date.now(),
    });
    go("/paywall/soft", true);
  };

  // Browser-based OAuth (Clerk-hosted). Works without native Google/Apple SDK
  // setup; only requires the providers to be enabled in the Clerk dashboard.
  const startSso = async (strategy: "oauth_apple" | "oauth_google") => {
    if (busy) return;
    setError(null);
    setBusy(true);
    try {
      const { createdSessionId, setActive, signIn, signUp, authSessionResult } =
        await startSSOFlow({
          strategy,
          // expo-linking is part of the core runtime, so this avoids depending
          // on extra native modules; resolves to hadithly://sso-callback.
          redirectUrl: Linking.createURL("/sso-callback"),
        });

      // Diagnostics: shows the exact SSO outcome in the Metro console.
      console.log("[SSO]", strategy, {
        authType: authSessionResult?.type,
        createdSessionId,
        hasSetActive: Boolean(setActive),
        signInStatus: signIn?.status,
        signUpStatus: signUp?.status,
        signUpMissing: signUp?.missingFields,
        signUpUnverified: signUp?.unverifiedFields,
      });

      // User closed the browser without authenticating: not an error.
      if (
        authSessionResult?.type === "cancel" ||
        authSessionResult?.type === "dismiss"
      ) {
        return;
      }

      const sessionId =
        createdSessionId ??
        signUp?.createdSessionId ??
        signIn?.createdSessionId ??
        null;

      if (sessionId && setActive) {
        await setActive({ session: sessionId });
        await finishSignedIn();
        return;
      }

      // OAuth returned but no session. If sign-up only needs a username
      // (a requirement OAuth can't supply), generate one and finalize.
      if (
        signUp &&
        setActive &&
        signUp.status === "missing_requirements" &&
        signUp.missingFields?.includes("username")
      ) {
        try {
          const updated = await signUp.update({
            username: `reader_${Math.random().toString(36).slice(2, 10)}`,
          });
          if (updated.createdSessionId) {
            await setActive({ session: updated.createdSessionId });
            await finishSignedIn();
            return;
          }
        } catch {
          // fall through to the diagnostic error below
        }
      }

      const detail =
        signUp?.status === "missing_requirements"
          ? `needs: ${[...(signUp.missingFields ?? []), ...(signUp.unverifiedFields ?? [])].join(", ") || "more info"}`
          : (signUp?.status ??
            signIn?.status ??
            authSessionResult?.type ??
            "no session");
      setError(`Couldn't finish sign-in (${detail}). See Metro logs.`);
    } catch (nextError) {
      setError(errorMessage(nextError));
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={styles.authStack}>
      <Button
        block
        disabled={busy}
        onPress={() => void startSso("oauth_apple")}
        style={styles.appleButton}
      >
        {translateUi(state.preferredLanguage, "continueWithApple")}
      </Button>
      <Button
        block
        disabled={busy}
        icon={<Sparkles color={t.text} size={18} />}
        onPress={() => void startSso("oauth_google")}
        variant="outline"
      >
        {translateUi(state.preferredLanguage, "continueWithGoogle")}
      </Button>
      <Button
        block
        icon={<Mail color={t.text} size={18} />}
        onPress={() => go("/onboarding/email")}
        variant="outline"
      >
        {translateUi(state.preferredLanguage, "continueWithEmail")}
      </Button>
      {error ? <Text style={styles.errorText}>{error}</Text> : null}
    </View>
  );
}

export function EmailEntryScreen() {
  const { state } = useOnboardingState();
  const [email, setEmail] = React.useState("");
  return (
    <FlowShell>
      <Logo size={32} />
      <Text style={styles.stepTitle}>
        {translateUi(state.preferredLanguage, "email")}
      </Text>
      <TextInput
        autoCapitalize="none"
        autoCorrect={false}
        keyboardType="email-address"
        onChangeText={setEmail}
        placeholder="you@example.com"
        placeholderTextColor={t.textTer}
        style={styles.input}
        value={email}
      />
      <Button
        block
        iconRight={<ArrowRight color="#FFFFFF" size={15} />}
        onPress={() =>
          go(
            `/onboarding/email-password?email=${encodeURIComponent(email.trim())}`,
          )
        }
      >
        {translateUi(state.preferredLanguage, "continue")}
      </Button>
    </FlowShell>
  );
}

export function EmailPasswordScreen() {
  const { email } = useLocalSearchParams<{ email?: string }>();
  const { state, update } = useOnboardingState();
  const signInState = useSignIn();
  const signUpState = useSignUp();
  const { setActive } = useClerk();
  const [password, setPassword] = React.useState("");
  const [isSignUp, setIsSignUp] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const normalizedEmail = Array.isArray(email) ? email[0] : email;

  const finishSignedIn = async () => {
    await update({
      authMode: "signed-in",
      onboardingComplete: true,
      completedAt: Date.now(),
    });
    go("/paywall/soft", true);
  };

  const submitPassword = async () => {
    setError(null);
    if (!normalizedEmail || !password) {
      setError("Enter your email and password.");
      return;
    }
    try {
      if (isSignUp) {
        if (!signUpState.signUp) {
          setError("Email sign-up is still loading. Try again in a moment.");
          return;
        }
        const signUp = signUpState.signUp as any;
        await signUp.create({ emailAddress: normalizedEmail, password });
        await signUp.prepareEmailAddressVerification({
          strategy: "email_code",
        });
        go(
          `/onboarding/email-verify?email=${encodeURIComponent(normalizedEmail)}`,
        );
        return;
      }
      if (!signInState.signIn) {
        setError("Email sign-in is still loading. Try again in a moment.");
        return;
      }
      const signIn = signInState.signIn as any;
      const attempt = await signIn.create({
        identifier: normalizedEmail,
        password,
      });
      if (attempt.status === "complete") {
        await setActive?.({ session: attempt.createdSessionId });
        await finishSignedIn();
        return;
      }
      setError("Authentication needs another Clerk step.");
    } catch (nextError) {
      setError(errorMessage(nextError));
    }
  };

  return (
    <FlowShell>
      <Logo size={32} />
      <Text style={styles.stepTitle}>
        {translateUi(state.preferredLanguage, "password")}
      </Text>
      <Text style={styles.lede}>{normalizedEmail}</Text>
      <TextInput
        autoCapitalize="none"
        onChangeText={setPassword}
        placeholder="Password"
        placeholderTextColor={t.textTer}
        secureTextEntry
        style={styles.input}
        value={password}
      />
      <Button block onPress={submitPassword}>
        {isSignUp ? "Create account" : "Sign in"}
      </Button>
      <Button
        block
        onPress={() => setIsSignUp((current) => !current)}
        variant="ghost"
      >
        {isSignUp ? "I already have an account" : "Create a new account"}
      </Button>
      {error ? <Text style={styles.errorText}>{error}</Text> : null}
    </FlowShell>
  );
}

export function EmailVerifyScreen() {
  const { state, update } = useOnboardingState();
  const signUpState = useSignUp();
  const { setActive } = useClerk();
  const [code, setCode] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);

  const verify = async () => {
    setError(null);
    try {
      if (!signUpState.signUp) {
        setError("Email verification is still loading. Try again in a moment.");
        return;
      }
      const signUp = signUpState.signUp as any;
      const result = await signUp.attemptEmailAddressVerification({
        code: code.trim(),
      });
      if (result.status === "complete") {
        await setActive?.({ session: result.createdSessionId });
        await update({
          authMode: "signed-in",
          onboardingComplete: true,
          completedAt: Date.now(),
        });
        go("/paywall/soft", true);
        return;
      }
      setError("Verification needs another Clerk step.");
    } catch (nextError) {
      setError(errorMessage(nextError));
    }
  };

  return (
    <FlowShell>
      <Logo size={32} />
      <Text style={styles.stepTitle}>
        {translateUi(state.preferredLanguage, "verifyEmail")}
      </Text>
      <TextInput
        keyboardType="number-pad"
        onChangeText={setCode}
        placeholder="Email code"
        placeholderTextColor={t.textTer}
        style={styles.input}
        value={code}
      />
      <Button block onPress={verify}>
        {translateUi(state.preferredLanguage, "verifyEmail")}
      </Button>
      <Button
        block
        onPress={() => {
          if (!signUpState.signUp) {
            setError(
              "Email verification is still loading. Try again in a moment.",
            );
            return;
          }
          void (signUpState.signUp as any).prepareEmailAddressVerification({
            strategy: "email_code",
          });
        }}
        variant="ghost"
      >
        Resend code
      </Button>
      {error ? <Text style={styles.errorText}>{error}</Text> : null}
    </FlowShell>
  );
}

function MissingClerkPanel() {
  return (
    <Card padding={14} style={styles.authStack}>
      <Text style={styles.infoTitle}>Clerk is not configured locally</Text>
      <Text style={styles.mutedBlock}>
        Add EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY to enable Apple, Google, and email
        auth.
      </Text>
    </Card>
  );
}

export function SoftPaywallScreen() {
  return <Paywall kind="soft" />;
}

function languageTitle(code: string) {
  return (
    SUPPORTED_LANGUAGES.find((language) => language.code === code)?.title ??
    code.toUpperCase()
  );
}

function errorMessage(error: unknown) {
  if (
    typeof error === "object" &&
    error &&
    "errors" in error &&
    Array.isArray((error as { errors?: Array<{ message?: string }> }).errors)
  ) {
    return (
      (error as { errors: Array<{ message?: string }> }).errors[0]?.message ??
      "Authentication failed."
    );
  }
  return error instanceof Error ? error.message : "Authentication failed.";
}

export function QuotaPaywallScreen() {
  return <Paywall kind="quota" />;
}

function Paywall({ kind }: { kind: "soft" | "quota" }) {
  const { clerkEnabled } = useAuthRuntime();
  if (clerkEnabled) return <ClerkPaywall kind={kind} />;
  return <PaywallView kind={kind} userId={undefined} />;
}

function ClerkPaywall({ kind }: { kind: "soft" | "quota" }) {
  const { user } = useUser();
  return <PaywallView kind={kind} userId={user?.id} />;
}

type PaywallPlan = {
  pkg: PurchasesPackage;
  label: string;
  price: string;
  sub: string;
};

function buildPlans(packages: PurchasesPackage[]): PaywallPlan[] {
  const order = (pkg: PurchasesPackage) =>
    pkg.packageType === "ANNUAL" ? 0 : pkg.packageType === "MONTHLY" ? 1 : 2;
  return [...packages]
    .sort((a, b) => order(a) - order(b))
    .map((pkg) => ({
      pkg,
      label:
        pkg.packageType === "ANNUAL"
          ? "Annual"
          : pkg.packageType === "MONTHLY"
            ? "Monthly"
            : pkg.product.title || pkg.identifier,
      price: pkg.product.priceString,
      sub:
        pkg.packageType === "ANNUAL"
          ? "billed yearly"
          : pkg.packageType === "MONTHLY"
            ? "per month"
            : "",
    }));
}

function PaywallView({
  kind,
  userId,
}: {
  kind: "soft" | "quota";
  userId?: string;
}) {
  const [plans, setPlans] = React.useState<PaywallPlan[] | null>(null);
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const [busy, setBusy] = React.useState<"buy" | "restore" | null>(null);
  const [message, setMessage] = React.useState<string | null>(null);

  React.useEffect(() => {
    let active = true;
    configurePurchases(userId);
    getCurrentOffering().then((offering) => {
      if (!active) return;
      const next = offering ? buildPlans(offering.availablePackages) : [];
      setPlans(next);
      setSelectedId(next[0]?.pkg.identifier ?? null);
    });
    return () => {
      active = false;
    };
  }, [userId]);

  const selected =
    plans?.find((plan) => plan.pkg.identifier === selectedId) ?? null;
  const hasTrial = Boolean(selected?.pkg.product.introPrice);

  const handlePurchase = async () => {
    if (!selected) {
      setMessage("Plans are still loading. Try again in a moment.");
      return;
    }
    setBusy("buy");
    setMessage(null);
    const result = await purchasePackage(selected.pkg);
    setBusy(null);
    if (result.status === "purchased") {
      go("/home", true);
    } else if (result.status === "error") {
      setMessage(result.message);
    }
  };

  const handleRestore = async () => {
    setBusy("restore");
    setMessage(null);
    const result = await restorePurchases();
    setBusy(null);
    if (result.status === "purchased" && result.isPro) {
      go("/home", true);
    } else if (result.status === "purchased") {
      setMessage("No active Pro subscription found to restore.");
    } else if (result.status === "error") {
      setMessage(result.message);
    }
  };

  return (
    <FlowShell>
      <View style={styles.closeRow}>
        <IconButton onPress={() => router.back()} size={32}>
          <X color={t.text} size={16} />
        </IconButton>
      </View>
      {kind === "quota" ? (
        <Card padding={16}>
          <View style={styles.infoRow}>
            <Info color="#D97706" size={16} />
            <Text style={styles.infoTitle}>AI translation quota reached</Text>
          </View>
          <ProgressBar height={5} value={100} />
          <Text style={styles.mutedBlock}>
            Already-translated hadiths remain free to view. New AI generations
            require available quota or Pro.
          </Text>
        </Card>
      ) : (
        <View style={styles.paywallIcon}>
          <Logo size={36} />
        </View>
      )}
      <Text style={styles.paywallTitle}>
        {kind === "quota"
          ? "Continue translating\nwith AI"
          : "Bring hadith to\nevery language"}
      </Text>
      <Text style={styles.lede}>
        Pro funds AI translations and helps the community improve them.
      </Text>
      <View style={styles.benefits}>
        {[
          "500 AI translations / month",
          "Priority translation queue",
          "Offline language packs",
          "Advanced contribution tools",
        ].map((label) => (
          <View key={label} style={styles.benefit}>
            <Check color={t.accent} size={18} strokeWidth={2.5} />
            <Text style={styles.benefitText}>{label}</Text>
          </View>
        ))}
      </View>

      {plans === null ? (
        <View style={styles.planLoading}>
          <ActivityIndicator color={t.accent} />
        </View>
      ) : plans.length === 0 ? (
        <Text style={styles.mutedBlock}>
          Subscriptions are unavailable right now. Pull down to retry, or
          restore a previous purchase.
        </Text>
      ) : (
        <View style={styles.planRow}>
          {plans.map((plan) => {
            const active = plan.pkg.identifier === selectedId;
            return (
              <Pressable
                key={plan.pkg.identifier}
                onPress={() => setSelectedId(plan.pkg.identifier)}
                style={styles.planPressable}
              >
                <Card
                  padding={14}
                  style={
                    active
                      ? [styles.planCard, styles.planActive]
                      : styles.planCard
                  }
                >
                  <Text style={active ? styles.planAccent : styles.muted}>
                    {plan.label}
                  </Text>
                  <Text style={styles.planPrice}>{plan.price}</Text>
                  <Text style={styles.muted}>{plan.sub}</Text>
                </Card>
              </Pressable>
            );
          })}
        </View>
      )}

      {message ? <Text style={styles.errorText}>{message}</Text> : null}
      <View style={styles.flex} />
      <Button
        block
        disabled={busy !== null || !selected}
        onPress={handlePurchase}
      >
        {busy === "buy"
          ? "Processing..."
          : hasTrial
            ? "Start 3-day free trial"
            : "Subscribe to Pro"}
      </Button>
      <Button
        block
        icon={<RotateCcw color={t.text} size={16} />}
        onPress={handleRestore}
        variant="outline"
      >
        {busy === "restore" ? "Restoring..." : "Restore purchases"}
      </Button>
      <Button block onPress={() => go("/home", true)} variant="ghost">
        Continue free
      </Button>
    </FlowShell>
  );
}

function FlowShell({
  children,
  step,
  progress,
}: {
  children: React.ReactNode;
  step?: string;
  progress?: number;
}) {
  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.flow}>
        {step ? (
          <View style={styles.progressHeader}>
            <IconButton onPress={() => router.back()} size={32}>
              <ChevronLeft color={t.text} size={18} />
            </IconButton>
            <View style={styles.progress}>
              <ProgressBar value={progress} height={4} />
            </View>
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
  splash: {
    alignItems: "center",
    backgroundColor: t.bg,
    flex: 1,
    justifyContent: "center",
  },
  splashHalo: {
    backgroundColor: t.accentSoft,
    borderRadius: 120,
    height: 240,
    opacity: 0.75,
    position: "absolute",
    top: "25%",
    width: 240,
  },
  splashTitle: {
    color: t.text,
    fontSize: 38,
    fontWeight: "700",
    letterSpacing: -0.5,
    marginTop: 18,
  },
  splashArabic: {
    color: t.textSec,
    fontSize: 18,
    marginTop: -7,
    writingDirection: "rtl",
  },
  splashLine: { backgroundColor: t.hair, height: 1, marginTop: 96, width: 60 },
  splashTag: {
    color: t.textTer,
    fontSize: 12,
    fontWeight: "600",
    letterSpacing: 0.8,
    marginTop: 28,
    textTransform: "uppercase",
  },
  heroTitle: {
    color: t.text,
    fontSize: 38,
    fontWeight: "700",
    letterSpacing: -0.8,
    lineHeight: 40,
    marginTop: 18,
  },
  onboardingTop: { gap: 0 },
  onboardingBottom: { gap: 10 },
  imageSlotWrap: {
    alignItems: "center",
    flex: 1,
    justifyContent: "center",
    paddingVertical: 20,
  },
  imageSlot: {
    alignItems: "center",
    aspectRatio: 1,
    backgroundColor: t.accentSoft,
    borderColor: t.hair,
    borderRadius: 22,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 16,
    justifyContent: "center",
    maxHeight: 360,
    width: "100%",
  },
  imageSlotTile: {
    alignItems: "center",
    backgroundColor: t.bg,
    borderRadius: 20,
    height: 96,
    justifyContent: "center",
    shadowColor: "#000",
    shadowOffset: { height: 6, width: 0 },
    shadowOpacity: 0.06,
    shadowRadius: 14,
    width: 96,
  },
  imageCaption: {
    color: t.accentText,
    fontSize: 12.5,
    fontWeight: "600",
    letterSpacing: 0.2,
  },
  stepTitle: {
    color: t.text,
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.5,
    lineHeight: 31,
    marginTop: 8,
  },
  lede: { color: t.textSec, fontSize: 14.5, lineHeight: 22, marginTop: 10 },
  reminder: { marginTop: 28 },
  reminderLabel: {
    alignSelf: "flex-start",
    backgroundColor: t.bg,
    color: t.textTer,
    fontSize: 10,
    fontWeight: "700",
    letterSpacing: 0.7,
    marginTop: -28,
    paddingHorizontal: 8,
    textTransform: "uppercase",
  },
  reminderArabic: {
    color: t.text,
    fontSize: 20,
    lineHeight: 37,
    marginTop: 10,
    textAlign: "right",
    writingDirection: "rtl",
  },
  reminderText: {
    color: t.textSec,
    fontFamily: "Georgia",
    fontSize: 14.5,
    lineHeight: 23,
    marginTop: 10,
  },
  muted: { color: t.textTer, fontSize: 11.5 },
  terms: {
    color: t.textTer,
    fontSize: 11.5,
    lineHeight: 17,
    marginTop: 12,
    textAlign: "center",
  },
  flex: { flex: 1 },
  progressHeader: {
    alignItems: "center",
    flexDirection: "row",
    gap: 10,
    marginBottom: 22,
  },
  progress: { flex: 1 },
  step: { color: t.textSec, fontSize: 12, fontWeight: "600" },
  languageList: { gap: 2, paddingVertical: 18 },
  languageRow: {
    alignItems: "center",
    borderColor: "transparent",
    borderRadius: 7,
    borderWidth: 1,
    flexDirection: "row",
    gap: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  selectedLanguage: { backgroundColor: "#EFFBF4", borderColor: t.accent },
  flag: { color: t.text, fontSize: 13, fontWeight: "800", width: 24 },
  languageCopy: { flex: 1 },
  languageTitleRow: { alignItems: "baseline", flexDirection: "row", gap: 8 },
  languageTitle: { color: t.text, fontSize: 15.5, fontWeight: "700" },
  languageNative: { color: t.textSec, fontSize: 13 },
  languageMeta: { color: t.textSec, fontSize: 11.5, marginTop: 4 },
  radio: {
    alignItems: "center",
    borderColor: t.hair,
    borderRadius: 11,
    borderWidth: 1.5,
    height: 22,
    justifyContent: "center",
    width: 22,
  },
  radioSelected: { backgroundColor: t.accent, borderColor: t.accent },
  pushPreview: {
    alignItems: "flex-start",
    flexDirection: "row",
    gap: 11,
    marginTop: 22,
  },
  appIcon: {
    alignItems: "center",
    backgroundColor: t.text,
    borderRadius: 9,
    height: 38,
    justifyContent: "center",
    width: 38,
  },
  pushCopy: { flex: 1 },
  pushTop: { flexDirection: "row", justifyContent: "space-between" },
  pushApp: { color: t.text, fontSize: 13, fontWeight: "700" },
  pushTitle: { color: t.text, fontSize: 13.5, fontWeight: "600", marginTop: 2 },
  pushBody: { color: t.textSec, fontSize: 12.5, lineHeight: 18, marginTop: 1 },
  settingsCard: { marginTop: 22, paddingHorizontal: 16 },
  previewCard: { marginTop: 16 },
  metaRow: {
    alignItems: "center",
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 6,
    marginBottom: 10,
  },
  ref: { color: t.textTer, fontSize: 10.5, fontWeight: "600" },
  softChipText: { color: t.accentText, fontSize: 10.5, fontWeight: "700" },
  previewArabic: {
    color: t.text,
    fontSize: 21,
    lineHeight: 42,
    textAlign: "right",
    writingDirection: "rtl",
  },
  previewEnglish: {
    color: t.text,
    fontFamily: "Georgia",
    fontSize: 14,
    lineHeight: 23,
    marginTop: 10,
  },
  divider: {
    backgroundColor: t.hair,
    height: StyleSheet.hairlineWidth,
    marginVertical: 12,
  },
  previewRussian: {
    color: t.textSec,
    fontFamily: "Georgia",
    fontSize: 14,
    fontStyle: "italic",
    lineHeight: 23,
    marginTop: 10,
  },
  authStack: { gap: 10, marginTop: 32 },
  input: {
    backgroundColor: t.surface2,
    borderColor: t.hair,
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    color: t.text,
    fontSize: 14,
    paddingHorizontal: 12,
    paddingVertical: 12,
  },
  errorText: { color: t.danger, fontSize: 12, lineHeight: 17 },
  appleButton: { backgroundColor: "#000000" },
  orRow: {
    alignItems: "center",
    flexDirection: "row",
    gap: 10,
    marginVertical: 24,
  },
  dividerFlex: {
    backgroundColor: t.hair,
    flex: 1,
    height: StyleSheet.hairlineWidth,
  },
  or: {
    color: t.textTer,
    fontSize: 10.5,
    fontWeight: "700",
    letterSpacing: 0.8,
  },
  closeRow: { alignItems: "flex-end" },
  paywallIcon: {
    alignItems: "center",
    alignSelf: "center",
    backgroundColor: t.accent,
    borderRadius: 14,
    height: 60,
    justifyContent: "center",
    marginTop: 12,
    width: 60,
  },
  paywallTitle: {
    color: t.text,
    fontSize: 28,
    fontWeight: "700",
    letterSpacing: -0.7,
    lineHeight: 31,
    marginTop: 18,
    textAlign: "center",
  },
  benefits: { gap: 11, marginTop: 22 },
  benefit: { alignItems: "center", flexDirection: "row", gap: 12 },
  benefitText: { color: t.text, fontSize: 14.5 },
  planRow: { flexDirection: "row", gap: 10, marginTop: 22 },
  planPressable: { flex: 1 },
  planLoading: { alignItems: "center", marginTop: 28 },
  planCard: { flex: 1 },
  planActive: { backgroundColor: "#EFFBF4", borderColor: t.accent },
  planAccent: { color: t.accent, fontSize: 11.5, fontWeight: "700" },
  planPrice: { color: t.text, fontSize: 22, fontWeight: "700", marginTop: 4 },
  infoRow: {
    alignItems: "center",
    flexDirection: "row",
    gap: 8,
    marginBottom: 8,
  },
  infoTitle: { color: t.text, fontSize: 13, fontWeight: "700" },
  mutedBlock: { color: t.textSec, fontSize: 12, lineHeight: 18, marginTop: 8 },
});
