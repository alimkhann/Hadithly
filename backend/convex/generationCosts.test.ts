/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

describe("Q1 compact progress counts", () => {
  test("upsert and idempotent backfill preserve counts after removing full outlines", async () => {
    const t = convexTest(schema, import.meta.glob("./**/*.ts"));
    const volumes = Array.from({ length: 50 }, (_, i) => ({ volumeId: String(i), title: "Volume", hadithCount: 20,
      chapters: Array.from({ length: 20 }, (_, j) => ({ title: "Chapter ".repeat(20), hadithCount: 1, firstProviderHadithId: String(i * 20 + j + 1) })) }));
    await t.mutation(internal.collections.upsertOutline, { collectionSlug: "bukhari", volumes });
    const first = await t.query(api.library.listCollectionProgressSummaries, {});
    expect(first.find(x => x.collectionSlug === "bukhari")).toMatchObject({ totalHadiths: 1000, state: "unopened" });
    const sizes = await t.run(async ctx => {
      const outline = await ctx.db.query("collectionOutlines").unique();
      const count = await ctx.db.query("collectionCounts").unique();
      if (!outline || !count) throw new Error("Missing counts");
      await ctx.db.delete(count._id);
      return { outline: JSON.stringify(outline).length, count: JSON.stringify(count).length };
    });
    expect(sizes.count).toBeLessThan(sizes.outline / 100);
    expect(await t.mutation(internal.migrations.materializeQ1CollectionCounts, {})).toEqual({ written: 1 });
    expect(await t.mutation(internal.migrations.materializeQ1CollectionCounts, {})).toEqual({ written: 0 });
    await t.run(async ctx => { for (const row of await ctx.db.query("collectionOutlines").collect()) await ctx.db.delete(row._id); });
    expect(await t.query(api.library.listCollectionProgressSummaries, {})).toEqual(first);
  });
  test("monthly aggregates are erased, never converted into invented event dates", async () => {
    const t = convexTest(schema, import.meta.glob("./**/*.ts"));
    await t.run(ctx => ctx.db.insert("users", { clerkId: "legacy", preferredLanguage: "en", subscriptionTier: "free", aiGenerationsThisMonth: 20, aiGenerationLimit: 20, createdAt: 0, updatedAt: 0 }));
    expect(await t.mutation(internal.migrations.migrateQ1Users, { paginationOpts: { cursor: null, numItems: 20 } })).toMatchObject({ erased: 1, isDone: true });
    expect(await t.mutation(internal.migrations.migrateQ1Users, { paginationOpts: { cursor: null, numItems: 20 } })).toMatchObject({ erased: 0 });
    expect(await t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(0);
  });
});
