# Account-store implementation review

2026-10-22. Read-only review of current uncommitted LibraryLocalStore.kt, GuestStore.kt, LibraryOutcomeJournal.kt and Android test diff against candidate B and the selected migration constraints. No code/repository edits, deployment or gate approval. The parent owns implementation and test execution. This record does not claim the running native job completed.

## Result

The core implementation follows B and removes the permanent cross-store claim boundary. **One concrete P2 transaction-authority seam remains**, described below. Additional migration-specific verification is still required; the current two added cloned-writer tests and updated old fixtures alone do not prove the complete new import protocol.

## P2: artifact validation can race a cloned deletion

`LibraryOutcomeJournal.kt:281-285`, `validateArtifact`, enters a ready-gated SQLite transaction but only checks the artifact's stored subject and namespace. `GuestStore.validateOutcomeExportArtifact` first performs `assertOutcomeOwnerActive` in a separate transaction, then calls this method. Unlike `checkFence`, `captureExportFence`, Saved active reads and the newly guarded journal producers, artifact validation does not recheck account/deletion authority inside its own transaction.

Concrete schedule:

1. A's facade precheck accepts the current owner.
2. B commits `beginLocalDeletion`, installing the scoped deletion intent and erasing clock; account and artifact rows remain until bounded cleanup.
3. A's `validateArtifact` transaction still returns success because the artifact row matches subject/namespace.

This method is used by `LibrarySync.copyPreparedExport` as part of current-export validation. That path also checks its export fence, but in an earlier transaction; a deletion can occur after those earlier checks and before this final artifact check. The last DB validation should respect the same authority boundary as the other newly guarded entry points.

Add `assertLocalOwner(db, owner)` inside `validateArtifact` before returning success. A focused actual-store regression should retain a registered artifact, begin deletion through a clone, and verify the journal artifact validator itself rejects despite the retained artifact row. This closes the specific precheck/TX gap; it does not promise impossible atomicity with the subsequent external OutputStream write.

## Capture simplification is sound within the stated boundary

The parent's replacement for FileChannel locking is a valid simplification: `localImportSource` starts the same SQLite write transaction that admits the immutable source BLOB and metadata, and all updated writers first require readiness and never mutate the old file. Separate helper instances/processes serialize that capture through the actual DB write lock. There is no remaining updated-writer cross-file claim. Therefore a separate permanent file lock is unnecessary.

The source is normalized once from the initial decoded legacy value, then stored and decoded on resume. This stabilizes generated defaults such as omitted client UUIDs; repeatedly decoding the unnormalized original for stage verification would have created false mismatches. The exact original bytes/hash remain retained until publication, while final publication rechecks the committed legacy source hash. Unsupported old-version writers remain a compatibility/rollback limit; no guarantee is claimed against an old process that ignores readiness or whole-DB history rollback.

`substr(BLOB, offset, 32768)` reads avoid placing large complete payloads into one CursorWindow. Ownership and digest metadata are read separately. The full selected guest/account payload is still allocated, decoded, encoded and written as one blob; this correctly remains a per-owner/guest scale gate rather than a claim of normalized queue storage.

## Positive implementation findings

- Additive helper v5 creation/upgrade preserves existing Saved/outcome tables. v1/v2 create the current Saved schema; v3 adds active/retiring columns; v4 only gains local-state tables. Source-file decoding does not run in SQLiteOpenHelper.onUpgrade.
- Default journal `transaction` now requires durable Ready inside the DB transaction. Only explicit importer operations use allowUnready. This gates direct journal/Saved/export wrappers, rather than relying on a facade-only ready flag.
- Staging writes guest/deletion/account records in groups of at most eight. Imported deletion fences are installed in those staged transactions and verified, so final Ready publication no longer loops all deletion scopes.
- Source ordinals/fingerprints, staged readback verification and indexed table enumeration account for duplicate-equal source rows and detect conflicting duplicates/missing/extra live local rows before publication. Source/receipt/checkpoint writes commit together.
- Ready is irreversible in this code. Ordinary facade methods query phase without decoding the source; a restored legacy file is ignored for authority and cleaned as redundant bytes. Corrupt existing source is retained and fails before Ready rather than silently becoming empty.
- GuestSnapshot excludes account/deletion arrays. Normal guest mutation touches the singleton guest row. Account methods read and update only their exact keyed account state, with exact subject/namespace/owner validation and scoped deletion checks.
- Guest claim appends the existing exact original-source conversion in its original order and clears that same current guest row in one DB transaction. Invalid originals continue to recovery. A fresh per-transaction decode prevents failed mutations leaking through a cached mutable state object.
- ACK journal metadata and account cursor now use one transaction-local database seam; account write abort rolls both back. The changed old ACK test correctly expects no separately durable ACK timestamp after rollback, and keeps later-cursor/stale-proof assertions.
- Account changes bump the shared export clock atomically. Empty-clock/removal predicates include local account rows. New Saved/outcome producers, active reads and export fence checks revalidate local owner inside the side-effect/read transaction, covering a cloned deletion after a facade precheck.
- Historical outcome evidence reads retain no account-existence requirement, and export enumeration stays scoped rather than cascading old partitionless evidence on account removal. Updated orphan fixture setup deletes the real local account row, retaining the behavioral assertion instead of editing an ignored legacy file.
- Begin deletion installs intent and erasing clock in one transaction. Local cleanup removes scoped account rows in groups of eight, preserves guest/sibling scopes, strictly removes redundant legacy base/backup/new files before identity_pending, and does not clear Ready. Deletion receipts/import fingerprints are cleaned before local completion. Artifact filesystem effects remain resumable and separate.
- The iOS files shown dirty remain the preexisting generated-project/catalog set; this Android storage change does not invent an iOS migration. Existing SwiftData parity tests still need to be reported from their real results.

## Verification still needed for this implementation

The current diff inspected adds two simultaneous cloned-writer tests and moves old fixtures to the new DB authority. Those are appropriate but do not themselves exercise the import driver crash phases. Before treating the new local migration component as verified, add/run concrete real-store evidence for:

1. Mixed legacy source with exact pending/frozen/client/sequence/ACK/recovery/mappings/positions/private Unicode notes and imported deletion phases, including omitted default UUIDs. Reopen during staging, verify and scan, and require exact domain equality and fixed source identity across restarts.
2. Real transaction abort before/after a stage row/cursor and the final Ready update. Direct authority-bearing journal methods must reject until Ready, including Saved active/prepared reads, outcome evidence and exports. A fresh helper must resume the same normalized source and original hash.
3. Changed old source before publication must fail without publishing or deleting either source; restored stale legacy bytes after Ready/claim/deletion must never reimport.
4. Large source, guest and per-owner payloads above the usual CursorWindow size, reopened and compared exactly. This proves BLOB windowing, not acceptable total latency or memory at arbitrary size.
5. Actual v4-to-v5 DB fixture retaining active/retiring Saved records, outcome evidence, export clock incarnation/revision/erasing flag and artifacts. Existing v1/v2/v3 tests are useful but do not substitute for the immediate installed predecessor.
6. SQL trigger abort between claim account write and guest clear, then reopen and retry once. Two clones claiming into the same/different owners must not duplicate sources or erase a later new guest edit.
7. A cloned account-only mutation after export fence invalidates artifact seal/copy even without journal page changes. Selected owner operations must succeed with many malformed unrelated account payloads and show indexed owner work.
8. Legacy cleanup unlink failure prevents local identity_pending; retry preserves guest/sibling DB state and finishes strict cleanup. After deletion begins, direct producer/active/fence/artifact validators must reject in their own DB transaction, not just facade prechecks.

No broad A2 gate is approved. Production Saved read cutover, pending/positions/server export throughput, installed/backend-first rollout, real SDK/JWT, cross-device, physical-device and recoverable iOS save failure remain open. The core local-store architecture is coherent; fix the artifact validation seam and prove the new migration boundaries with the real disk tests before the parent commits the unit.
