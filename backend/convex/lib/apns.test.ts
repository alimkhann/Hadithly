import { createSign, generateKeyPairSync, verify } from "node:crypto";
import { describe, expect, test } from "vitest";
import { derSignatureToRaw } from "./apns";

describe("derSignatureToRaw", () => {
  test("produces verifiable raw signatures across padded and unpadded values", () => {
    const { privateKey, publicKey } = generateKeyPairSync("ec", {
      namedCurve: "P-256",
    });
    // ~75% of P-256 signatures carry a DER leading zero in r or s; the old
    // copy assumed ≤32 bytes and crashed with "targetStart out of range".
    for (let i = 0; i < 50; i += 1) {
      const data = Buffer.from(`daily-hadith-${i}`);
      const der = createSign("SHA256").update(data).sign(privateKey);
      const raw = derSignatureToRaw(der);
      expect(raw).toHaveLength(64);
      const ok = verify("sha256", data, {
        key: publicKey,
        dsaEncoding: "ieee-p1363",
      }, raw);
      expect(ok).toBe(true);
    }
  });

  test("rejects malformed encodings", () => {
    expect(() => derSignatureToRaw(Buffer.from([0x31, 0x00]))).toThrow();
  });
});
