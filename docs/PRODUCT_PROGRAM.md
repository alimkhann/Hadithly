# Product completion program

Owner objective received October 17, 2026. This program preserves the complete
objective in the attached `goal-objective.md` and referenced `pasted-text-1.txt`.
The A1/A2 and other letter-number labels below are internal tracking IDs created
for this program, not session names supplied by the owner.

Their checksums and every research URL are recorded in
`product-program/research-manifest.json`. No later phase replaces unfinished work.

## Current stage and rough time budget

October 21 checkpoint: **A2 is active**, specifically native durable assembly of
bounded Saved pages. Core queue/receipt/ownership, manifest folder delete/Undo,
outcome journal/export/retention and the first server Saved page boundary have local
proof. Native assembly/read cutover, broader storage/export scale, installed/SDK
compatibility and real cross-device proof remain. A1 still has content dependencies.

These are remaining focused-work-day estimates at the pace observed October 18–21,
not measured hours or completion promises. External review/account/device waits are
additional; some observation can overlap later work. Re-estimate after native A2
integration, rather than interpreting a test count as a percentage complete.

| Stage | Remaining rough budget |
| --- | --- |
| A1 first-reading content | 1–2 days plus language review |
| A2 sync/storage/cross-device verification | 3–6 days |
| A3 grounding/source quality | 2–4 days |
| A4 fifteen-language localization | 3–5 days plus language review |
| A5 remaining core bugs/UX | 2–3 days |
| A6 release/device/service checks | 2–4 days plus external waits |
| A7 activation/return/conversion evidence | 1 day setup, then 2–4 weeks observation |
| B videos and other research | 3–5 days |
| C research-led native refinements | 3–5 days |
| D website redesign | 2–3 days |
| E Linear setup/readback | Half to one day |

Overall planning allowance: roughly five to eight weeks of focused work, with
external waits unresolved. These estimates preserve the full checklist below.

## Sequence and definition of done

The requested end state is a reliable first reading and return experience on both
native apps, followed by evidence-led native refinements, the supplied website
redesign across its pages, and a configured Linear hub covering the entire program.
Completion requires running the real journeys, reviewing rendered results, and
recording evidence for every requirement below. A build, a draft translation, a
manifest entry, or a proposed external change is not completion.

The owner explicitly requests the previously found gaps first. Research and the
later redesigns remain pending while that work proceeds. External dependencies
stay visible. A missing account, legal approval, physical device, paid-provider
activation, or user-study participant cannot be silently represented as verified.

## Checklist

- [x] Read the objective, pasted resources, PLAN, and workflow principles.
- [ ] Frame and verify the readiness gaps before later redesign work.
  - [ ] A1. Guest first reading delivers actual exact-locale text and provenance,
    including when today's exact-locale translation is absent. Daily identity stays
    canonical. No hidden provider call or quota bypass on opening onboarding.
  - [ ] A2. Reproduce and repair Saved, notes, folders, and reading-position sync;
    prove iOS → Android and Android → iOS, including sign-out/account changes.
  - [ ] A3. Improve real grounding and citation provenance for both free and paid
    generation; verify exact identity, relevance, failures, shared caching, rights,
    and bounded cost. Do not fill citation counts with unrelated URLs.
  - [ ] A4. Audit all runtime copy and Android XML files, repair localization gaps
    across the fifteen supported locales, and verify fallback, placeholders,
    pluralization, RTL, accessibility, and critical-copy review status.
  - [ ] A5. Resolve reproduced architecture, system, behavior, and UI defects that
    prevent the core reading/saving/return journeys. Retain the RTL regressions.
  - [ ] A6. Execute or explicitly retain every existing content, store, purchase,
    physical-device, disclosure, production, backup/recovery, and integration gate.
    Real receipt/readback evidence is required to close an external gate.
  - [ ] A7. Establish honest activation/return/conversion evidence through a
    privacy-preserving measurement plan and consented reader sessions. Current
    clipped analytics totals are not cohort retention.
- [ ] Review the complete research set after the gaps.
  - [ ] B1. All 34 videos have full available transcripts, relevant visual frames,
    timestamped findings, evidence-quality notes, and an application/rejection
    decision. Missing media is explicit, never counted as watched.
  - [ ] B2. Review substantive resources, named case studies, channels, practitioner
    accounts and discussions from the pasted text. Separate verified findings from
    self-reported results, paywalled material, and opinion.
- [ ] Apply the research to the requested native experience.
  - [ ] C1. Simplified paywall with background imagery, hero/subtext, two options,
    clear actual annual billing total plus monthly equivalent, and recommended /
    savings badges extending from the option's top-right edge.
  - [ ] C2. Custom, restrained translation reveal that feels rewarding and remains
    interruptible, accessible, and fast. Centered missing/retry/failure/limit states
    use simple colored icons and no cards. Verify both platforms visually.
  - [ ] C3. Smooth focus entry and exit; thin progress bars remain in focus mode.
  - [ ] C4. Liquid glass menu elements remain visually separate without fusing.
  - [ ] C5. Daily hadith cards follow app appearance, independently of reader theme.
  - [ ] C6. Contents uses real volume names preceded by their numbers and removes
    Open from start. Preserve jump and navigation behavior.
  - [ ] C7. Native glass page-switching controls on supported systems, with fitting
    accessible fallbacks elsewhere.
  - [ ] C8. Coherent onboarding/auth with the official Google brand asset. Use
    Clerk's native flows where supported and a minimal, explained hosted handoff
    where required. Preserve actual sign-in, cancellation, recovery and account state.
- [ ] D1. Inspect the Hadithly redesign package in Downloads; use website assets
  only. Redesign the website and its other pages; verify responsive rendering,
  routes, forms, accessibility, legal links, and content/source claims.
- [ ] E1. Configure Linear as the hub for agents, plans, issues, bugs and docs.
  Link implementation and verification evidence. Confirm actual workspace readback;
  a local proposal does not count as a configured hub.
- [ ] Audit the full objective requirement by requirement, review the decision
  trail independently, commit finished units, and report remaining gates honestly.

## Active unit

A2 sync implementation is active, with A1 content and maintenance dependencies
still open. A1's cache-only boundary is implemented and deployed to the
approved development deployment. Exact public readback is available in English,
Arabic, Russian and Kazakh, with three prepared references each. Eleven locales,
automatic reference maintenance, semantic-quality safeguards and the complete
content gate remain open. Native verification and limits are in
`FIRST_READING_VERIFICATION.md`. Actual content review found a Kazakh meaning
reversal; the exact-text block protects both first-reading paths, while the ordinary
reader's old row remains an A3 repair.

The A2 store diagnostic reproduced unconditional sign-in cleanup deleting newer
unsent notes and positions. Both production sign-in callers now use the durable
coordinator, and account Saved, folder, undo and reading-position writes use its
persisted queue. Owned read streams preserve accepted local edits until the same
server revision is observed. Actual-facade offline/reopen, account-switch, late
read, undo and invalid-write checks pass locally on both platforms. See
`LIBRARY_SYNC_INTEGRATION_VERIFICATION.md`. The compact receipt protocol passed
independent source review; the integration review's stale folder-undo finding is
repaired with an authoritative server member manifest. Local pending/recovery
export now retains offline originals and all server export fields, with local scope/content checks on both apps. See
`LIBRARY_SYNC_EXPORT_VERIFICATION.md`. Persistent deletion phases and a server
recreation guard now pass local checks on both platforms and actual Convex
functions; see `LIBRARY_SYNC_DELETION_VERIFICATION.md`. Bounded quarantine and
known invalid frozen-frame retirement now pass real-store and Convex checks, with
an independently reviewed sparse fence that preserves valid earlier work. See
`LIBRARY_SYNC_RECOVERY_VERIFICATION.md`. Final broad integration review,
actual SDK deletion and propagation, retained-marker privacy/retention treatment,
scale/migration
and real cross-device account delivery remain open. Expired deletion authorization
maintenance now has a bounded internal pager and local scheduler proof; cloud cron
readback is still required. See `ACCOUNT_DELETION_MAINTENANCE_VERIFICATION.md`.
The 501-member support probe remains red. Bounded folder-job candidates, independent
review and remaining contract corrections are recorded in
`product-program/sync-design/scale/decision.md`; logical delete/restore cutover is
not enabled.
Ordinary membership writes now share a causal clock rule, and both native apps
preserve independent folder timestamps. Unknown-time guest claims cannot replace
existing cloud choices. The focused repair passes 413 backend, 51 iOS and 30 Android
checks; see `LIBRARY_SYNC_MEMBERSHIP_VERIFICATION.md`. This is a prerequisite to
the remaining full folder/page/job cutover, not app-level large-folder support.
Membership epochs and an owner-scoped indexed maximum now track accepted moves,
restores and last-facet removal. The 2,001-member fixture and complete 421-test
backend suite pass locally; see `LIBRARY_FOLDER_SCAN_VERIFICATION.md`. No paged
folder preparation or logical deletion is enabled yet.
Independent review also exposed foreign malformed pointers affecting existing
delete queries. Both queries now restrict owner before member reads and writes;
actual red/green fixtures and the final source recheck are in that record.
Resumable manifest preparation, recovery and cleanup now pass 501-/2,001-member
actual Convex fixtures and a complete 433-test backend suite. See
`LIBRARY_FOLDER_MANIFEST_VERIFICATION.md`. This prepares identities only; the
held-frame/terminal-receipt, logical membership, Undo, page/export and native
migrations remain open. The current 501-member product support probe is still red.
Held-frame proofs, protected ACK/retirement, exact failure receipts and both native
waiting/polling consumers now pass 439 backend, 55 iOS and 34 Android checks. An
independent review's same-ID restored-copy flaw was reproduced and fixed using a
cross-native content fingerprint. See `LIBRARY_SYNC_HELD_FRAME_VERIFICATION.md`.
Successful logical effects, Undo, producer/read/export cutover and old installed
schema/client migration remain open; no public large-folder success is claimed.
Internal logical deletion, staged Undo, clock resolution, materialization and
retention now pass full 501-/2,001-member sequences, with 453 backend tests overall.
Older facet endpoints also share the canonical writers after a reproduced ghost
membership defect. See `LIBRARY_FOLDER_EFFECTS_VERIFICATION.md`. Native 56 iOS/35
Android checks include retaining frozen originals when outcome collection is absent.
The public producer, paged outcomes/reads/export and final legacy/installed migration
remain gated; the public 501-member product probe is still red.
The outcome page boundary now passes 0/1/50/51/501-member, ownership, exact-proof,
retention and immutable-history fixtures, with 469 backend tests overall. Native
cursor adoption now rejects acknowledging uncollected manifest results;
the chosen SwiftData/SQLite collection design still needs implementation and proof.
See `LIBRARY_OUTCOME_PAGE_VERIFICATION.md`. This advances the server page contract;
public producer, durable native collection, bounded Saved read/export and installed
migration remain open. No deployment was performed.
The native journal core is now implemented and verified against real SwiftData and
SQLite stores, with 65 iOS and 45 Android checks. Bounded resumable verification,
partial evidence and account erasure are covered; an injected Android cleanup
failure resumes after its first committed batch. See
`LIBRARY_OUTCOME_JOURNAL_VERIFICATION.md`. This stores evidence only. Every manifest
ACK guard remains until coordinator/settlement, full export, Saved revision barriers
and retention are integrated. The public producer and full A2 gate remain open.
The actual native coordinators now route direct and adopted manifests into durable
matched/historical collection phases and fetch journal pages. Interrupted 501-member
reopen fixtures pass with zero ACKs and no later sends, with 68 iOS/48 Android checks.
See `LIBRARY_OUTCOME_COORDINATOR_VERIFICATION.md`. The no-ACK guard now lives in the
persisted phase. Final settlement/export/pruning and public cutover remain open.
Retained native outcome export now streams bounded journal pages for the captured
subject/deployment, including older-owner orphan evidence, with mutation fencing
and private artifact cleanup. Actual old-store migration, corruption and account/
erasure/cancellation fixtures pass: 74 iOS and 56 Android checks. Android also
exercises real local document URI rollback. See
`LIBRARY_OUTCOME_EXPORT_VERIFICATION.md`. Existing server/partition export scale,
physical/external-provider behavior and the full A2 gate remain open. The no-ACK
settlement guard remains until exact terminal policy, Saved barriers and recovery
are integrated; pruning and public producer cutover are still pending.
Exact native outcome settlement now waits for the owned Saved revision, preserves
partial/unavailable recovery and original source, persists ACK intent, and retries it
after reopen. Full local checks pass 78 iOS and 61 Android tests; see
`LIBRARY_OUTCOME_SETTLEMENT_VERIFICATION.md`. Unavailable proof still blocks ACK.
All journals remain retained. Pruning/retention, manifest Undo, public producer/read
cutover, full-library scale, iOS write-failure and actual hosted/device matrices remain
open. No A2 deployment or full A2 completion is claimed.
Native outcome ACK confirmation and bounded success cleanup now have local proof.
Only exact matched complete success gains ACK metadata; aged cleanup preserves
queued/offline Undo and recovery dependencies, advances fairly past retained headers,
and removes at most 50 facts per transaction. Export fails during partial pruning.
See `LIBRARY_OUTCOME_RETENTION_VERIFICATION.md` for 85 iOS/68 Android checks,
501-row interruption, ACK replay and their limits. Manifest Undo/public cutover,
full-library scale, iOS save failures and hosted/device/deployment gates remain open.

The public manifest producer and compact native account Undo now pass local proof.
Current native bindings explicitly select manifest-v2; legacy capabilities cannot
consume upgraded stream proof. Exact old mixed frames split without business effects
and ACK before isolated replay. Scheduled delete/Undo, authoritative membership,
atomic destination aliases and causal offline projection pass 501-member fixtures.
See `LIBRARY_PUBLIC_FOLDER_VERIFICATION.md` for 484 backend, 89 iOS and 72 Android
passes and the final independent review. The current-binding 501 support probe is
now green locally; the default v1 probe retains its safe size limit. Full Saved/
folder/export and whole-file scale, legacy transaction/age, installed/SDK/device,
iOS save-failure and A2 deployment gates remain open. No A2 deployment occurred.

Paged-read grounding found and repaired a missing Saved revision advance in the
legacy H3 backfill. Each changed owner now advances once per page in the same
transaction; unchanged replay and unrelated owners do not. Three actual-function
red/green regressions and the complete 487-test backend suite pass. See
`LIBRARY_BACKFILL_REVISION_VERIFICATION.md`. Bounded reads/native assembly,
whole-file/export scale and all hosted/device/deployment gates remain open.

The first bounded Saved read component now serves owner/revision-bound private
source facts with signed continuations, explicit incomplete/oversized failure and
no public hadith joins. A review-discovered SplitRequired gap has four actual
adapter red/green regressions. The complete backend suite passes 511 tests; see
`LIBRARY_SAVED_FACTS_VERIFICATION.md`. Production native reads still use the
old whole snapshot. Both native durable row assembly/activation and independent
summary hydration, practical throughput, full export and whole-partition scale,
installed/SDK/device and deployment gates remain open. No A2 rollout occurred.

Native Saved wire and deterministic page/reducer policy now derive actual validators
and match a real backend parity fixture on both platforms. Selected native suites
pass 95 iOS and 78 Android checks; all 511 backend tests pass. See
`LIBRARY_SAVED_POLICY_VERIFICATION.md`. This is a pure policy/codec substep.
Durable raw collection, bounded fold/verification, migration, erasure/export,
activation and production barrier/read cutover remain open. A2 is still active.
The durable native Saved store now retains raw facts and exact replay receipts,
folds and verifies bounded projection rows, and streams retained private evidence
through existing fenced export. Real old-schema migration, interruption, rollback,
erasure/reopen and indexed query checks pass with 107 iOS and 88 Android tests.
See `LIBRARY_SAVED_STORE_VERIFICATION.md`. A real iOS technical cursor-sort bug and
an Android unrelated-row scan were reproduced and repaired. This yields prepared
data only; production reads and all acknowledgement barriers still use the existing
complete snapshot. Final server recheck/atomic activation, all consumer cutovers,
public hydration, practical throughput, whole-file/export scale and hosted/device/
deployment gates remain open. A2 is still active.

Continue A2 integration while retaining A1's content dependencies. No paid
generation or production change has been approved. Research, later native redesign, website and Linear remain
pending in the owner's requested order.

The principles shaping this sequence are Experience First (actual readable text),
Model the Domain (separate a first reading from a canonical Daily selection),
Prove It Works (native/runtime evidence), and Sequence Work into Verifiable Units
(finish each readiness unit before research-driven redesign).

The canonical decision trail is `product-program/decisions.tsv`.
