import { useAuth, useUser } from "@clerk/expo";
import { useMutation } from "convex/react";
import { makeFunctionReference } from "convex/server";
import { useEffect } from "react";

import { useOnboardingState } from "./onboarding";

const upsertCurrentUser = makeFunctionReference<
  "mutation",
  {
    clerkId: string;
    email?: string;
    displayName?: string;
    avatarUrl?: string;
    preferredLanguage?: string;
  },
  string
>("users:upsertCurrentUser");

export function ClerkUserSync() {
  const { isSignedIn } = useAuth();
  const { user } = useUser();
  const { state } = useOnboardingState();
  const upsert = useMutation(upsertCurrentUser);

  useEffect(() => {
    if (!isSignedIn || !user) return;
    void upsert({
      clerkId: user.id,
      email: user.primaryEmailAddress?.emailAddress,
      displayName: user.fullName ?? user.username ?? undefined,
      avatarUrl: user.imageUrl,
      preferredLanguage: state.preferredLanguage,
    });
  }, [isSignedIn, state.preferredLanguage, upsert, user]);

  return null;
}
