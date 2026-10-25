# A2 normal-use wrap-up

Updated October 26, 2026. The owner asked to end the expanding storage work and focus on
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

## Development acceptance passed, October 26

The owner approved the development rollout, compatibility inspection and isolated
native test-account writes. The exact tested A2 snapshot `e657024` was deployed to
`festive-cobra-664`, excluding later A3 changes. Before rollout, the stream-shape
readback found zero records, no truncated scan and no legacy/unknown slots. The
post-deploy readback agrees. No records needed migration. Evidence:
`/tmp/hadithly-a2-dev-preflight.json`, `/tmp/hadithly-a2-dev-deploy.log` and
`/tmp/hadithly-a2-dev-postflight.json`.

The first live iOS write and Android read/edit/Undo phases pass through the actual
Clerk and Convex SDKs and production app coordinators. Their notes, bookmark,
favorite, folder placement/restoration and reading position are verified in owned
server snapshots. Android-to-iOS return readback, iOS sign-out/stale actions, the iOS second-account
read after relaunch, and Android same-process account switching also pass.

The Android run reproduced a real sign-in failure: Convex's numeric `2.0` could
not decode into `ReaderPreferences.schemaVersion: Int`. A field serializer now
accepts integral doubles and old integer JSON without truncating fractional or
out-of-range values. The preference DTO regression failed before the fix and
passes after it; all 213 Android unit tests pass. Evidence:
`/tmp/hadithly-a2-preferences-red.log`, `/tmp/hadithly-a2-preferences-fixed.log`.
The actual native read/edit/Undo phase passes after the fix in
`/tmp/hadithly-a2-native-android-numeric-fixed.log`.

Live tests are explicitly opted in using expiring private configuration files and
the development deployment/publishable key. They refuse to replace an unrelated
existing session. Two dedicated test addresses use
[Clerk's documented test-email code flow](https://clerk.com/docs/guides/development/testing/test-emails-and-phones),
which sends no verification email. An initial Android harness attempt omitted its
required second-factor step; the test now completes the SDK's offered email-code
factor. The successful iOS second-account lane uses first-factor email code. This
does not change application authentication policy. An earlier file copy failed and
that instrumented run skipped; it is not live acceptance evidence.
No production change, real-account deletion or paid AI call was performed.

Existing deletion/SDK propagation, marker retention, installed-client, physical
device, A1 content and release gates remain in their own records and
`OPEN_GATES.md`. They have not passed through this scope change. The next product
priority is A3 grounding/source quality, then the remaining reader/localization
defects in `PRODUCT_PROGRAM.md`.


| Live boundary | Passing evidence |
| --- | --- |
| iOS production coordinator sends bookmark, favorite, note, folder placement and position to an owned server snapshot | `/tmp/hadithly-a2-native-ios-write.log`, `.xcresult` |
| Android reads the iOS data, edits the note, restores bookmark/folder through Undo and updates position | `/tmp/hadithly-a2-native-android-numeric-fixed.log` |
| iOS reads the Android note, restored facets/folder and offset, then rejects stale actions after sign-out | `/tmp/hadithly-a2-native-ios-read-signout.log`, `.xcresult` |
| Fresh iOS launch signs into the second account, reads its empty owned snapshot and rejects a retained first-account scope | `/tmp/hadithly-a2-native-ios-second-email.log`, `.xcresult` |
| Android switches between both real test accounts, rejects old scope and confirms the first-account bookmark removal | `/tmp/hadithly-a2-native-android-final.log` |

The final iOS opt-in branch is named `ios-read-and-signout`; its passing read/sign-out
artifact used the earlier name `ios-read-and-switch`. iOS same-process direct-SDK
password/MFA and immediate re-login attempts returned `resource_not_found` during
verification preparation. Those attempts failed and are not counted as acceptance
passes. This remains an auth investigation on the LA2/A5 track. The app's hosted
sign-in journey was not exercised by these SDK-only fixtures. The iOS Saved scope
change is proved after relaunch with a second authenticated account, plus the
existing same-process controlled-transport regression. Do not claim the complete
physical/hosted-auth matrix passed.

For a new isolated fixture run, execute `ios-write`, `android-read-write`,
`android-provision-second`, `ios-read-and-signout`, `ios-second-account`, then
`android-final`. The provisioning step creates only the second dedicated account.
Never use these phases with a real reader account. The private configuration must
have a future `expiresAt`, the exact development URL, and test-mode publishable key.
Android additionally requires `-e a2Live 1`. Missing/expired configuration skips.

Private test credentials and opt-in files were removed from both native app
containers and the local driver after verification. Both successful account checks
sign out. The two dedicated development accounts and synthetic Saved data remain
for operator inspection; they contain no real reader notes. No production account
or content was deleted. The exact deployment snapshot is recoverable at `e657024`.
The isolated deployment worktree was archived after readback. A final iOS check
passes the offline/reopen and late-account-callback regressions and confirms the
live test skips after its opt-in file is removed. Evidence:
`/tmp/hadithly-a2-wrap-final-ios.log` and `.xcresult`.
The final Android native runner also skips the live test without `a2Live=1`;
`/tmp/hadithly-a2-wrap-final-android.log` confirms its default opt-in boundary.

A2's agreed normal-use synchronization gate is complete. Keep the deferred scale
work deferred. The next program work is A3; physical devices, hosted authentication,
installed release compatibility, account-deletion/retention and the other release
tracks retain their own gates.
