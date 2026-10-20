# Outcome export implementation review

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only architect Phase D review of the uncommitted implementation

## Findings

### P1: Android loses the mutation fence before publishing to SAF

`LibraryPreparedExport` retains only the file, artifact ID and write context. `copyPreparedExport` validates the current session and artifact registry row, but it does not validate the captured `LibraryOutcomeExportFence`. An ordinary journal mutation after private sealing leaves the artifact row valid, so the SAF copy continues and reports success without the required final revision check.

Keep the opaque fence in `LibraryPreparedExport`, or bind epoch/revision to the artifact registry and validate it in `validateOutcomeExportArtifact`. Check it before each bounded destination write and after flush. Erasure happens to delete the artifact row, but verification, page persistence, header insertion, pruning and owner-key cleanup do not.

Evidence: `LibrarySync.kt:352`, `LibrarySync.kt:564-584`, `GuestStore.kt:589-592`, `LibraryOutcomeJournal.kt:253-257`.

### P1: Android leaves a publishable partial SAF document on failure

`CreateDocument` creates or grants the external destination before server fetch and private preparation. If preparation fails, session changes, cancellation arrives, erasure starts, or the stream fails after some writes, Settings reports failure but never deletes or truncates the URI. The private artifact cleanup cannot remove those external bytes.

This is broader than the acknowledged inability to revoke bytes after a successful handoff. The current flow can leave an empty or partially copied file after a failed export. Attempt `ContentResolver.delete(uri)` on every failure/cancellation before success and test a provider that supports deletion. If a provider refuses rollback, keep that destination as an explicit failed external-publication gate and do not claim the no-partial-artifact contract.

Evidence: `SettingsScreen.kt:1036-1065`, `LibrarySync.kt:564-586`.

### P2: iOS leaves a completed private artifact when Settings disappears

The view's `onDisappear` cancels `exportTask` but does not discard an already prepared export. If preparation has completed, cancellation is inert and the state-owned artifact can become unreachable when the view is destroyed. Startup or the next export eventually sweeps it, but cancellation cleanup is not immediate as required.

Call the same artifact discard path from `onDisappear`, or make disappearance invoke `clearExportPresentation` without clearing unrelated deletion state. Keep `ShareLink` alive only while the destination remains visible.

Evidence: `SettingsDestinations.swift:1084-1085`, `SettingsDestinations.swift:1127-1131`.

### P2: iOS has one journal mutation path without a clock bump

`collectOutcomeStep` can create a missing `GuestOutcomeScope` and then find an existing header. That save changes durable journal ownership/generation state but does not bump the subject clock because `insertOutcomeInventory` runs only for a new header. This can occur during repair or a damaged/restored store, exactly where the design requires conservative invalidation.

Track whether the scope was inserted and bump the same subject-plus-namespace clock in that save. The common new-scope/new-header case already bumps through inventory insertion, so avoid a redundant second bump if one revision per transaction is the intended rule.

Evidence: `GuestDataStore.swift:748-761`. Android correctly bumps when `captureGeneration` inserts a scope at `LibraryOutcomeJournal.kt:275-282`.

### P2: installed iOS migration remains unproved and fail-hard

The app adds four nonoptional SwiftData models to the live container and opens it with `try! ModelContainer`. The logical inventory backfill is bounded and has a second scan, but it runs only after the store opens. A lightweight installed-store migration failure crashes before that code can protect or report anything.

Add the planned real old-store reopen test before treating this path as usable. Verify iOS 17 creates the unique inventory key index, preserves all existing outcome rows and resumes an interrupted logical backfill. A failure should reach the existing store-unavailable behavior rather than silently replacing the store; whether the app should avoid `try!` is a broader existing-store decision.

Evidence: `GuestDataStore.swift:21-47`, `GuestDataStore.swift:537-574`.

## Areas that currently hold

- Both platforms use one clock keyed by subject plus deployment namespace, not by current owner. Persisted authority and header owner fields are cross-checked before export, so the reviewed paths include old-owner and partitionless headers without admitting a foreign subject or namespace.
- Header/member/checkpoint writes and verification bump the clock in the same SwiftData save or SQLite transaction. Android header discovery uses the new `(subject, namespace, collection_key)` index. iOS uses a unique scoped inventory key and a two-pass global backfill.
- Full erasure marks the clock as erasing before row cleanup, removes registered private artifacts, and relies on the durable deletion intent to block recreation after clock removal. No registry resurrection path was found in the reviewed app-owned flow.
- Private preparation streams journal rows in pages of at most 50 and distinguishes collected-prefix end from `detailComplete`. Existing server and partition values still accumulate in memory, correctly leaving the broader scale gate open.
- Cancellation during preparation removes the app-private artifact on both platforms. Android catches and rethrows `CancellationException`; iOS uses its defer cleanup while the artifact is not retained.

## Required focused proofs

1. Mutate each Android clocked path after sealing and during SAF copy. The copy must fail through the retained fence, with destination cleanup attempted.
2. Cancel Android before preparation, mid-copy and after flush; switch account and begin erasure at the same points. Inspect the actual URI rather than only the notice text.
3. Leave iOS Settings after preparation completes and confirm the registry row and directory disappear immediately.
4. Create the iOS missing-scope/existing-header repair case during an export and prove the fence changes.
5. Reopen real pre-change iOS and Android stores, interrupt backfill, insert a header before the cursor, resume, and prove exact owned inventory with no row loss.

The existing missing-journal red-to-green evidence is useful but does not cover these races. Settlement, ACK, pruning, full-export scale, external destination behavior and broader A2 gates remain open.
