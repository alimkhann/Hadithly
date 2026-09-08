/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import { normalizeHadith } from "./lib/sunnahNow";

const modules = import.meta.glob("./**/*.ts");

describe("canonical content cache", () => {
  test("shares one license record and never downgrades verified terms", async () => {
    const t = convexTest(schema, modules);
    const items = [
      normalizeHadith("bukhari", { id: "1" }),
      normalizeHadith("bukhari", { id: "2" }),
    ];

    await t.mutation(internal.hadiths.upsertPage, { items });
    const license = await t.run(async (ctx) =>
      await ctx.db.query("licenseRecords").unique(),
    );
    expect(license?.terms).toEqual({ kind: "unverified" });
    await t.run(async (ctx) => {
      if (!license) throw new Error("Missing license fixture");
      await ctx.db.patch(license._id, {
        terms: {
          kind: "verified",
          licenseName: "Fixture license",
          licenseUrl: "https://example.test/license",
          permitsDisplay: true,
          permitsRedistribution: false,
          permitsOfflineDistribution: false,
          verifiedAt: 2_000,
        },
      });
    });

    await t.mutation(internal.hadiths.upsertPage, { items: [items[0]] });
    const licenses = await t.run(async (ctx) =>
      await ctx.db.query("licenseRecords").collect(),
    );
    expect(licenses).toHaveLength(1);
    expect(licenses[0]?.terms).toMatchObject({
      kind: "verified",
      licenseName: "Fixture license",
    });
  });
});
