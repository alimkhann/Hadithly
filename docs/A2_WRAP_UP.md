# A2 normal-use wrap-up

October 25, 2026. The owner asked to end the expanding storage work and focus on
ordinary use and visible product improvements. This record supersedes unfinished
cutover instructions in older A2 design and verification documents.

## Decision

The existing production integration is the A2 implementation. Both native apps
persist account edits before sending, retain edits through offline restart and
delayed server reads, and reject stale account callbacks and actions. Bookmarks,
favorites, notes, folders, Undo and reading position use that path. The underlying
race repairs are committed; no additional storage implementation was needed during
this wrap-up.

Keep the shared Saved presentation. Leave row mode off. Defer runtime/UI wiring
of the alternate row-backed storage, additional point-admission machinery,
501-/2,001-item performance work and injected recoverable iOS disk-save failure.
Preserve the already tested components without activating or expanding them.

## Focused verification

The October 25 runs use the real native local stores and production library
facades with controlled RPC/read streams. They are local checks, not Clerk/network
or cross-device proof.

| Check | Result | Evidence |
| --- | --- | --- |
| iOS normal-use facade/store checks | Six pass | `/tmp/hadithly-a2-wrap-ios.log`, `/tmp/hadithly-a2-wrap-ios.xcresult` |
| iOS reader Saved tabs, preview, exact navigation and note editor; latest reading-position selection | Two pass | `/tmp/hadithly-a2-wrap-ios-ui.log`, `/tmp/hadithly-a2-wrap-ios-ui.xcresult` |
| Android normal-use facade/store and native Saved UI checks | Eight pass | `/tmp/hadithly-a2-wrap-android.log` |
| Backend sync, held-frame and public-folder checks | 58 pass | `/tmp/hadithly-a2-wrap-backend.log` |
| Backend strict typecheck | Pass | Executed before the focused backend tests |
| Generated native sync wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |

The paired facade tests cover a bookmark, favorite, private note, folder placement,
folder deletion/Undo, reading position and store reopening with pending edits.
They also cover accepted notes under delayed snapshots, late reads and stale Undo
after switching/signing out, explicit removal of an absent bookmark, oversized
note rejection, guest edits arriving during sign-in and writes captured for an
account that has since changed. Both platforms render the reader Saved tabs/editor.
iOS verifies preview and exact-row navigation; Android verifies that preview and
action menus do not navigate.

## Remaining acceptance check

Normal-use implementation is wrapped. Full live A2 acceptance remains open until
the new sync backend is deployed to development and actual authenticated
iOS-to-Android and Android-to-iOS writes are read back. The existing request for
action-time approval covers development `festive-cobra-664`, compatibility
inspection and isolated test-account writes. Approval is pending. No A2 rollout,
private test write, production change or paid generation was performed here.

Before an approved rollout, inspect existing development sync-stream shapes and
handle incompatible records without discarding data. Then exercise normal saving,
note editing, folder/Undo, reading position and account switching through the
actual SDK paths. Fix a reproduced normal-use failure directly. Do not add a new
storage architecture as a prerequisite.

Existing deletion/SDK propagation, marker retention, installed-client, physical
device, A1 content and release gates remain in their own records and
`OPEN_GATES.md`. They have not passed through this scope change. The next product
priority is A3 grounding/source quality, then the remaining reader/localization
defects in `PRODUCT_PROGRAM.md`.
