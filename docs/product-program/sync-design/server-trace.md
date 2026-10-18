# A2 server acknowledgement trace

Read-only source evidence, October 18. No cloud, identity, or cross-device execution. Scope: merge admission, conflict rules and readback.

## Ownership and atomicity

`backend/convex/guestMerge.ts:88-102` calls `requireIdentity`, resolves `users.by_clerk_id`, and errors if ensureCurrentUser has not created the owner. `backend/convex/lib/identity.ts:34-58` derives Clerk subject and tokenIdentifier from `ctx.auth.getUserIdentity`; merge arguments contain no user identity. Every private write uses that resolved user. Valid foreign hadith IDs name public content, not another user's Saved row.

One mutation transaction includes folder resolution, legacy writes, canonical Saved materialization and position writes. Validation or thrown errors abort the transaction; an exception is not a partial acknowledgement. A lost response after commit remains ambiguous, requiring idempotent resend. Current add/note/position semantics mostly converge, but membership replay can overwrite newer cloud membership.

## Exact decisions

- Folders (`guestMerge.ts:104-123`): trim/NFC/lowercase normalized name, reuse owner's matching folder or insert. Local IDs only map within request. Empty/control/overlong name throws (`library.ts:534-543`). No folder counts or receipt are returned. Duplicate localId aliases overwrite the request map. Name collision intentionally conflates local folders with the same normalized name; first-created server display name wins.
- Legacy bookmarks/favorites (`guestMerge.ts:125-218`): missing hadith and existing same-owner facet both increment `Skipped`; otherwise insert. Searches collect all owner rows per incoming facet. A skipped missing target is not acknowledged preservation; skipped existing facet generally is preservation of the add, even when createdAt differs.
- Legacy notes (`guestMerge.ts:156-195`): missing hadith skips; existing.updatedAt >= incoming.updatedAt skips; otherwise patch text/update time or insert. Equal timestamp with differing text keeps cloud text. `notesSkipped` conflates duplicate, conflict and absent target. Clock timestamps are conflict policy, not evidence of byte equality.
- V2 Saved (`guestMerge.ts:220-306`): no facet or missing hadith skips. `materializeLegacySavedItem` (`library.ts:587-628`) folds earliest add timestamps and strictly newer legacy note into the canonical item first. Incoming bookmark/favorite preserve earliest add time. Incoming note needs both content and noteUpdatedAt and wins only strictly later. Missing noteUpdatedAt can silently leave text unapplied. Omitted facets mean preserve existing, never delete.
- Membership in V2 uses request folder map if resolvable, otherwise retains existing folder. Supplied mapped folder replaces existing membership without comparing folderUpdatedAt. It can overwrite a newer cloud move on retry. A missing mapping can be silently ignored while another facet makes the row count as merged. Omitted folder means preserve; there is no explicit remove-folder operation.
- `savedItemsMerged` counts rows with any detected change, not applied facets. A winning bookmark can coexist with a losing note and ignored membership. `savedItemsSkipped` includes unchanged values and note conflicts, and cannot acknowledge every facet. Materialization itself can write before this count is determined. V2 changes dual-write legacy tables, with notes only when incomingNoteWins.
- After V2, every legacy target is materialized (`guestMerge.ts:308-317`), including missing targets: `ensureSavedItem` creates a facetless Saved row without validating hadith existence. Readback filters missing hadiths, so “row exists” is not successful preservation.
- Positions (`guestMerge.ts:319-363`, `library.ts:1045-1143`): semantic input parsed, exact provider anchor resolved, otherwise whole provider collection collected and nearest permissible anchor chosen through `resolveReadingPosition`, converted to legacy position. No candidate skips. Legacy input resolves its hadith; incoming collectionSlug is not authoritative. `applyReadingPosition` keys owner + collectionSlug (not provider); cloud updatedAt >= incoming keeps cloud. Else writes complete resolved position. `progressSkipped` conflates absent target, duplicate and newer/equal cloud winner. `progressMerged` may mean a different, resolved anchor was stored; does not promise exact original semantic position.

## Counts and consumer readback

Mutation returns ten aggregate merged/skipped counters and no identities/revisions (`guestMerge.ts:365-377`). Both native GuestMergeResult DTOs omit Saved counters (`ios/Hadithly/App/AppEnvironment.swift:36-45`, `android/.../core/data/GuestStore.kt:145-155`). Neither result enumerates folders, membership, accepted note versions, resolved anchors or rejected targets. The return is a commit summary, not an all-accepted receipt.

`library:listSavedSnapshot` (`library.ts:837-895`) derives JWT owner, combines canonical and legacy facets, picks earliest bookmark/favorite and strictly newer note, joins hadith summaries, removes missing-target items. It returns canonical membership and folders, so legacy writes alone cannot prove membership preservation. `listReadingProgressDetailed` (`library.ts:899+`) derives owner, joins position/hadith and can re-resolve missing anchors. Queries are authenticated, but native emissions themselves currently carry no session epoch: native subscriptions apply directly (`ios/.../UserLibraryModel.swift:428-439`, `android/.../UserLibraryModel.kt:363-389`). Successful merge return does not prove those subscriptions read the intended account or that the other device rendered it.

Both sign-in consumers unconditionally clear real guest persistence after mutation success (`AppEnvironment.swift:312`, `SessionManager.kt:142`). Counts cannot justify that cleanup even without the parent's demonstrated snapshot/edit race. A rejected target, losing note, unresolved folder, newer local change or sanitized-out draft can disappear.

## Existing evidence and gaps

`backend/convex/readingPositions.test.ts:265-307` merges semantic position then older legacy position and reads `listReadingProgressDetailed`; asserts semantic position survives. Its following test exercises vanished-anchor convergence. Repository search found no other backend test references to mergeGuestData or its skip counters. Native `GuestMergePlannerTests.swift` and `GuestMergePlannerTest.kt` cover payload formation, while the parent reports real-storage race diagnostics. None proves per-facet acknowledgements, deletion handling, folder replay conflicts, account epochs or actual two-device sign-in.

## Minimal truthful acknowledgement contract

Use one typed operation per facet/folder/membership/position, each with an opaque request-scoped operationId and local revision. Request carries batchId but never owner ID. Return one receipt for every operation, echoing operationId and submitted revision:

- `preserved`: inserted/applied, or exact semantic value already present; safe to acknowledge only the matching local revision.
- `conflict`: cloud winner differs, including equal timestamp/different text, newer note/position or protected newer membership. Keep recoverable local copy; do not translate this to accepted. Return minimal winning version metadata/value privately if needed for reconciliation, never log content.
- `rejected`: missing target, missing folder dependency, invalid item, or unresolved position; retain draft with reason. Request-wide structural/auth errors throw and acknowledge nothing.
- For position fallback, return resolved position explicitly as a conflict/transformation requiring domain policy; do not call original value preserved. If product explicitly accepts nearest-anchor migration, encode `resolved` with resolved value and retain original until matching revision reconciliation completes.

For accepted folder creation/reuse return local operationId -> server folderId mapping; membership is acknowledged independently. Compare membership revisions/timestamps before overwrite. Use receipt of exact semantic equality rather than raw merged counts for duplicate retries. A status must cover only the submitted facet, never the whole Saved item because another facet changed.

Client cleanup is compare-and-remove against captured revision and session epoch. New local edits survive and enqueue the next bounded batch under the captured account. Never clearAll; never infer acceptance of filtered-out entries. Conflict/rejected data stays in account-scoped recoverable pending storage, without reappearing under another account. Response losses resend same operations; stale account responses do not clear or render another account's data. Local epoch does not replace verified-JWT ownership on server.

Bound operation count/bytes and note size at admission; process bounded dependency-ordered batches (folders before membership), and replace per-item full-owner bookmark/favorite scans with owner+hadith indexes. Cap/explicitly handle position resolution access. Retry only transient transport failures with backoff; conflicts and missing content need reconciliation, not an infinite automatic resend loop. Keep accepted state distinct from observed subscription readback and real iOS↔Android proof.
