"use node";
import { createHash } from "node:crypto";
import { verifyAttestation, verifyAssertion } from "node-app-attest";
import { GoogleAuth } from "google-auth-library";
import type { Infer } from "convex/values";
import type { ActionCtx } from "../_generated/server";
import type { Id } from "../_generated/dataModel";
import { internal } from "../_generated/api";
import { allowUnattestedDevelopment, isNamedDevelopmentDeployment, integrityProof } from "../generationIntegrity";
import { validPlayIntegrity } from "../lib/playIntegrity";

function record(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === "object" && !Array.isArray(value); }
function proofBytes(value: string) {
  if (!value || value.length > 32_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new Error("AI_INTEGRITY_REJECTED");
  return Buffer.from(value, "base64");
}

export async function verifyGenerationProof(ctx: ActionCtx, input: {
  clerkId: string; hadithId: Id<"hadiths">; language: string; challengeId?: Id<"generationChallenges">; proof?: Infer<typeof integrityProof>;
}): Promise<{ signal: "app_attest" | "play_integrity" | "unavailable_dev"; verifiedGenerationKey: string }> {
  if (!input.challengeId || !input.proof) throw new Error("AI_INTEGRITY_REQUIRED");
  const proof = input.proof;
  const { challenge, credential } = await ctx.runQuery(internal.generationIntegrity.verificationContext, {
    challengeId: input.challengeId, clerkId: input.clerkId, hadithId: input.hadithId, language: input.language,
    ...(proof.kind === "app_attest" ? { keyId: proof.keyId } : {}),
  });
  const payload = `${challenge.nonce}:${challenge.generationKey}`;
  if (proof.kind === "unavailable") {
    if (!allowUnattestedDevelopment()) throw new Error("AI_INTEGRITY_REQUIRED");
    await ctx.runMutation(internal.generationIntegrity.consumeVerified, { challengeId: challenge._id });
    return { signal: "unavailable_dev", verifiedGenerationKey: challenge.generationKey };
  }
  try {
    if (proof.kind === "app_attest") {
      const bundleIdentifier = process.env.APP_ATTEST_BUNDLE_ID, teamIdentifier = process.env.APP_ATTEST_TEAM_ID;
      if (!bundleIdentifier || !teamIdentifier || proof.keyId.length > 200) throw new Error("AI_INTEGRITY_REQUIRED");
      if (credential) {
        if (!proof.assertion || proof.attestation) throw new Error("Invalid assertion");
        const verified: unknown = verifyAssertion({ assertion: proofBytes(proof.assertion), payload, publicKey: credential.publicKey,
          bundleIdentifier, teamIdentifier, signCount: credential.signCount });
        if (!record(verified) || typeof verified.signCount !== "number" || !Number.isSafeInteger(verified.signCount)) throw new Error("Invalid counter");
        await ctx.runMutation(internal.generationIntegrity.consumeVerified, { challengeId: challenge._id,
          credential: { keyId: proof.keyId, publicKey: credential.publicKey, signCount: verified.signCount, previousCount: credential.signCount } });
      } else {
        if (!proof.attestation || proof.assertion) throw new Error("Invalid attestation");
        const verified: unknown = verifyAttestation({ attestation: proofBytes(proof.attestation), challenge: payload, keyId: proof.keyId,
          bundleIdentifier, teamIdentifier, allowDevelopmentEnvironment: isNamedDevelopmentDeployment() });
        if (!record(verified) || typeof verified.publicKey !== "string" || verified.keyId !== proof.keyId) throw new Error("Invalid attestation");
        await ctx.runMutation(internal.generationIntegrity.consumeVerified, { challengeId: challenge._id,
          credential: { keyId: proof.keyId, publicKey: verified.publicKey, signCount: 0 } });
      }
      return { signal: "app_attest", verifiedGenerationKey: challenge.generationKey };
    }
    if (proof.token.length > 32_000) throw new Error("Invalid token");
    const packageName = process.env.PLAY_INTEGRITY_PACKAGE_NAME;
    const certificateDigests = process.env.PLAY_INTEGRITY_CERTIFICATE_DIGESTS?.split(",").map(value => value.trim()).filter(Boolean) ?? [];
    const rawCredentials = process.env.PLAY_INTEGRITY_CREDENTIALS;
    if (!packageName || !certificateDigests.length || !rawCredentials) throw new Error("AI_INTEGRITY_REQUIRED");
    const credentials: unknown = JSON.parse(rawCredentials);
    if (!record(credentials) || typeof credentials.client_email !== "string" || typeof credentials.private_key !== "string") throw new Error("Invalid configuration");
    const auth = new GoogleAuth({ credentials: { client_email: credentials.client_email, private_key: credentials.private_key }, scopes: ["https://www.googleapis.com/auth/playintegrity"] });
    const token = await auth.getAccessToken();
    const response = await fetch(`https://playintegrity.googleapis.com/v1/${encodeURIComponent(packageName)}:decodeIntegrityToken`, {
      method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ integrity_token: proof.token }), signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error("Decode failed");
    const decoded: unknown = await response.json();
    if (!validPlayIntegrity(decoded, { packageName, certificateDigests, requestHash: createHash("sha256").update(payload).digest("base64url"), now: Date.now() })) throw new Error("Invalid verdict");
    await ctx.runMutation(internal.generationIntegrity.consumeVerified, { challengeId: challenge._id });
    return { signal: "play_integrity", verifiedGenerationKey: challenge.generationKey };
  } catch {
    throw new Error("AI_INTEGRITY_REJECTED");
  }
}
