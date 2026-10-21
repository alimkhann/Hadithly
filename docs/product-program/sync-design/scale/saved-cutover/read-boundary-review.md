# Bounded Saved read boundary implementation review

2026-10-22. Read-only architect review of current `librarySavedReads.ts`, shared identity helper, Saved facts integration, public query wrappers and13 new actual Convex tests. Applied TypeScript/type-system review guidance. No source/repository edits, cloud/provider/account calls or delegation.

## Result

No concrete ownership, private-fact deletion, silent truncation or query-fanout correctness defect found in the implemented boundary. The three APIs make the intended separation explicit: compact Saved head is an invalidation hint; exact reference and full cached text hydrate a requested private target; neither hydration reply carries a private observed version or proves activation.

## Ownership and missing semantics

`requireSavedReadBinding` first bounds capability UTF-8 bytes, then resolves the verified Clerk identity and matching binding digest, owner, expiry, manifest protocol and Saved cursor-key presence. No user ID argument is accepted. Public wrappers validate hadith IDs as actual `hadiths` IDs. Extracting the helper into Saved facts preserves its existing manifest/key requirement and signed-cursor path; the earlier facts-specific request/cursor limits remain in place.

Hydration admission checks exact `(userId,hadithId)` indexed ownership in canonical savedItems or legacy bookmarks/favorites/notes. It reads no foreign owner's rows and only gets the public target after a matching own source exists. Unsaved, foreign-only and vanished public IDs share the same missing shape, echoing only the caller's own owner ID and requested target. The source query results, private note content and timestamps never enter hydration output.

This is intentionally source existence rather than an additional facet-visibility predicate. It matches the old `readSavedSnapshot` admission, which merges canonical rows and legacy sources before hydration. Missing public metadata does not remove the private source, decrement its count or advance its version. Concurrent removal can make hydration missing before the next private generation becomes active; native must retain the caller's private row until private observation resolves it.

## Actual bounded work and size behavior

- Head performs indexed user lookup, binding lookup and one indexed private version lookup. It neither enumerates Saved nor gets public hadiths. The safe-integer/nonnegative invariant prevents an invalid private counter from masquerading as a valid invalidation hint.
- Hydration performs those auth/binding reads, then at most4 exact indexed `.first()` source checks, then at most1 public document get. There are no `.collect()` calls, joins over all Saved rows, provider requests or unbounded child scans in the new module.
- `.first()` returns an entire matching document, not a projected existence-only field. A legacy/canonical note may therefore consume a full private document read internally even though only boolean existence is used. Work is bounded by fixed document count, not by8KiB reference response size; do not describe8KiB as a database-read bound.
- Available reference/fulltext responses are measured after complete JSON serialization and UTF-8 encoding. Oversize becomes an explicit unavailable discriminant; no substring or truncated route/text is returned. Metadata excludes Arabic/English fields; text preserves exact whitespace, quotes, controls and full cached passages.
- The8MiB text ceiling is an application wire bound, not a hosted Convex performance/transport proof or an authorization to return larger stored documents. The deliberately mocked oversized adapter fixture is labeled beyond hosted-document limits. Actual SDK/transport/device throughput remains its own gate.

## Privacy and rights scope

The new text response reproduces the fields already exposed by native `savedSnapshot` through `readSavedSnapshot -> hadithSummary -> cleanSummary`; it does not add AI/provider generation, offline packages or public unauthenticated access. Old and new native Saved summary helpers do not consult a license record here. That is parity with the old native surface, not proof of display/redistribution rights. Existing rights/release gates remain open, and these APIs must not be cited as a new web/offline redistribution permission. The public canonical-link path has a separate verified-display rule and is not the caller/scope being replaced by this component.

## Practical consumer traps to retain in cutover work

1. Head is invalidation-only; its version cannot prune overlays, settle manifests, ACK or establish the active private read barrier. Its response contains no membership/activation proof.
2. Hydration echoes owner/target but intentionally has no candidate generation or private version. Native callbacks must retain their captured owner/session/action scope/active-handle identity and reject stale results after a switch; server echo alone cannot identify the native generation.
3. A head subscription's binding expiry check runs when the query executes; elapsed wall time alone is not a private data change trigger. Native must use its known binding validity/refresh lifecycle rather than assuming a quiet live head publication independently renews or invalidates credentials.
4. Public changes do not advance Saved head. A one-shot hydrated cache does not automatically become fresh merely because head remains equal. Separate public hydration freshness/missing/retry behavior must remain distinct from private generation completeness.
5. Reference unavailable is distinct from missing and cannot silently discard a private row. Fulltext loading/copy/share must preserve exact source text; the earlier64KiB fact envelope cannot be reused as a passage truncation threshold.

These are contract consequences, not defects in the intentionally separate server boundary.

## Evidence inspected

`/tmp/hadithly-saved-reads-focused-first.log` is terminal:13 actual Convex tests passed. Inspected test bodies exercise compact head query/get shape; Saved vs positions/foreign invalidation; invalid counters; canonical and all3 legacy admission; unsaved/foreign missing without public get; public change/disappearance preserving exact private row/version; full text beyond64KiB including JSON escapes; explicit oversize outcomes; JWT/owner/protocol/key/expiry errors. Query spies plus source inspection establish fixed query count; this reviewer did not run hosted request-limit or native SDK tests.

Accept the local bounded server read component. Production native consumers, active barrier migration, full-cache retirement, UI hydration/Reader exact-target behavior, deployment, physical/cross-device/installed-SDK and recoverable iOS save-failure gates remain open.
