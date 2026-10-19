/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());

test("expired erasure preparation grants are removed in bounded resumable pages without reviving the subject", async () => {
  vi.useFakeTimers();
  const t = convexTest(schema, modules);
  const owner = t.withIdentity({ subject: "maintenance-owner", tokenIdentifier: "fixture:maintenance-owner" });
  const first = await owner.mutation(api.users.prepareAccountDeletion, {});
  await owner.mutation(api.users.deleteCurrentUser, { authorization: first.authorization });
  const retry = await owner.mutation(api.users.prepareAccountDeletion, {});
  const now = Date.now();
  await t.run(async ctx => {
    for (let index = 0; index < 205; index++) await ctx.db.insert("accountDeletionAuthorizations", { subjectDigest: `expired-subject-${index}`, digest: `expired-digest-${index}`, validUntil: now - 1 });
    await ctx.db.insert("accountDeletionAuthorizations", { subjectDigest: "boundary-subject", digest: "boundary-digest", validUntil: now });
    await ctx.db.insert("accountDeletionAuthorizations", { subjectDigest: "future-subject", digest: "future-digest", validUntil: now + 60_000 });
  });
  expect(await t.mutation(internal.users.pruneExpiredDeletionAuthorizations, {})).toEqual({ deleted: 100 });
  expect(await t.run(ctx => ctx.db.query("accountDeletionAuthorizations").withIndex("by_expiry", q => q.lte("validUntil", now)).collect())).toHaveLength(106);
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await t.run(ctx => ctx.db.query("accountDeletionAuthorizations").collect())).toHaveLength(2);
  expect(await t.run(ctx => ctx.db.query("accountDeletionMarkers").collect())).toHaveLength(1);
  await expect(owner.mutation(api.users.ensureCurrentUser, {})).rejects.toThrow("ACCOUNT_DELETION_PENDING");
  expect(await owner.mutation(api.users.deleteCurrentUser, { authorization: retry.authorization })).toEqual({ subject: "maintenance-owner", deleted: false });
  expect(await t.mutation(internal.users.pruneExpiredDeletionAuthorizations, {})).toEqual({ deleted: 0 });
  expect(await t.run(ctx => ctx.db.query("accountDeletionAuthorizations").collect())).toMatchObject([{ digest: "future-digest" }]);
});
