export type SsoCompletionInput = {
  createdSessionId?: string | null;
  hasSetActive: boolean;
};

export function ssoCompletionResult(input: SsoCompletionInput) {
  if (input.createdSessionId && input.hasSetActive) {
    return { status: "complete" as const, sessionId: input.createdSessionId };
  }
  return {
    status: "incomplete" as const,
    reason: "Authentication needs another Clerk step.",
  };
}

export function nextRouteAfterAuth({
  onboardingComplete,
}: {
  onboardingComplete: boolean;
}) {
  return onboardingComplete ? "/home" : "/paywall/soft";
}

export function emailAuthStepFor({
  hasEmail,
  hasPassword,
  needsVerification,
}: {
  hasEmail: boolean;
  hasPassword?: boolean;
  needsVerification?: boolean;
}) {
  if (!hasEmail) return "email" as const;
  if (!hasPassword) return "password" as const;
  if (needsVerification) return "verify" as const;
  return "complete" as const;
}
