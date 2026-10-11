import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";

const [command = "list", ...args] = process.argv.slice(2);
const url = process.env.HADITHLY_CONVEX_URL;
const token = process.env.HADITHLY_OPERATOR_JWT;
if (!url || !token || !/^https:\/\/[^/]+\.convex\.cloud$/.test(url)) {
  process.stderr.write("Set HADITHLY_CONVEX_URL and a verified Clerk Convex JWT in HADITHLY_OPERATOR_JWT.\n");
  process.exit(1);
}
const client = new ConvexHttpClient(url);
client.setAuth(token);
try {
  if (command === "list") {
    const kind = args[0] ?? "exception";
    if (!["exception", "appeal", "audit", "incident"].includes(kind)) throw new Error("Unsupported case kind");
    const page = await client.query(makeFunctionReference("evidenceOperator:listCases"), { kind, paginationOpts: { cursor: args[1] ?? null, numItems: 25 } });
    process.stdout.write(JSON.stringify(page, null, 2) + "\n");
  } else if (command === "audit") {
    if (!args[0]) throw new Error("Supply the receipt from list");
    process.stdout.write(JSON.stringify(await client.query(makeFunctionReference("evidenceOperator:auditFacts"), { receipt: args[0] }), null, 2) + "\n");
  } else if (["recheck", "suppress", "takedown"].includes(command)) {
    const [caseId, expectedVersion, reason] = args;
    if (!caseId || !expectedVersion || !["rights", "privacy", "unsafe", "incorrect", "policy", "audit"].includes(reason)) throw new Error("Supply caseId, version, and a rights/privacy/unsafe/incorrect/policy/audit reason from the latest list");
    await client.mutation(makeFunctionReference("evidenceOperator:act"), { caseId, expectedVersion, action: command, reason });
    process.stdout.write("Action recorded.\n");
  } else throw new Error("Use list, audit, recheck, suppress, or takedown");
} catch {
  // Do not echo SDK errors: their request context can include auth material.
  process.stderr.write("Operator request failed. Check identity, reason, and the current case version.\n");
  process.exitCode = 1;
}
