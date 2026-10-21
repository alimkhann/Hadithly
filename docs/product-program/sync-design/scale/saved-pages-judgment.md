# Bounded Saved pages: independent architecture judgment

Read in full: frame.md, grounding.md, candidate-a.md and candidate-b.md. This is a design review, not execution evidence. No repository implementation, cloud operation, account operation or additional delegation performed.

## Recommendation

Use **candidate A's stateless private fact traversal as the base**, and **candidate B's explicit private-domain versus eventual public-summary split** as a required graft. Do not introduce a global corpus epoch for this private Saved boundary. Do not materialize a second private Saved library on the server unless measured native assembly or throughput demonstrates that the simpler boundary cannot meet product requirements.

This recommendation is for the target architecture and its first independently provable component. A one-row backend endpoint is a useful bounded prerequisite; it is not a usable large-library cutover or proof that A2 is complete. A's smaller lifecycle wins narrowly over B's simpler merged-row native input. The implementation must still follow through with durable native row assembly on both platforms and measure end-to-end loading.

## Scores

Scores are 1–5 against the frame's five criteria; higher is better. Neither proposal receives full bounds/completeness marks before its stated contracts are implemented and exercised.

| Criterion | A | B | Reason |
| --- | ---: | ---: | --- |
| Whole-source/read/wire bounds | 4 | 4 | Both explicitly bound source rows and dependencies, reject oversized values and avoid per-hadith legacy collect. Actual read accounting and SDK pagination behavior remain to be demonstrated. B adds bounded accumulator and cleanup reads/writes. |
| Owner/revision/cursor/completion truth | 4 | 4 | A signs binding/owner/revision/phase/ordinal continuations and requires native chain validation. B checks owned generation, contiguous rows and finish, but adds scheduled generation invalidation/cleanup races. Neither is yet executable proof. |
| Canonical/legacy/effective-membership parity | 4 | 4 | Both identify timestamp/tie asymmetries, duplicate canonical behavior, effective membership and missing-target private retention. Exact legacy order, normalization interleavings and every writer's revision boundary still need tests. |
| Native integration simplicity and ACK barriers | 3 | 5 | A requires duplicate folding and ordered source semantics in two native data layers. B supplies a merged private generation. Both correctly prohibit partial activation; B states independent public hydration more decisively. |
| Smallest deep module and executable interleaving proof | 5 | 2 | A adds a private cursor secret to an existing bounded binding and one source traversal module. B creates heads/rows/folders, scheduler transitions, rebuild/cleanup/expiry/erasure and write amplification before native cutover. |
| Total | **20/25** | **19/25** | Choose A plus the required domain/barrier graft below. |

## Required grafts and corrections

1. **Adopt B's private Saved domain without public summaries.** A complete private generation must retain all private rows, including hadith references that are currently missing or whose public summary cannot be fetched. Public hydration returns explicit found/missing/unavailable independently and may change at the same private revision. Its failure must not hold a legitimate private receipt barrier indefinitely. This is an explicit native model migration; it cannot be represented by constructing the old joined `SyncSavedSnapshot` with missing rows and declaring its version complete.
2. **Keep A's server-private per-binding signing field optional for old stored rows.** New bindings generate the field locally. Old bindings without it require an explicit reopen result, never a public-capability-derived fallback. JWT ownership, binding expiry and the signed cursor must be validated before a source query. Neither the key nor its derivation appears in DTOs, logs or account exports.
3. **Make the continuation chain explicit in the wire and staging contract.** The native assembler captures a root assembly identity and binding, accepts only the exact expected input cursor/phase/ordinal, and stores each response idempotently. A terminal proof is valid only after the contiguous persisted prefix includes every source phase. Empty split pages advance the server cursor without inventing a fact ordinal; repeated/nonprogressing cursors fail explicitly. Counting received rows or trusting a terminal token alone is insufficient.
4. **Preserve source encounter order until deterministic merge is finished.** Replayed source IDs replace their exact staged fact; they do not append. Canonical duplicates retain last-source-row precedence, equal-time legacy notes retain first encounter precedence, and stable aggregate sort ties require explicit encounter keys. A Map implementation used only by a test is not proof of the production native merge.
5. **Treat read and wire budgets separately.** A legal large database row is read before application rejection. Document a conservative constant worst-case read budget including binding/user/version and every membership dependency. UTF-8 response limits include signed cursor/envelope overhead. Local instrumentation must record the actual query/get graph and assert no whole collect or public hadith get; `convex-test` ignoring paginator limit options cannot prove hosted enforcement.
6. **Retain the old endpoint unchanged during development.** Existing binaries continue using the joined whole snapshot until native cutover and installed-client behavior are proven. Its continuing unbounded reads remain an open gate, not a compatibility victory or reason to close scale work.

## Rejections

- Reject A's suggested future global corpus clock as the default integration path. It would couple private ACK progress to all public corpus mutations and expand the writer audit without being necessary for private Saved correctness. Consider it only if a separate product requirement truly demands an atomic public corpus snapshot.
- Reject B's durable server generation for the current base. Its strongest benefit is hiding native merge complexity, but current evidence does not justify extra retained private rows, rebuild cleanup, account erasure integration and scheduler lifecycle. Preserve it as an alternative if measured native assembly or throughput is unacceptable, not as a second simultaneous implementation.
- Reject paginating an already collected old snapshot, per-hadith duplicate collects, per-device durable server copies, partial legacy migration, truncated private notes, missing-target row deletion and any old-shaped snapshot carrying a complete version before all private facts are installed.
- Reject claims that one-row scaffolding closes product throughput, whole-partition cache/pending growth, full account export, installed SDK/auth/cross-device behavior or physical persistence failure gates.

## Acceptance evidence for the first slice

The parent-reported revision repair (`c7b98f7`, 487 backend tests) is a prerequisite, not evidence that the new page API exists or is bounded. The first component should provide actual validators, optional private binding signing key, page boundary and executable adversarial tests while leaving native production callers unchanged.

Traverse more than 501 unique private items and more than 500 duplicate legacy facets with real database fixtures; instrument each request's reads and UTF-8 bytes; test the fold against baseline semantics on bounded fixtures; retain missing canonical targets without any hadith get. Exercise all source phase boundaries, empty/split continuations, exact replay, tampered cursors, wrong owner/binding, expired/reopened bindings, oversized row/cursor, malformed dependency pointers and Saved mutations before every page/final check. Include membership materialization that preserves visibility, and revision-changing folder commit/migration interleavings. No malformed/oversized result can produce completion or advance staging as though that source row were consumed.

Then implement native durable private generations and deterministic folds on both platforms, with crash/reopen, account-switch, stale-session, duplicate/gap/reordered page, store-failure, atomic activation and ACK/retention barrier checks. Public hydration must remain separately refreshable and preserve private missing-target facts. Measure actual multirow/large-library completion time and memory before changing production subscriptions. Whole-account export and whole-file pending/cache storage remain explicit separate work.

**Decision:** A as base; B's private-domain/public-hydration/barrier separation is mandatory. Both candidates remain proposals until their selected behavior is implemented and verified.
