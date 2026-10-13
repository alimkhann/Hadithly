import type { ActionCtx } from "../_generated/server";
import { internal } from "../_generated/api";
import type { DiagnosticOperation } from "./diagnosticsPolicy";

export async function reportFailure(ctx: Pick<ActionCtx, "runMutation">, operation: DiagnosticOperation): Promise<void> {
  if (process.env.DIAGNOSTICS_ENABLED !== "1") return;
  try { await ctx.runMutation(internal.diagnostics.recordFailure, { operation, surface: "backend" }); }
  catch { /* Diagnostics failure must not replace the product's result. */ }
}
