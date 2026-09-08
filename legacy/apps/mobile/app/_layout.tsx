import { ClerkProvider, useAuth } from "@clerk/expo";
import { tokenCache } from "@clerk/expo/token-cache";
import { ConvexProvider, ConvexReactClient } from "convex/react";
import { ConvexProviderWithClerk } from "convex/react-clerk";
import { Stack } from "expo-router";
import * as SplashScreen from "expo-splash-screen";
import { ReactNode, useEffect, useMemo } from "react";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";

import { AuthRuntimeProvider } from "@/lib/auth-runtime";
import { ClerkUserSync } from "@/lib/user-sync";

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
        <OptionalConvexProvider
          clerkEnabled={Boolean(clerkKey)}
          url={convexUrl}
        >
          <AuthRuntimeProvider
            value={{
              clerkEnabled: Boolean(clerkKey),
              convexEnabled: Boolean(convexUrl),
            }}
          >
            <SafeAreaProvider>
              <Stack screenOptions={{ headerShown: false }}>
                <Stack.Screen name="index" />
                <Stack.Screen name="onboarding/splash" />
                <Stack.Screen name="onboarding/welcome" />
                <Stack.Screen name="onboarding/language" />
                <Stack.Screen name="onboarding/notifications" />
                <Stack.Screen name="onboarding/preview" />
                <Stack.Screen name="onboarding/auth" />
                <Stack.Screen name="onboarding/email" />
                <Stack.Screen name="onboarding/email-password" />
                <Stack.Screen name="onboarding/email-verify" />
                <Stack.Screen name="paywall/soft" />
                <Stack.Screen name="paywall/quota" />
                <Stack.Screen name="(tabs)" />
                <Stack.Screen name="notifications" />
                <Stack.Screen name="collection/[slug]" />
                <Stack.Screen name="search" />
                <Stack.Screen name="submit-translation" />
                <Stack.Screen name="settings" />
                <Stack.Screen
                  name="reader/[collectionSlug]"
                  options={{ gestureEnabled: false }}
                />
              </Stack>
            </SafeAreaProvider>
          </AuthRuntimeProvider>
        </OptionalConvexProvider>
      </OptionalClerkProvider>
    </GestureHandlerRootView>
  );
}

function OptionalConvexProvider({
  children,
  clerkEnabled,
  url,
}: {
  children: ReactNode;
  clerkEnabled: boolean;
  url?: string;
}) {
  const client = useMemo(
    () => (url ? new ConvexReactClient(url) : null),
    [url],
  );
  if (!client) {
    return children;
  }
  if (clerkEnabled) {
    return (
      <ConvexProviderWithClerk client={client} useAuth={useAuth}>
        <ClerkUserSync />
        {children}
      </ConvexProviderWithClerk>
    );
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
    <ClerkProvider publishableKey={publishableKey} tokenCache={tokenCache}>
      {children}
    </ClerkProvider>
  );
}
