# Candidate B: immutable page journal with compact collection checkpoints

## Usage first

```text
LibrarySync receives committed folder manifest receipt:
  collection = store.openOutcomeCollection(capturedOwner, frozenFrame, committed)
  while collection.needsDetails:
    page = transport.outcomePage(binding, collection.boundRequest)
    collection = store.persistOutcomePage(collection, page)
  store.settleCollectedOutcome(collection) // durable recovery/ACK intent, never raw arrays
  coordinator resumes existing acknowledgement

Saved subscription receives owner-tagged snapshot:
  store.observeSavedRevision(owner, snapshot.revision)
  store.pruneSuccessfulOutcomeDetails(owner) // only after durable ACK + revision barrier

export(owner): stream store.exportOutcomeEvidence(owner) into private archive
 erase(subject, namespace): store.eraseOutcomeNamespace(subject, namespace)
```

Views never request pages or interpret collection cursors. `LibrarySync` and its existing real stores hide journal format, crash recovery and paging. No new backend or auth behavior. Existing `settleReceipts` deliberately throws for folderDeletedManifest/folderRestoredManifest on Swift and Android; route those outcomes through this boundary rather than treating manifest presence as successful complete details.

## Shape

```text
CollectionKey = hash(serverOwner, capturedSubject, appNamespace, localInstallationKey,
  streamSequence, batchId, commandDigest, operationId, operationRevision,
  receiptDigest, manifestId, manifestGeneration, phase)

CollectionHeader = {key, schemaVersion, boundIdentity, exactManifestTotals,
  committedSavedRevision, frozenOriginalReference, state}
Checkpoint = {key, nextOrdinal, receivedRows, categoryCounts, lastPageHash,
  terminalVerified, settlementState, ackObserved, savedRevisionObserved}
PageFile = {schemaVersion, key, startOrdinal, nextOrdinal, rows[<=50],
  immutableTotals, terminal, priorPageHash, contentHash} // total encoded <=64KiB
CollectionState = collecting | complete | unavailable(reason) | conflicting(reason)
EvidenceHandle = {collectionKey, classification, availableOriginalReference}
```

Identity fields are compared exactly, not trusted merely because a directory hash matches. Query sends binding plus installation/sequence/batch/digest/receipt proof and phase/manifest identity; server derives JWT owner and verifies the committed proof. Delete pages bind immutable original identity set even if later restore dispositions change. Restore pages are consumable only after visibility-flip completion; totals/dispositions must be frozen. The exact page DTO is generated from the parent's actual server boundary; this sketch does not invent acceptance of an unpublished shape.

Use monotonically increasing ordinal continuation, never a locally guessed “next 50.” Require expected start, next ordinal progression, unique contiguous row ordinals, <=50 small identity facts and <=64KiB encoded response; returned immutable totals must exactly match the bound receipt/header on every page. Final completion requires terminal marker, next ordinal==exact count, cumulative category totals==immutable manifest totals and no gaps. Zero-count completion requires a valid empty terminal proof. A short page is not terminal. Unknown categories/identity mismatch stop collection without ACK; original intent and available pages remain recoverable.

## Storage and module map

One native `OutcomeJournal` owned by GuestDataStore, backed by app-private files on both platforms. iOS uses Application Support with appropriate data protection; Android uses app-private directory and AtomicFile/rename discipline. The existing SwiftData partition row and Android JSON state hold only a compact EvidenceHandle/collection settlement reference, not member arrays or per-page path arrays. File layout is deterministic:

```text
outcomes/<subject+namespace digest>/<owner digest>/<collection key>/
  header.json           immutable, small; includes captured subject/namespace identity
  checkpoint.json       bounded atomic replacement
  pages/0000000000.json  immutable, <=64KiB
  ...
  settlement.json       compact durable decision + exact proof identity
```

A subject/namespace directory has a persistent erasure generation/tombstone, independent of partition presence. All filenames are derived from validated digests/ordinals, never supplied paths. Header and each page identify captured subject+namespace; no capability/JWT is persisted. Directory enumeration is paged/batched, not loaded into an unbounded array. Disk quota failure is a fixed storage failure that pauses collection; never drop originals or ACK to escape it. Local backup policy follows current private sync data policy; available recovered files remain owner-scoped.

`OutcomeJournal` owns `open`, `persistPage`, `reopen`, `streamEvidence`, `prune`, `eraseNamespace`. GuestDataStore exposes only high-level collection/settlement methods to the coordinator, so callers cannot perform an ACK before evidence persistence. Transport remains in existing LibrarySync. Generated wire models remain separate from file envelopes (per boundary-discipline). No second queue or generic persistence framework.

## Page commit and exact duplicate behavior

Under the existing owner store actor/mutex and captured erasure generation:

1. Validate response identity, row bounds, exact ordinal, immutable totals and preceding page hash.
2. Encode deterministic envelope; if final ordinal file exists, compare canonical full content hash AND decoded identity/content. Identical duplicate returns current state without double-counting. Different content at the same ordinal is immutable-evidence conflict, never overwrite; preserve incoming conflict evidence in a separate bounded file and park with reason. Repeated identical conflict need not append another file.
3. Write a uniquely named temp file in the same directory, synchronize its bytes, rename atomically to final file, synchronize directory metadata as supported. Rename is create-if-absent under lock, not overwrite. Recover temp files by validating header/bounds; never count them as committed.
4. Atomically replace and durably sync the constant-size checkpoint advancing counts/nextOrdinal. If checkpoint write fails, page remains valid and collection retries/reopens. Do not ACK.

On reopen, verify checkpoint's last page and extend forward over valid next ordinal filenames. A checkpoint cannot outrun its synchronized page under the required ordering. If missing/corrupt, rebuild counts by sequential bounded page reads and hash-chain validation; recovery can take many steps but each step has bounded memory/work. Never infer a page's category from a filename. Conflicting duplicate data is retained privately, not logged.

## Cross-store settlement and crash replay

Android's present JSON AtomicFile and iOS SwiftData JSON blob cannot atomically transact with external page files. Use ordered idempotent commits rather than claiming a distributed transaction:

1. Journal pages/header/checkpoint become complete or explicit unavailable evidence, durable first.
2. Persist compact settlement.json containing exact receipt proof, needed recovery classification and original-reference binding. Unavailable means result details were not obtainable; it never asserts collected subset completeness.
3. Existing store settlement transaction validates the same frozen frame/receipt, retains original source for partial/unavailable/conflicting cases, adds compact EvidenceHandle, then writes its durable ACK intent and removes only that exact frozen revision.
4. After restart, settlement.json can replay step 3 only if exact still-existing captured partition/frozen identity matches. Already settled is idempotent. Erased partitions are never recreated. No matching frozen frame leaves an orphan evidence handle classified historical; it is retained/exported, never guessed accepted.

Crash before step 2 repeats collection. Crash between 2 and 3 replays settlement. Crash after 3 follows existing persisted ACK. Lost ACK response retries existing exact acknowledgement. A same-ID/different-command fork cannot attach the old journal: command/receipt digests are part of CollectionKey and exact matching; original divergent source remains historical recovery.

The page path does not rewrite the Android whole-file JSON or iOS partition on every page. Only bounded sidecar checkpoints change while collecting. Final existing settlement still rewrites its current partition blob, which may already be large; this is an explicitly retained whole-file native-scale limitation, not evidence that storage is fully bounded end-to-end. Splitting existing Saved cache/pending/recovery is a separate migration gate; no growth proportional to collected members is added to that blob.

## Unavailable, partial and projection behavior

If proof/details unavailable is a server-defined immutable response, persist the reason, expected totals, exact receipt identity, all collected pages and original intent before settlement. Do not synthesize missing identities or label a partial subset as complete. Transient network errors leave collection open and retry with bounded backoff. Invalid/conflicting pages preserve evidence and pause rather than ACK arbitrary data. If server permits terminal unavailable settlement, it must be explicit in the receipt contract; otherwise keep ACK pending and surface fixed recoverable sync failure. No fabricated terminal state avoids an incompatible producer.

Successful complete manifest receipt can become a confirmed compact change with its committed Saved revision. Existing native barrier (`observe`/confirmed pruning in partition state) prevents optimistic restoration from overriding a Saved snapshot at or beyond that revision. Do not hydrate full collected identity arrays into `confirmed` or guess restored rows from the local command. Before that revision arrives, retain the previous authoritative projection plus a pending transition indicator; let authoritative snapshot determine actual membership. Journal evidence supports recovery/export, not another competing Saved state. Any newer authoritative revision dominates the collected historical result.

## Success pruning and retention

Only prune all-success detail pages after both ACK is durably confirmed and an owner-tagged authoritative Saved snapshot revision >= committedSavedRevision has been durably observed, with matching session/owner guards. Write compact prune authorization marker first, then delete page files in bounded batches. Reopen resumes deletion. Keep header/compact proof until references no longer require it, then delete directory; a crash cannot turn retained recovery into success. Partial restore, unavailable proof/details, conflicts and available losing originals remain recovery/export data until explicit owner erasure or a separately approved retention policy. A successful delete's original identity evidence may still be required by an unexpired local undo/recovery reference; pruning must additionally check those references, not just ACK+Saved revision.

No unlimited-retention claim: disk-full pauses sync and leaves a visible recoverable error. This task introduces no silent retention eviction or mandatory conflict queue. Later lifecycle/retention design must address long-lived recovery; ordinary success pages do not accumulate forever.

## Owner erasure, orphans and complete export

Erasure takes captured subject+namespace, persists tombstone/new erasure generation before partition/file deletion, invalidates active journal writers and checks generation immediately before final rename/checkpoint/settlement. Actor/mutex serializes those writes with erasure. Clean all matching owner directories by bounded enumeration, including temp pages, conflict files, unreferenced headers and orphan settlements when no partition row exists. Tombstone survives partition erasure and restart until all sweeps complete; stale callbacks cannot recreate directories. Account switch merely fences rendering/work and preserves the old owner's evidence; it is not erasure. A cleanup worker must never infer ownership from current Clerk session.

Export discovers journal roots by captured owner/subject/namespace rather than partition references alone. Stream header, exact status, pages (including partial facts), conflict envelopes, compact settlement/prune state and locally available original source into the private export. Export runs under snapshot/generation fence or copies a bounded manifest inventory with continuation so concurrent prune cannot remove required files; if a required file vanishes, fail export explicitly rather than report complete. Owner recovery evidence remains private and never enters diagnostic logs. Export/erase must be wired to existing user-facing paths before claiming complete coverage.

## Tradeoffs and alternatives

- Accept filesystem ordering/checkpoint recovery complexity in exchange for bounded immutable page writes and minimal change to existing native partition schemas.
- Accept slow bounded journal replay after damaged checkpoint in exchange for a compact replaceable checkpoint without a per-page index table.
- Row DB (SwiftData entities / Android SQLite): stronger transaction/query/pruning tools and less cross-store reasoning; larger current Android storage migration. Prefer that candidate if it demonstrably covers orphans/erasure and avoids duplicate store ownership with a smaller reliable diff.
- Whole partition arrays: simplest apparent change, but every page rewrites all accumulated members and creates unbounded partition serialization; rejected for this task. Current blob remains only a known pre-existing scale gate.

## Proof seams and synthesis recommendation

Actual native real-store tests: 0/1/50/51/many-page collections; count/category mismatch; reordered/gapped/duplicate/conflicting pages; cross-owner/installation/sequence/digest rejection; delete versus restore immutable binding; server unavailable before/after partial collection; disk/checkpoint/rename failure; reopen after each ordered commit; lost ACK; newer Saved revision before/after collection; prune interruption; erase with partition absent and orphan/temp/conflict files; stale writer cannot resurrect directory; complete export under prune race. Assert per-page file<=64KiB, <=50 rows, constant-size checkpoint, no accumulated identity arrays in partition, and exact totals before complete. Backend fixture tests belong to the parent's actual page producer; native mocks alone do not prove proof binding.

Recommend this candidate as base only when bounded page persistence must land without migrating the entire Android store. Graft row-DB candidate's explicit recovery enumeration/export tests. Preserve current public producer, old installed/schema migration, whole-file cache, authenticated cross-device and read/export cutover gates until implemented and verified. Candidate only; parent selects synthesis.
