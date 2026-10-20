# A2 native outcome journal core

October 20, 2026. Continues `0a3f187`. Both native stores implement durable bounded
collection and verification of exact folder outcome facts. This is the journal
core, not app-level large-folder support. The coordinator still rejects manifest
settlement until its remaining integration is implemented. No deployment, private
account call, paid generation, production migration or push was performed.

The selected architecture is
`product-program/sync-design/scale/outcome-collection.md`.

## Implemented behavior

`collectOutcomeStep` binds server owner, captured subject/namespace, installation,
sequence, batch/digest, receipt ID/revision and manifest ID/generation/phase. It
verifies the echoed request, row/byte limits, contiguous ordinals, unique identities
and allowed categories. A page inserts at most 50 facts and updates its checkpoint
in the same database save. The native partition remains unchanged while collecting;
facts do not accumulate in its whole-file JSON.

iOS adds SwiftData header, member and active-scope models. Each journal transaction
uses a fresh context and checks unique ordinal/member/hadith keys before insertion.
A conflicting unique value cannot silently upsert previous evidence. Its padded
ordinal-key index orders bounded reads. Android uses private SQLite under the same
app files directory, with primary/unique constraints and INSERT without REPLACE.
The SQL uses Android 8-compatible operations rather than a newer SQLite UPSERT.

The final fetched page starts a durable `verifying` phase. Each subsequent local
step checks at most 50 persisted identities/categories and commits its cursor.
Only exact verified totals become `complete`. Restart resumes either phase without
fetching a verified prefix again. A completed header trusts the previous durable
verification and immutable rows; it does not rescan every fact on each access.

Identical overlapping requests replay without double counting. Conflicting rows,
repeated identities or invalid categories roll back the whole page. Unavailable
proof/detail remain distinct, retain the collected prefix, and do not create ACK
intent. The local evidence pager names its boundary `endOfCollectedPrefix`, so a
partial or unavailable prefix cannot be mistaken for a full server manifest.

Account erasure validates the durable deletion intent, rotates active generations,
removes members/headers/scopes in bounded committed batches, and only then advances
the local deletion phase. It finds orphan evidence without a partition reference.
Late pages cannot recreate an erased journal. Scope rows containing private owner
metadata are removed at the end. The old generic partition eraser had no production
callers; it is now named `resetSyncPartitionForTesting` on both platforms. It is not
an account-erasure guarantee.

## Review corrections and evidence

The first implementation passed 52 focused iOS and 43 Android checks, but independent
review exposed repeated whole-manifest verification scans, retained scope metadata,
Android scope creation before the owner check, an unbounded delete cascade and
ambiguous terminal replay. These were repaired in source. Verification now has its
own bounded cursor, erasure deletes scope metadata and rejects stale initial calls,
SQL sweeps commit at most 50 facts per batch, and unavailable replays compare exact
reason/start. The re-review found these corrections in source; it did not run tests.
Reports are saved beside the contract as `outcome-journal-review.md` and
`outcome-journal-review-final.md`.

The new real-store tests cover 0/1/50/51/501 facts, reopening during collection and
verification, overlapping identical/conflicting callbacks through reopened stores,
rollback after earlier rows of a page were inserted, wrong owner/categories,
unavailable partial evidence, original partition preservation, and an old callback
after reset/recreation. A deliberately removed persisted member fails verification
before completion. A 501-row orphan erasure removes owner metadata while preserving
another subject and another deployment. A stale initial call cannot recreate scope
metadata. Android additionally injects a SQL trigger failure after the first 50-row
erase batch, confirms the durable deletion intent and remaining rows, then reopens
and finishes the sweep after removing the trigger.

| Check | Result | Evidence |
| --- | --- | --- |
| iOS core/store/coordinator, presentation and Settings | 65 pass | `/tmp/hadithly-outcome-journal-ios-verified.log`, `.xcresult` |
| Android actual store/coordinator instrumentation | 45 pass | `/tmp/hadithly-outcome-journal-android-verified.log` |
| Generated native wire source check | Pass | `python3 scripts/generate-library-sync-wire.py --check` |

An earlier final Android attempt compiled successfully but had no connected emulator.
The device was restored; the latest named run is the behavioral evidence. Existing
iOS fixture teardown emits SQLite unlink warnings; these are not process-kill or
power-loss durability tests. Tests reopen real stores using controlled wire pages,
not a deployed Convex query or real private account.

## Remaining gates

Integrate the journal into every direct/pending/reconcile/retirement/ACK cursor route,
bind exact local frozen intent or historical recovery, and persist settlement before
ACK. Connect authoritative Saved revision barriers, full captured-owner export
discovery/streaming, partial/unavailable recovery and Undo-aware success pruning.
Until these exist, keep manifest ACK guards and the public producer disabled.

Whole-file native Saved cache/pending scale, old installed stream/client/schema
migration, iOS 17 and Android 8 runtime proof, real process termination/storage-failure
coverage, host query plans/cost, authenticated device/cross-device delivery, bounded
Saved read/export and legacy timestamp/list-only Undo cutover remain open. Existing
additive SwiftData fixture migration is local evidence only. No unlimited retention
or release-ready claim is made. Other A1, quality, localization, store and release
gates remain unchanged; the full product program remains active.
