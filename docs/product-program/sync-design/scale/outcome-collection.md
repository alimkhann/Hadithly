# Paged outcome collection contract

October 20, 2026. A2 continuation. This is the chosen native design and the
implemented server page contract. The native journal core is implemented; coordinator,
settlement, export and app cutover still require integration and proof. No deployment
is authorized by this record.

## Caller and ownership

The existing sync coordinator receives a terminal manifest receipt and asks its
store to collect that exact outcome. The store owns page validation, persistence,
reopen and readiness. Views continue to consume Saved snapshots and compact local
changes. They never page or reconstruct membership from result facts.

The journal binds captured subject, namespace, server owner, installation/client
key, sequence, batch and digest, receipt ID/revision, manifest ID/generation and
delete/restore phase. An exact duplicate resumes. Different content at an occupied
ordinal or a repeated member at another ordinal stops collection. It cannot replace
previous evidence. Same-ID/different-intent local commands remain historical.

## Server page

`librarySync.outcomePage(capability, request)` verifies the Clerk owner and current
binding. The request carries the exact committed acknowledgement proof, receipt ID,
manifest identity/generation, phase and nonnegative integral ordinal. A matching
committed stream slot and its manifest receipt authorize the query. A pending slot,
another owner, wrong proof or acknowledged stream grants no member access.

Each response echoes owner/request and contains at most 50 identity facts, with an
encoded 64 KiB ceiling. Facts contain ordinal, manifest-member ID, hadith ID and
disposition. They contain no note, folder name or hadith text. Indexed ordinal reads
must return every expected row in order. Missing rows fail with a fixed invariant
error; a short page cannot masquerade as completion. Count components and their sum
must be nonnegative safe integers. Continuation is the actual next ordinal, and
completion requires that ordinal to equal the receipt total. Zero members still
require an authenticated empty terminal page.

Delete pages always describe the original deleted identity set, including while
Undo mutates the same facts' restore dispositions. Restore pages become available
only from a terminal restored receipt, and use its frozen categories. Later user
edits do not rewrite that historical result.

`proof_unavailable` means current receipt authority could not be established. It
never authorizes native settlement or ACK. `detail_unavailable` means the receipt
was verified but retained detail expired or was removed. The native protocol must
persist this distinction, the exact proof, partial facts and locally available
original source. Whether to settle that explicit recovery state must be encoded
and tested before enabling the public producer; no current native ACK path does so.
Network errors and malformed facts remain unfinished work.

## Native storage choice

Use candidate A's native row journal: SwiftData rows on iOS and private SQLite
rows on Android. Its transaction can write a bounded page and header together.
At cutover, partition JSON will hold a compact handle only. The journal core currently
leaves the partition unchanged. It must not grow an array of collected identities.
Strict fetch-and-compare plus database uniqueness protect
ordinal/member identity; SwiftData uniqueness alone can upsert and is insufficient.

Android's journal transaction commits before the existing AtomicFile settlement,
which commits before server ACK. Reopen can replay a complete matching journal
when JSON is stale. JSON claiming readiness without matching durable evidence must
stop. iOS can settle partition and journal in the same ModelContext save, but must
also tolerate and prove page/reopen boundaries. The coordinator calls a small store
operation instead of coordinating individual filesystem/database steps.

Each active owner scope has an erasure generation. Erasure rotates it before the
member/header sweep and removes the scope row afterward. A missing scope or a new
scope UUID also rejects stale writers. The durable account-deletion intent remains
until cleanup finishes. Erasure removes orphan journal rows even when the partition
disappeared. Scope metadata is not an indefinite tombstone.
Export discovers retained evidence under captured ownership rather than only
following partition references. It must fail explicitly if required evidence
vanishes during export. Do not persist capabilities or JWTs in this journal.

## Projection and retention

Keep terminal work until collection readiness and an owner-tagged Saved snapshot
at or beyond its committed Saved revision. That snapshot determines membership.
Never restore every local command identity when only a subset succeeded, or let
an old successful delete overlay override a newer authoritative snapshot.

Success pruning requires durable ACK, observed Saved revision and no remaining
Undo, frozen/offline restore or recovery dependency. Partial restore and unavailable
details retain locally available evidence for private recovery/export. No silent
eviction or unlimited-retention claim is introduced. Storage failure pauses sync.

## Selection and proof

Both candidates were read end to end. Parent scores match the independent judge:
A scores 4/4/3/4/3 and B scores 4/3/4/2/3. Choose A, 18/25 versus 16/25. Native row
transactions and indexed orphan/export queries hide more complexity than custom
file rename, directory synchronization, hash-chain repair and bounded file walks.
Reject B as the base; retain its erasure, proof distinction and Undo-aware pruning.
Reject growing partition arrays because every page would rewrite previous members.
Source candidates and independent judgment are saved beside this contract.

## Implemented journal core

`GuestDataStore.collectOutcomeStep` owns request binding, page fetch, strict parsing,
generation checks and one row/checkpoint transaction. `collecting` writes at most
50 facts. The final server page starts `verifying` instead of claiming completion.
Each subsequent local step checks at most 50 persisted facts and saves its category
cursor. Only verified exact totals reach `complete`. Reopen continues from either
cursor; completed verification relies on the journal's immutable rows and atomic
transactions. It is not a fresh full audit on every read. Whole-manifest scans per
page were rejected after implementation review.

Swift uses a fixed-width ordinal key's unique index for bounded page order, a fresh
ModelContext per journal transaction, and strict compare before any unique-model
insert. Android uses SQLite primary/unique indexes and INSERT without REPLACE.
Unavailable proof and unavailable detail retain their different terminal reasons
and all collected facts. Conflicting terminal replays fail. Neither journal writes
an ACK or changes the partition while collecting.

`outcomeEvidencePage.endOfCollectedPrefix` marks only the end of locally retained
facts. It does not mean the original manifest is complete. Recovery/export must
carry expected totals and checkpoint status. Whole-export discovery, retention,
Undo-aware success pruning and coordinator settlement are still cutover work.
Account cleanup uses bounded committed sweeps and removes scope metadata. The
separate reset helper is explicitly test-only and does not claim final erasure.

See `../../../LIBRARY_OUTCOME_JOURNAL_VERIFICATION.md` for actual store proof and
remaining device/migration limits.

Prove 0/1/50/51/large pages and mixed frozen categories against the actual server.
Then prove real SwiftData and SQLite reopen, identical/conflicting duplicate,
failed page/settlement/ACK boundaries, unavailable detail, Saved revision, Undo
retention, orphan erasure and complete export on both apps. Installed-schema
migration and existing whole-file cache scale remain separate gates. The public
producer, bounded Saved read/export, authenticated devices and hosted limits remain
open until their own end-to-end verification.
