# Large-folder architecture checkpoint

October 19, 2026. Candidates and independent judge are read-only design work.
Resumable manifest preparation is now implemented and locally verified. Logical
folder commit and staged restore are not enabled. The current
500-member product limit remains open and has a repeatable actual-function probe.

## Decision

Use A's resumable manifest job as the conservative reference base. It preserves
current member identity and per-member outcome semantics with the smallest storage
ownership change. Do not implement it verbatim. Graft B's bounded read/export
requirements and one-hop normalization discipline, and the C review's phase-aware
membership clock and one-time deletion-handle requirements. C remains a promising
smaller alternative, not the selected implementation: its raw orphan-pointer rule
as written loses Undo eligibility under an older delayed membership removal.

The parent's source review agrees with the independent judge: all three sketches
need another verifiable unit before a product cutover. A passing support claim
cannot come from increasing take501 or replacing one unbounded collect with pages
while still returning a complete member array or following unbounded aliases.

## Required corrections to A

- One domain module owns effective membership, conflict clocks, jobs, dispositions
  and materialization. UI callers keep delete/undo plus captured account scope;
  views never coordinate pages or job internals.
- Every current, guest and legacy placement/facet-removal path participates in the
  epoch/version and staged-membership rules. A fact staged before a concurrent move
  cannot later make that superseded member visible. Keep the exact terminal count
  at its commit point and separate later materialization progress.
- Keep only one current staging/alias hop per item. Structural transitions wait
  behind bounded materialization while ordinary membership moves remain available.
  Re-evaluate their clocks when they run. Do not build arbitrary redirect history.
- A stream needs a distinct pending job state, not a committed success called
  started. Exact final receipts alone may ACK. Invalid-frame retirement must not
  skip an in-progress job or assume it had no effects. New native frames should
  isolate folder operations; older mixed frames require a truthful migration rule.
- Replace full member outcome arrays with a bounded receipt plus immutable paged
  outcomes. The native coordinator must durably preserve what is needed for partial
  recovery before compaction. Do not call a scanned subset the entire deletion.
- Add bounded owned Saved/folder and export pages with a native version/assembly
  contract. Do not mix owners or combine different Saved revisions into a complete
  snapshot. Metadata, source-text read bytes and response size need explicit bounds.
- Specify the lifetime of unconsumed deletion handles, immutable member facts and
  frozen offline Undo. ACK of a deletion alone does not prove no Undo is queued.
  Cleanup must preserve pending work or return an honest recoverable expiration,
  with an explicit policy. Per-member facts times deletion history cannot grow
  silently without an admission/retention budget.
- Every worker checks current job generation and server owner existence before
  effects. Account erasure invalidates jobs/facts and prevents late resurrection.

## Next executable unit

Run the existing support probe red, then build the effective-membership and
transition model against the 50/100/75 stale-removal counterexample, post-delete
moves before/after restore commit, repeated same-name delete/recreate/undo, worker
interruption and pending-frame replay/retirement. Implement the indexed maximum,
shared writer rule and bounded server page/job core only once these invariants are
specified. Exercise actual Convex interleavings and step read/write/byte bounds at
501 and larger fixtures. Migrate both native coordinators/projections together,
then installed-store/client fixtures and approved actual account/device readback.

## Executed current-limit diagnostic

Default test:
`npm --prefix backend test -- convex/libraryFolderScale.test.ts`

It executes the actual owner-bound mutation with 501 Saved members, checks no
partial unlink/truncation, preserves all facets, and verifies another account's
folder/note stay untouched. Its current safe unresolved result is a data-safety
check, not large-folder support.

Required-support probe:
`HADITHLY_REQUIRE_LARGE_FOLDER_SUPPORT=1 npm --prefix backend test -- convex/libraryFolderScale.test.ts`

This was run and is red: expected folder_deleted, received unresolved. Evidence:
`/tmp/hadithly-large-folder-gate-red.log`. It must remain an open gate until the
new product behavior is implemented and the probe is updated for terminal jobs.
Local synthetic fixtures do not prove Convex hosted quotas or real two-device sync.

## Workflow

- [x] Frame and trace actual caller/storage/receipt paths.
- [x] Two structurally distinct read-only candidates.
- [x] Read both and obtain independent criterion-by-criterion cross-judge.
- [x] Pick conservative reference, document grafts and rejected assumptions.
- [x] Independently falsify the parent's smaller alternative.
- [x] Execute current-limit support probe and retain its red result honestly.
- [x] Reproduce and fix ordinary membership causal clocks and independent native
  guest timestamps. Unknown-time claims preserve cloud choices; see
  `../../../LIBRARY_SYNC_MEMBERSHIP_VERIFICATION.md`. This does not implement
  effective membership during logical folder transitions.
- [x] Implement membership epochs and owner-indexed maximum against actual writer
  paths and 2,001 members. See `../../../LIBRARY_FOLDER_SCAN_VERIFICATION.md`.
  This supplies a scan guard; it does not implement manifest preparation or a
  logical visibility commit.
- [ ] Correct and verify the state/retention/page contract.
- [x] Implement bounded manifest preparation, generation/step replay fences,
  stalled delivery recovery and temporary-fact cleanup. See
  `../../../LIBRARY_FOLDER_MANIFEST_VERIFICATION.md`. Prepared is not a terminal
  receipt; native cutover and the full retained-handle contract remain open.
- [x] Implement held-frame pending proofs, protected ACK/retirement, exact failure
  publication and both native waiting/poll consumers. Reproduce and fix same-ID
  restored-copy confirmation with cross-native content fingerprints. See
  `../../../LIBRARY_SYNC_HELD_FRAME_VERIFICATION.md`. Successful logical effects,
  complete native producer/read/export cutover and retained Undo authority remain
  open.
- [ ] Implement bounded server core and both native integrations.
- [ ] Verify migrations, interruption, privacy and actual approved device delivery.
