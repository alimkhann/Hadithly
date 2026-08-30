import { Redirect } from "expo-router";

import { isOnboardingComplete, useOnboardingState } from "@/lib/onboarding";

export default function Index() {
  const { state, isLoading } = useOnboardingState();
  // Keep the native splash visible until persisted state resolves.
  if (isLoading) return null;
  return (
    <Redirect
      href={
        (isOnboardingComplete(state) ? "/home" : "/onboarding/welcome") as never
      }
    />
  );
}
