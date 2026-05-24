import { ClerkProvider } from "@clerk/expo";
import { ConvexProvider, ConvexReactClient } from "convex/react";
import { Stack } from "expo-router";
import * as SplashScreen from "expo-splash-screen";
import { ReactNode, useEffect, useMemo } from "react";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

void SplashScreen.preventAutoHideAsync();

const clerkKey = process.env.EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY;
const convexUrl = process.env.EXPO_PUBLIC_CONVEX_URL;

export default function RootLayout() {
  useEffect(() => {
    void SplashScreen.hideAsync();
  }, []);

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <OptionalClerkProvider publishableKey={clerkKey}>
        <OptionalConvexProvider url={convexUrl}>
          <SafeAreaProvider>
            <Stack screenOptions={{ headerShown: false }}>
              <Stack.Screen name="index" />
              <Stack.Screen name="onboarding/splash" />
              <Stack.Screen name="onboarding/welcome" />
              <Stack.Screen name="onboarding/language" />
              <Stack.Screen name="onboarding/notifications" />
              <Stack.Screen name="onboarding/preview" />
              <Stack.Screen name="onboarding/auth" />
              <Stack.Screen name="paywall/soft" />
              <Stack.Screen name="paywall/quota" />
              <Stack.Screen name="(tabs)" />
              <Stack.Screen name="notifications" />
              <Stack.Screen name="topic/[slug]" />
              <Stack.Screen name="collection/[slug]" />
              <Stack.Screen name="search" />
              <Stack.Screen name="submit-translation" />
              <Stack.Screen name="settings" />
              <Stack.Screen name="reader/[collectionSlug]" />
            </Stack>
          </SafeAreaProvider>
        </OptionalConvexProvider>
      </OptionalClerkProvider>
    </GestureHandlerRootView>
  );
}

function OptionalConvexProvider({
  children,
  url,
}: {
  children: ReactNode;
  url?: string;
}) {
  const client = useMemo(
    () => (url ? new ConvexReactClient(url) : null),
    [url],
  );
  if (!client) {
    return children;
  }
  return <ConvexProvider client={client}>{children}</ConvexProvider>;
}

function OptionalClerkProvider({
  children,
  publishableKey,
}: {
  children: ReactNode;
  publishableKey?: string;
}) {
  if (!publishableKey) {
    return children;
  }

  return (
    <ClerkProvider publishableKey={publishableKey}>{children}</ClerkProvider>
  );
}
