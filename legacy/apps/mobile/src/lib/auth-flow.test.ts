import { describe, expect, it } from "vitest";

import {
  emailAuthStepFor,
  nextRouteAfterAuth,
  ssoCompletionResult,
} from "./auth-flow";

describe("auth flow helpers", () => {
  it("routes successful auth through onboarding completion and soft paywall", () => {
    expect(nextRouteAfterAuth({ onboardingComplete: false })).toBe(
      "/paywall/soft",
    );
    expect(nextRouteAfterAuth({ onboardingComplete: true })).toBe("/home");
  });

  it("distinguishes complete SSO sessions from incomplete transfers", () => {
    expect(
      ssoCompletionResult({ createdSessionId: "sess_123", hasSetActive: true }),
    ).toEqual({ status: "complete", sessionId: "sess_123" });
    expect(ssoCompletionResult({ createdSessionId: null, hasSetActive: true }))
      .toEqual({
        status: "incomplete",
        reason: "Authentication needs another Clerk step.",
      });
  });

  it("puts email auth on password then verification steps", () => {
    expect(emailAuthStepFor({ hasEmail: false })).toBe("email");
    expect(emailAuthStepFor({ hasEmail: true, hasPassword: false })).toBe(
      "password",
    );
    expect(
      emailAuthStepFor({
        hasEmail: true,
        hasPassword: true,
        needsVerification: true,
      }),
    ).toBe("verify");
  });
});
