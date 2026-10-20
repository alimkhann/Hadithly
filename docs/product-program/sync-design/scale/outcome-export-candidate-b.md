# Candidate B: revocable subject-scoped journal export lease

## Usage first

```text
Settings requests export under captured LibraryWriteContext:
  artifact = librarySync.stagePortableExport(context) // private file; never a JSON member array
  librarySync.publishPortableExport(context, artifact, destination)
  // Coordinator releases lease and deletes staging on all exits.
```

Inside that one deep boundary:

```text
capture existing server export + portable partition under captured session
lease = journal.acquireExportLease(subject, deploymentNamespace)
for header in journal.headers(lease, afterKey, limit=50):
  writer.beginEvidence(header.authority, header.checkpoint, expectedTotals)
  for page in journal.evidence(lease, header, ordinal, limit=50):
    writer.writeRows(page.rows); writer.recordPrefixEnd(page.endOfCollectedPrefix)
finish private artifact; verify captured context + lease; publish while lease remains valid
release lease; delete private artifact
```

Rows remain bounded; one small header/page at a time. End-of-collected-prefix and receipt-detail-complete remain distinct exported fields. Export includes all retained statuses, unavailable reasons and category counts, never guesses completion.

## Source-grounded problem

Android LibraryOutcomeJournal is SQLiteOpenHelper with scopes/headers/members; each journal mutation currently uses a short SQLite transaction. Swift GuestDataStore uses GuestOutcomeScope/Header and row-based evidence in a separate ModelContext. Neither current API exposes a supported persistent read snapshot spanning async file writes. Android Settings export currently reads portableState/server JSON into memory, builds JsonObject, serializes the whole object and writes directly to selected URI (`SettingsScreen.kt` export launcher). Swift portableState is in GuestMergePlanner/LibrarySync. Existing journal erasure discovers matching headers beyond partition references. Preserve that orphan coverage.

A true shared cross-platform MVCC snapshot is not the smallest viable change: Android could hold a SQLite read transaction but that retains a reader/database state across awaits and can pin WAL/checkpoint progress; current iOS17 SwiftData API does not provide a verified matching long-lived snapshot contract. Do not claim SQLite snapshot APIs or copying SwiftData's backing SQLite files are safe public SwiftData behavior. This candidate instead freezes journal mutation briefly with an explicit revocable lease, holding no database transaction or native mutex across an await.

## Shape

```text
ExportScopeKey = hash(capturedSubject, deploymentNamespace) // excludes current ownerKey
Lease = {opaqueId, scopeKey, generation, expiresAt, processBootId}
ExportArtifact = {privatePath, scopeKey, generation, leaseId, capturedContext,
  state: staging | sealed | publishing}
JournalControl = {scopeKey, generation, activeLease?, erasing: Bool}
```

JournalControl lives outside account partition so a missing partition cannot hide old-owner headers. One lease covers all matching subject+namespace headers/scopes, including owner-key orphans. It never grants access to other subjects or deployments. Internal `withLease`/`validateLease` check exact captured identity and durable generation; request fields do not supply a backend user identity. Capabilities/JWTs are never written to controls, artifacts or logs.

Private store interface: acquireExportLease, nextHeader, nextEvidencePage, validate/renewLease, releaseLease, eraseScope. Coordinator API exposes only stage/publish/cancel export; views do not manage lock stages (per boundary-discipline and minimize-reader-load). Use a short fixed maximum lifetime (for example 30 seconds), not indefinite lease extension; an oversized export times out explicitly and can retry. No successful artifact survives invalidation. Timeout is a product limit, not evidence that all arbitrary exports can finish; large exports may need the mutation-clock or row-snapshot design instead.

## Concrete platform transactions

Android schema migration adds export_controls keyed by subject+namespace with durable generation/lease metadata. Acquire writes one row in a short SQLite transaction. Every page insert, verification checkpoint, header creation, pruning and orphan cleanup checks that scope's lease in the SAME transaction before effects. If leased, ordinary mutations return fixed temporary local-export-busy; collection coordinator backs off without changing pending data/ACK. Reads use separate short transactions, each verifying the unchanged valid lease, so inventory remains stable across insert-before-cursor scenarios. No SQL transaction remains open across output writes or network awaits.

Swift adds a versioned GuestOutcomeExportControl model to the actual container/schema and installed-store migration. All journal write methods are serialized by the existing single store owner; a shared control-check-and-save helper performs lease checks and effects in the same ModelContext save boundary. The lease is persisted, not merely an in-memory boolean. Do not assert safety with multiple independent writer contexts/processes: current code must prove all journal mutations enter that owner, or move them to one dedicated ModelActor before accepting this design. Public SwiftData provides no general compare-and-swap transaction across independent process writers here; unsupported cross-process writes are an explicit blocker. File staging happens after releasing actor execution; no ModelContext transaction awaits file IO.

Read calls must not run verification that mutates headers while leased. Export serializes persisted checkpoint/status exactly as captured; verification pending means verifying, not complete. If existing evidence() performs verifyOutcomeStep, split pure export read from verifying write rather than exempting a hidden mutation from the lease. Acquisition performs no unbounded scan.

## Mutation, cancellation and erasure

Lease acquisition serializes before or after any in-flight journal mutation. Once acquired, no mutation in that subject+namespace commits until release/expiry, except erasure. Header insertion/removal cannot move behind discovery cursor. Scope checks include orphan headers whose old ownerKey lacks an active partition/scope row. A central subject+namespace control lookup is mandatory for all new header writes, not only existing scope generations.

Erasure always preempts: transaction increments generation, clears lease and marks erasing before deleting matching journal rows in existing bounded batches. New readers/publish fail immediately. Native coordinator cancels private export, closes streams and removes staging. A staging registry under the subject namespace records artifact paths; erase enumerates/cleans those artifacts even when partition and header rows are gone. Paths are generated private filenames, not user-supplied. On restart clear expired/other-processBootId leases and remove private staging files before admitting exports; orphan registry/files are discovered by bounded directory paging. Do not leave raw subject text in filenames. After completed erasure, remove private control metadata once stale writers are ruled out by process/session fences; late callbacks cannot recreate a control/partition.

Account switch invalidates captured export context, cancels writer and deletes staging without erasing the old owner's journal. Cancellation in either native runtime enters cleanup; Android must not swallow CancellationException. Failed release is safe: persisted lease expires and restart sweeps it. Missing control/erasure generation is an invalid lease, never automatic lease recreation.

## Artifact and publication boundary

Preserve the entire existing sanitized server/partition document and exact user strings. Structurally remove provider-passage/capability fields using typed key filtering; do not substring-rewrite serialized JSON or note contents. Stream a new journalEvidence array into the private file rather than adding rows to LibraryExportValue/JsonObject. Existing server/partition memory scale remains open; bounded journal streaming does not fix those producers.

Seal only after every discovered matching header and its collected row prefix was written and lease/session remain valid. Recheck context and lease before publication and between bounded destination writes. Keep lease valid through final write/close, then validate again before announcing success. Erasure invalidates publication even if a final file close raced. Dispose of canceled artifacts in all cases.

There is an unavoidable platform limit: Android arbitrary SAF destinations do not guarantee atomic rename, rollback or deletion after a mid-copy revocation; iOS share handoff likewise cannot revoke bytes another application already accepted. Private staging can guarantee no partial artifact is offered BEFORE publication, not erase external bytes after handoff. For strict “no partial publishable artifacts on cancellation” choose a destination supporting create-temp+atomic commit+delete, or retain current destination flow as an explicit unresolved gate. A lease cannot fix remote provider semantics. Do not claim strict external revocation by checking only at start/end. Parent should prefer the mutation-clock design if it also states this same publication limitation honestly.

## Failure table

| Event | Required result |
| --- | --- |
| Insert/remove before lease | Included/excluded according to lease acquisition order. |
| Insert/remove/verify/prune during lease | Busy/backoff, no journal mutation; export stable. |
| Erasure between header pages | Generation revoked, abort/delete staging, no success. |
| Lease expires during stream | Next read/write-publication check fails; discard staged file. |
| Reopen after process death | Expired/foreign-boot lease removed; orphan artifact swept; export restarts. |
| Older owner orphan header | Included only for same captured subject+namespace. |
| Session switch after server fetch | Captured context fails; local export not published. |
| Checkpoint says partial/unavailable | Export all available facts and explicit status/totals, never complete label. |
| Storage full/output failure | Close/delete private artifact, release lease; retain journal/partition data. |

## Tradeoffs and alternatives

- Accept temporary paused journal collection/verification/pruning in exchange for a stable inventory without long database transactions or copying all identities. Limit the pause and never block erasure.
- Accept installed schema migration and one centralized mutation guard; forgetting one mutation path invalidates the design. Enumerate current store write/verify/erase APIs and enforce through a single helper, not a checklist alone.
- Mutation-clock retry fence avoids paused writes and native lease recovery, but exports can repeatedly fail under constant collection. It is likely the smaller base if centralized atomic clock bumps already fit current source.
- SQLite read transaction is viable only with explicit bounded lifetime and lock/WAL tests; cannot supply unproven iOS17 SwiftData parity. Rejected as the cross-platform base.
- Copy rows into a temporary snapshot database provides stable reads without pausing collection only if copied under one real source transaction; then copy duration/lock and erasure coverage remain. Rejected for this narrow change.

## Next implementation step and proof

First add a real-store export lease prototype and tests that attempt every existing mutator during paginated discovery. Prove one header inserted lexically before cursor is blocked, verify-step cannot mutate silently, erasure preempts, lease timeout/restart cleans artifacts, orphan headers are included and foreign subject/namespace excluded. Test actual old SwiftData/SQLite installation migration and injected save failures. Use real file writer and parsed exported document to prove exact note preservation and all original fields; assert <=50 rows per read and no journal array accumulation. Exercise cancel/account-switch/erasure at each stage and publication capability limitations with the actual selected document provider. Full A2, settlement/ACK/pruning, server/partition scale, deployment and actual cross-device gates remain open.

## Synthesis decision

Candidate B is viable as a short revocable application-level lease only with one proven journal writer owner and honest destination publication guarantees. Recommend A as base if its atomic mutation-clock path is demonstrably smaller; graft B's pure export reads, artifact registry/orphan cleanup and explicit SAF/share publication limits. No implementation or completion claim.
