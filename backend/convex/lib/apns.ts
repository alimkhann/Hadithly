"use node";

/**
 * APNs client for the daily hadith push. Node-only (HTTP/2), called from
 * actions/daily.ts. Credentials live in Convex env vars:
 *
 *   APNS_KEY_ID       key id of the .p8 signing key
 *   APNS_TEAM_ID      Apple Developer team id
 *   APNS_PRIVATE_KEY  PEM contents of the .p8 key (\n escapes fine)
 *   APNS_ENVIRONMENT  "sandbox" (default) or "production"
 *   APNS_TOPIC        defaults to the iOS bundle id com.hadithly.app
 *
 * Nothing is sent (and nothing throws) when the credentials are absent, so
 * the cron can ship before the Apple-side key is provisioned.
 */

import * as crypto from "node:crypto";
import * as http2 from "node:http2";

export type ApnsPayload = {
  alert: { title: string; subtitle?: string; body: string };
  /** Arbitrary app metadata delivered with the notification. */
  custom?: Record<string, string>;
};

export function apnsConfigured(): boolean {
  return Boolean(
    process.env.APNS_KEY_ID &&
      process.env.APNS_TEAM_ID &&
      process.env.APNS_PRIVATE_KEY,
  );
}

function base64Url(input: Buffer | string): string {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/**
 * DER → raw r||s. APNs (like all JOSE ES256 verifiers) expects the 64-byte
 * concatenated form, while node's createSign emits ASN.1 DER.
 */
function derSignatureToRaw(der: Buffer): Buffer {
  if (der[0] !== 0x30) throw new Error("Unexpected ECDSA signature encoding");
  let offset = 2;
  if (der[1] & 0x80) offset += der[1] & 0x7f;
  if (der[offset] !== 0x02) throw new Error("Unexpected ECDSA r encoding");
  const rLength = der[offset + 1];
  const r = der.subarray(offset + 2, offset + 2 + rLength);
  const sOffset = offset + 2 + rLength;
  if (der[sOffset] !== 0x02) throw new Error("Unexpected ECDSA s encoding");
  const sLength = der[sOffset + 1];
  const s = der.subarray(sOffset + 2, sOffset + 2 + sLength);
  const raw = Buffer.alloc(64);
  r.copy(raw, 32 - r.length);
  s.copy(raw, 64 - s.length);
  return raw;
}

function providerToken(): string {
  const header = base64Url(
    JSON.stringify({ alg: "ES256", kid: process.env.APNS_KEY_ID }),
  );
  const claims = base64Url(
    JSON.stringify({
      iss: process.env.APNS_TEAM_ID,
      iat: Math.floor(Date.now() / 1000),
    }),
  );
  const signingInput = `${header}.${claims}`;
  const key = crypto.createPrivateKey(process.env.APNS_PRIVATE_KEY!);
  const der = crypto
    .createSign("SHA256")
    .update(signingInput)
    .sign(key);
  return `${signingInput}.${base64Url(derSignatureToRaw(der))}`;
}

/**
 * Sends one push. Resolves with the APNs HTTP status; throws on transport
 * failure so the caller can decide whether to retry later.
 */
export function sendApnsPush(deviceToken: string, payload: ApnsPayload): Promise<number> {
  const host =
    process.env.APNS_ENVIRONMENT === "production"
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com";
  const topic = process.env.APNS_TOPIC ?? "com.hadithly.app";
  const authorization = `bearer ${providerToken()}`;
  const body = JSON.stringify({
    aps: {
      alert: payload.alert,
      sound: "default",
    },
    ...(payload.custom ?? {}),
  });

  return new Promise<number>((resolve, reject) => {
    const session = http2.connect(`https://${host}`);
    session.on("error", (error) => {
      session.close();
      reject(error);
    });

    const request = session.request({
      [http2.constants.HTTP2_HEADER_METHOD]: http2.constants.HTTP2_METHOD_POST,
      [http2.constants.HTTP2_HEADER_PATH]: `/3/device/${deviceToken}`,
      [http2.constants.HTTP2_HEADER_AUTHORIZATION]: authorization,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      [http2.constants.HTTP2_HEADER_CONTENT_TYPE]: "application/json",
    });
    request.setEncoding("utf8");
    let responseText = "";
    request.on("data", (chunk: string) => {
      responseText += chunk;
    });
    request.on("response", (headers) => {
      const status = Number(headers[http2.constants.HTTP2_HEADER_STATUS]);
      request.on("end", () => {
        session.close();
        if (status >= 200 && status < 300) {
          resolve(status);
        } else {
          reject(
            new Error(`APNs rejected push (${status}): ${responseText}`),
          );
        }
      });
    });
    request.on("error", (error) => {
      session.close();
      reject(error);
    });
    request.end(body);
  });
}
