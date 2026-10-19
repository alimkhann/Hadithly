# A2 integration review, partial stage

Read-only source audit of current uncommitted integration on October 19. No deployment, account call, or implementation edit. Parent is still repairing compile/tests; this is not a final A2 verdict.

## Finding

**P1 — Folder undo can omit memberships that the server actually deleted.** Both native facades capture the folder's member IDs from their current local projection when the user taps Delete (`ios/Hadithly/Core/Saved/UserLibraryModel.swift:336-356`; `android/app/src/main/kotlin/com/hadithly/app/core/data/UserLibraryModel.kt:265-270`). The server `folder_delete` reads the current membership set and returns its actual removed IDs in the `folder_deleted` receipt (`backend/convex/librarySync.ts:76-95`). If device B placed a Saved item in that folder before A's delete timestamp but A has not yet received that subscription update, the delete can validly remove B's member, while A's captured list omits it. Undo then sends only A's old list, so the omitted membership is never restored. Use the accepted delete receipt's IDs for the restore intent (or keep undo pending until it arrives), with the same captured account scope. Test a stale local Saved snapshot where the server deletes one extra member.

The current owner fences otherwise have the right structure for this stage: the new snapshot queries derive the owner from JWT and return an owner key and domain version (`backend/convex/librarySync.ts:276-300`); iOS/Android check owner/session/epoch before caching and applying subscribed values (`ios/Hadithly/Core/Saved/UserLibraryModel.swift:420-441`; `android/app/src/main/kotlin/com/hadithly/app/core/data/UserLibraryModel.kt:295-315`). Persisted overlays use receipt versions until a snapshot reaches them (`ios/Hadithly/Core/GuestData/GuestMergePlanner.swift:325-329,403-423`; `android/app/src/main/kotlin/com/hadithly/app/core/data/LibrarySync.kt:129-170`). I found no additional concrete ownership or query-freshness defect in the inspected paths.

Known unfinished work is not counted as a new finding: compile/test repair, Swift guest-undo proof, note-write feedback, invalid pending admission, local recovery export, large folders/vanished anchors, SDK/account proof, deployment and full cross-device verification remain open. The old public guest-merge path remains for compatibility and is outside this partial core integration verdict.

## Parent resolution and limits

The P1 is repaired by retaining the server's actual deleted-member manifest in the
folder deletion mark. Restore derives its authorized members from that manifest;
the native member list is only an observed hint. The actual Convex test
`folder undo restores actual deleted members even when the native snapshot omitted one`
restores both members after a one-member hint. A second test retains a newer cloud
move even when the caller omits it from its hint.

A new causal-removal test also caught an empty materialized Saved row left by a
refused undo. Refused and losing facet operations now remove empty materializations.
An already-absent removal cannot acquire authority to undo another deletion.

The final integration diff has not received an independent re-review. A subsequent
read-only SDK/deletion consultation failed at the account usage limit before a
report was returned. The parent inspected installed SDK source and bytecode
instead; this is not a substitute for independent review or actual account proof.
