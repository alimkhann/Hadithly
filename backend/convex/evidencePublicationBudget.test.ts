/// <reference types="vite/client" />
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import { fixture, passes, reviewClaim } from "../test/evidenceFixtures";
import { PublicationReadBudget, publicTranslationAvailable, publicationExpiry } from "./lib/evidencePublication";

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

async function published() {
  const f = await fixture();
  const claim = await reviewClaim(f);
  expect(await f.t.mutation(internal.evidenceReview.finish, {
    submissionId: f.draft.submissionId, token: claim.token, passes: passes(claim.packet),
  })).toBe(true);
  const translation = await f.t.run(ctx => ctx.db.query("translations")
    .withIndex("by_hadith_language_default", q => q.eq("hadithId", f.hadithId).eq("language", "en").eq("isDefault", true)).unique());
  if (!translation?.evidencePublicationId) throw new Error("Expected published fixture");
  return { ...f, translation, publicationId: translation.evidencePublicationId };
}

test("a real published translation remains readable within the caller's budget", async () => {
  const f = await published();
  const budget = new PublicationReadBudget(128);
  expect(await f.t.run(ctx => publicTranslationAvailable(ctx, f.translation, new Set(), budget))).toBe(true);
  expect(budget.remaining).toBeLessThan(128);
  expect(budget.exhausted).toBe(false);
  expect(await f.t.run(ctx => publicationExpiry(ctx, f.publicationId, new Set(), budget))).toBeNull();
});

test("permission validation fails closed when point reads exhaust the budget", async () => {
  const f = await published();
  const budget = new PublicationReadBudget(1);
  expect(await f.t.run(ctx => publicTranslationAvailable(ctx, f.translation, new Set(), budget))).toBe(false);
  expect(budget.exhausted).toBe(true);
  expect(await f.t.run(ctx => publicationExpiry(ctx, f.publicationId, new Set(), budget))).toBe(0);
});

test("large indexed dependency sets cannot bypass a bounded public read", async () => {
  const f = await published();
  await f.t.run(async ctx => {
    for (let index = 0; index < 140; index++) {
      await ctx.db.insert("evidenceSourceDependencies", {
        submissionId: f.draft.submissionId, origin: `https://fixture-${index}.example.org`,
      });
    }
  });
  expect(await f.t.run(ctx => publicTranslationAvailable(ctx, f.translation))).toBe(true);
  const budget = new PublicationReadBudget(32);
  expect(await f.t.run(ctx => publicTranslationAvailable(ctx, f.translation, new Set(), budget))).toBe(false);
  expect(budget.exhausted).toBe(true);
});
