# Saved private fact page implementation review

Read-only review of the selected contract and current implementation: `lib/librarySavedFacts.ts`, public wrapper/binding creation in `librarySync.ts`, `librarySyncIdentity.ts`, schema binding field, `librarySavedFacts.test.ts`, baseline `readSavedSnapshot`, membership resolver, version helper, and installed Convex pagination definitions/client handling. No repository changes, deployment or private-account calls performed. Tests were inspected; this reviewer did not rerun the parent's focused suite.

## Finding requiring correction

**[P1] Do not consume or sign a continuation for a `SplitRequired` source page.** `backend/convex/lib/librarySavedFacts.ts:94–112` reads `page`, `isDone` and `continueCursor` without inspecting `pageStatus`. Installed `convex/src/server/pagination.ts:50–54` explicitly says `SplitRequired` means the returned page might be incomplete. Installed `convex/src/react/use_paginated_query.ts:343–347` accordingly refuses to include that incomplete page while splitting. The endpoint configures `maximumBytesRead`, precisely a documented trigger for incomplete/split pagination, so this is relevant even with `numItems:1`.

Current behavior can sign a cursor past facts omitted from an incomplete page, or advance to the next source and eventually issue a completion token from incomplete private coverage. The smallest truthful first-slice correction is explicit unavailability before processing any `SplitRequired` result, with no `next` or `completion`. A proper bounded split-range chain is another option but substantially more contract work. Do not infer that the local fake paginator's ordinary output proves this cannot happen in the hosted runtime.

Add injected paginator-result regressions for an empty incomplete page and a partial nonempty incomplete page, including `isDone:true`, showing neither yields facts/next/completion and retry stays at the input position. A split-recommended complete page is distinct; it can remain consumable if the SDK contract guarantees it is complete. Parent was notified of this finding immediately.

## Sound parts of the implementation

- The cursor key is random, private, optional on existing binding rows, generated only for new manifest bindings. No public-capability-derived signing fallback is present. Old absent-key rows require reopen.
- JWT identity resolves the owner before traversal. HMAC verification and explicit owner/binding checks precede source queries. Signed source/cursor/ordinal/version fields prevent caller-selected phase skipping or cross-owner cursor use.
- Requests and token sizes are checked before decoding and database traversal. Cursor parsing rejects extra fields, bad source/complete shapes and unsafe ordinals/revisions.
- Saved revision checking happens in the same query transaction as page traversal. Completion replay rechecks the current private revision. Assembly identity is stable for binding plus revision, input/start are echoed, and completion counts describe private facts rather than joined public rows.
- Exactly one source paginator appears per request. No whole-library collect, per-hadith legacy collect or public hadith get appears in the module's call graph. Effective membership is delegated to the existing bounded, ownership-checking resolver. Primary pages over one row throw instead of silently exceeding the contract.
- Private canonical facts retain references whose hadith documents are absent. Public summaries are excluded. No new consumer or old joined snapshot silently adopts this meaning.
- Oversized returned source rows produce explicit unavailability before consuming a cursor. Response serialization includes envelope and cursor overhead in the 64 KiB check.
- Existing whole-snapshot endpoint and native production consumers are unchanged. Account erasure already removes binding rows; adding the key creates no extra retained table family.

## Verification gaps to preserve honestly

The inspected 11-case focused suite covers actual 501 unique items plus 501 duplicate legacy facets, one missing target, owner/private isolation, timestamp/tie fixture parity, cursor tampering and binding swaps, three oversized source types, backfill version restarts, expiry, erasure and secret exclusion. It is meaningful first-slice evidence, not native or hosted rollout proof.

The existing read-spy assertion exercises only a canonical item without membership dependencies. The selected contract also requires measured upper read bounds for staged membership/header/destination and deleted-folder/tombstone paths, plus explicit assertions of the paginator's configured limits. Parent reports adding membership/no-version normalization, midphase write and malformed-pointer cases; review their final evidence rather than treating their intent as completed coverage. Fake paginator pagination-limit behavior must remain a hosted/actual runtime gate.

Canonical duplicate last-row precedence, legacy-only initialization/equal-time source order and full native deterministic row merge are not demonstrated by the one canonical fixture assembler. This backend transport preserves the source identities/order needed to implement them, so these are follow-through requirements, not reasons to add a server materialized generation now.

## Disposition

Fix the `SplitRequired` consumption issue before accepting the server boundary. I found no additional concrete owner, signature, Saved-revision or public/private-domain defect in the inspected implementation. The first backend component can be accepted after the fix and authoritative test/typecheck evidence, with native durable assembly/activation, throughput, installed-client cutover, full export, whole-partition scale, hosted pagination/auth and physical persistence gates remaining explicitly open.
