# A2 large-folder design frame, October 19

Read-only architecture consultation within the existing A2 session, not a delegated
implementation session. Do not edit the repository, deploy, call cloud/private
accounts, or access credentials. Write only your candidate file under this folder.

Current code is at e1e75d5, with only five incoming generated Xcode/catalog changes.
Read docs/PLAN.md, PRODUCT_PROGRAM.md, SESSION_PROMPTS H3, sync-design traces and
receipt-lifecycle decision, and actual current backend/native callers. Source map:
backend/convex/librarySync.ts folder_delete/restore; lib/librarySyncPolicy.ts;
library.ts legacy writers/readSavedSnapshot; guestMerge.ts; schema.ts folder/marks;
iOS GuestMergePlanner/UserLibraryModel/LibraryProjection and Android equivalents.

Bug: >500 folder members produce unresolved folder_too_large. The physical mutation
clears memberships, stamps a mark per member, stores/returns complete member arrays;
restore looks up deletion marks with take501 and takes complete arrays. The current
native command also sends its locally observed member IDs, capped at500. Server
must restore its actual deleted members, preserve newer moves/removals, resolve
same-name folder recreation/merge, support offline undo and lost responses, and
never claim a partial/capped list as complete. Preserve JWT ownership, durable frozen
frames and exact per-operation receipts. Routine work must finish automatically.

Produce a caller-first type/module sketch and pseudocode, not implementation.
Compare against current exact semantics and identify unavoidable tradeoffs. Native
parity, private recovery/export/deletion, old installed/schema migration and actual
Convex bounds must be explicit. No unbounded scans, writes, arrays or ancestry walks
inside one transaction. At least two materially distinct designs will be judged.

Rubric1-5: (1) exact delete/undo/concurrent move semantics; (2) bounded work and
payload at arbitrary member count/history; (3) restart/retry/ack/ownership clarity;
(4) small deep interface and complete caller migration; (5) real red/green test and
migration path. Reject superficial page wrappers around an unbounded operation.

Workflow checklist: [x] frame/ground parent source trace; [ ] two candidates;
[ ] independent judge; [ ] synthesize; [ ] implement chosen verifiable unit;
[ ] actual local/native proof; [ ] retain deployment/device gates.
