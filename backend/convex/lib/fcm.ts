"use node";

/**
 * Minimal FCM HTTP v1 client. Credentials stay in Convex env vars:
 *
 *   FCM_PROJECT_ID
 *   FCM_CLIENT_EMAIL
 *   FCM_PRIVATE_KEY  PEM service-account key (literal \n escapes accepted)
 */

import * as crypto from "node:crypto";

export type FcmPayload = {
  title: string;
  body: string;
  data?: Record<string, string>;
};

let cachedAccessToken: { value: string; expiresAt: number } | undefined;

export function fcmConfigured(): boolean {
  return Boolean(
    process.env.FCM_PROJECT_ID &&
      process.env.FCM_CLIENT_EMAIL &&
      process.env.FCM_PRIVATE_KEY,
  );
}

function base64Url(input: string | Buffer): string {
  return Buffer.from(input).toString("base64url");
}

async function accessToken(): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(
    JSON.stringify({
      iss: process.env.FCM_CLIENT_EMAIL,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${claims}`;
  const key = process.env.FCM_PRIVATE_KEY!.replace(/\\n/g, "\n");
  const signature = crypto.sign("RSA-SHA256", Buffer.from(signingInput), key);
  const assertion = `${signingInput}.${base64Url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const payload = (await response.json()) as {
    access_token?: string;
    expires_in?: number;
    error_description?: string;
  };
  if (!response.ok || !payload.access_token) {
    throw new Error(
      `FCM authorization failed (${response.status}): ${payload.error_description ?? "unknown error"}`,
    );
  }
  cachedAccessToken = {
    value: payload.access_token,
    expiresAt: Date.now() + (payload.expires_in ?? 3600) * 1000,
  };
  return payload.access_token;
}

export async function sendFcmPush(
  installationId: string,
  payload: FcmPayload,
): Promise<void> {
  const token = await accessToken();
  const projectId = process.env.FCM_PROJECT_ID!;
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          fid: installationId,
          notification: { title: payload.title, body: payload.body },
          data: payload.data ?? {},
          android: {
            priority: "high",
            notification: { channel_id: "daily_hadith" },
          },
        },
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`FCM rejected push (${response.status}): ${await response.text()}`);
  }
}
