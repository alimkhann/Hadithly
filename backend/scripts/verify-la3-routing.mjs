#!/usr/bin/env node
// Approved owner-only forwarding proof. Never sends an authentication message.
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const backendDir = fileURLToPath(new URL("../", import.meta.url));
const configured = readFileSync(new URL("../.env.local", import.meta.url), "utf8");
if (!process.argv.includes("--send")) throw new Error("Pass --send only for an owner-approved synthetic routing test");
if (!/^CONVEX_DEPLOYMENT=dev:festive-cobra-664(?:\s|$)/m.test(configured)) throw new Error("Development deployment required");
const key = execFileSync("npx", ["convex", "env", "get", "RESEND_API_KEY", "--deployment", "festive-cobra-664"], { cwd: backendDir, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
if (!/^re_[A-Za-z0-9_-]{20,100}$/.test(key)) throw new Error("Scoped sending key is not configured");
const day = new Date().toISOString().slice(0, 10);
const response = await fetch("https://api.resend.com/emails", { method: "POST", redirect: "error", signal: AbortSignal.timeout(10_000),
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}`, "Idempotency-Key": `la3-support-routing-${day}` },
  body: JSON.stringify({ from: "Hadithly routing verification <verification@updates.hadithly.app>", to: ["support@hadithly.app"],
    subject: "Hadithly support routing verification", text: "Synthetic LA3 support forwarding test. Self-authored text only, no real user data. The approved support alias should forward this message to the owner's selected mailbox." }) });
if (!response.ok) throw new Error(`Controlled routing test rejected with HTTP ${response.status}`);
const result = await response.json();
if (typeof result?.id !== "string" || !/^[A-Za-z0-9-]{1,100}$/.test(result.id)) throw new Error("Invalid provider receipt");
process.stdout.write(JSON.stringify({ day, providerId: result.id, destination: "support@hadithly.app", synthetic: true,
  retriedAutomatically: false, idempotencyWindowHours: 24 }) + "\n");
