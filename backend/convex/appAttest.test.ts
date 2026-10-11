import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { verifyAttestation } from "node-app-attest";

// Public signed fixtures shipped by the pinned MIT-licensed verifier package.
function fixture(environment: "production" | "development") {
  const value: unknown = JSON.parse(readFileSync(new URL(`../node_modules/node-app-attest/test/fixtures/attestation-${environment}.json`, import.meta.url), "utf8"));
  if (!value || typeof value !== "object" || !("attestation" in value) || !("keyId" in value) || !("challenge" in value) ||
    typeof value.attestation !== "string" || typeof value.keyId !== "string" || typeof value.challenge !== "string") throw new Error("Invalid signed fixture");
  return { attestation: Buffer.from(value.attestation, "base64"), challenge: Buffer.from(value.challenge, "base64"), keyId: value.keyId,
    bundleIdentifier: "io.uebelacker.AppAttestExample", teamIdentifier: "V8H6LQ9448", allowDevelopmentEnvironment: false };
}

describe("real App Attest cryptographic validation", () => {
  test("signed production attestation validates; changed challenge/key/app fails", () => {
    const input = fixture("production");
    expect(verifyAttestation(input)).toMatchObject({ environment: "production", keyId: input.keyId });
    for (const change of [{ challenge: Buffer.from("tampered") }, { keyId: "wrong" }, { bundleIdentifier: "com.other.app" }])
      expect(() => verifyAttestation({ ...input, ...change })).toThrow();
  });
  test("development attestation is rejected by production policy", () => {
    const input = fixture("development");
    expect(() => verifyAttestation(input)).toThrow();
    expect(verifyAttestation({ ...input, allowDevelopmentEnvironment: true })).toMatchObject({ environment: "development" });
  });
});
