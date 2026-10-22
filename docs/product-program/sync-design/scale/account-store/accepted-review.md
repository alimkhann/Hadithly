# Account-store final implementation recheck

2026-10-22. Read-only recheck of the current Android local-state implementation and complete new migration/clone test block. Reviewed LibraryLocalStore.kt, GuestStore.kt, LibraryOutcomeJournal.kt, the test diff including authority-targeted replacements, and the widget snapshot type adjustment. Parent is the sole implementer. No code/repository edits, cloud actions or gate approval by this consultation.

## Result

**No remaining concrete correctness finding in the reviewed local migration unit.** The prior artifact-validator P2 is fixed: validateArtifact now calls assertLocalOwner inside the same SQLite transaction that checks retained artifact ownership. The actual retained-artifact deletion regression calls the journal validator directly after deletion begins while the artifact row still exists, and requires rejection. This exercises the previously missing boundary rather than relying on a facade precheck.

localDeletion also now checks assertErasedScope before reporting identity_pending. GuestStore then strictly retries redundant legacy path cleanup before returning that phase. Unused public journal transaction wrappers have been removed; combined queue/ACK/retention/settlement operations use internal transaction-local helpers. The readiness gate remains inside the shared synchronous journal transaction.

## Verified terminal results inspected

- `/tmp/hadithly-account-store-android-final.log`: BUILD SUCCESSFUL. The actual connected XML reports GuestMergeRaceTest **114 tests, zero failures/errors/skips**. The separate installed-widget fixture is **one explicit skip**; do not call it a widget runtime pass. The XML aggregate is 115 cases, one skipped, zero failures/errors. The Gradle console's inconsistent `Finished 116 tests` counter is not the authoritative count.
- Android XML: `android/app/build/outputs/androidTest-results/connected/debug/TEST-hadithly(AVD) - 16-_app-.xml`, inspected after terminal completion.
- `/tmp/hadithly-account-store-ios-parity.log`: **120 tests, zero failures**, TEST SUCCEEDED. `/tmp/hadithly-account-store-ios-parity.xcresult` is the reported result bundle. This is selected existing iOS no-change storage parity, not new migration or physical-device proof.
- `git diff --check` returned clean during this recheck.

No tests were independently relaunched; these are inspected actual artifacts from the parent's completed jobs.

## Evidence supporting the local result

The new tests inspect real SQLite state and use actual trigger aborts/reopened helper instances:

- Nineteen-owner import with private RTL/Kazakh Unicode notes stages at most eight receipt rows per step, rolls back rows plus checkpoint together, resumes canonical omitted UUID defaults identically, and refuses all local authority before successful Ready. A Ready-trigger abort retains both source/original BLOBs and remains unready; successful publication clears those BLOB columns logically.
- Unknown fields, conflicting duplicate owners and ambiguous historical owner keys fail before import publication and preserve original source bytes. Identical duplicate account/deletion records are separately receipted and coalesce only by exact equality. A changed legacy source blocks final publication while captured original bytes remain retained.
- Guest claim account append and guest clear roll back together on an actual SQLite abort. Exact duplicate-target original drafts and invalid-source recovery survive. Repeated claim does not duplicate them; restoring stale old JSON after Ready/claim does not reimport.
- Independent cloned guest writers preserve all sixteen accepted notes. Independent account writers preserve all sixteen accepted command identities. Two simultaneous different-owner claims distribute each original once; a later guest note remains unclaimed.
- A payload above 2.3 MB migrates, reopens and retains exact recovery text without CursorWindow full-row failure. A malformed foreign account blob does not block selected-owner/guest operations. The scoped account lookup plan uses the local_accounts_scope index, and the foreign corrupt payload remains untouched.
- A guest-only edit leaves an account export fence valid; a cloned account-only command invalidates it. Existing portable export/old-owner orphan tests now seed/remove the real account-row authority and continue passing. Clock emptiness/removal includes retained account rows.
- Deletion intent plus erase clock roll back together when the clock update aborts. A non-removable redundant legacy path prevents identity_pending; retry preserves sibling partition and newer unclaimed guest note, removes the captured account and completes local cleanup. Late journal producers/export registrations reject a missing local account inside their own transaction without creating new scope/header/Saved/artifact rows.
- An actual v4 schema fixture, constructed by removing only new v5 local tables and setting predecessor version, upgrades to v5 and preserves exact frozen frame/account state, active and retiring Saved metadata, active handle, export-clock fence and artifact row. Existing v1/v2/v3 upgrade suites also pass. This validates additive local schema evolution; installed-binary rollout/backup restoration remains separate.
- Existing ACK-failure tests now use an actual account-row trigger and require account cursor plus journal marker rollback together; successful retry records the first successful timestamp once. Outcome settlement write-failure/retry assertions remain preserved at the new authority.

## Architectural checks

SQLite write ownership serializes immutable source capture and cloned resume operations. Updated writers never modify the legacy file; therefore the parent correctly removed the extra FileChannel lock/snapshot-file protocol. Canonical source and exact original are retained separately until verified publication. Unsupported old writers and whole-database history rollback are outside this local guarantee.

Post-ready hot operations use one guest singleton or one exact owner row. They do not reconstruct GuestStoreFile or decode unrelated account blobs. Thread-local SQLite transactions contain synchronous policy and writes after facade entry to IO; no suspending transform/network wait is held inside the transaction. The immutable private Saved generation remains separate from account queue/source and future derived view authority. Production Saved consumers have not switched to row mode during this unit.

All normal journal transactions require durable Ready. New-authority production operations revalidate current account/deletion ownership inside the transaction, while historical partitionless evidence remains retained and scoped exportable rather than requiring account recreation. Imported deletion fences stage/verify in bounded import steps before the final marker flip. Source hash recheck is an explicit one-time whole-source migration cost, not a steady-state bounded-byte claim.

## Limits retained

This accepts the reviewed implementation direction and inspected local test evidence; it closes no broad A2/release gate. Guest and selected-owner payloads are still whole blobs for decode/write. Large-byte latency/memory, pending/positions/server export throughput, unsupported rollback/old simultaneous writers, physical process power-loss/backup restoration, installed-client/backend-first rollout, real SDK/JWT, cross-device and physical-device behavior remain separate evidence. SQLite source clearing/unlink is logical local cleanup, not a forensic secure-erase claim. The optional installed widget fixture was skipped. Recoverable actual iOS save-failure injection remains open.

Parent can document and commit this local component while preserving the full product goal and these remaining gates. No push or deployment is authorized by this review.
