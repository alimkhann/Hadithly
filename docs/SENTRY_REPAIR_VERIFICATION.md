# Sentry notification and translation repair, November 3

## Scope and isolation

The owner requested notification and AI translation repairs from Sentry, using
Terra for code. Work is isolated in `Hadithly-sentry-fixes`, branch
`fix/sentry-notifications-translations-20261103`, based on `8ef463a`.
The concurrent reader chat owns native source, builds, installations and captures.
No reader file, native project, native resource or device setting changed here.

Poteto's bug-fix procedure and Matt Pocock's focused regression approach guided
the work. Separate Before Serializing Shared State led to the sibling worktree.
Fix Root Causes required executable failures before changes. Prove It Works
keeps local checks separate from live delivery and model results.

## Live readback

Authenticated Sentry browser inspection found three unresolved issues across all
projects in the 14-day view:

| Issue | Observed scope |
| --- | --- |
| [HADITHLY-BACKEND-5](https://alimkhan-yergebayev.sentry.io/issues/156430942/) | Ten `generation` events, development. No underlying exception or response retained. |
| [HADITHLY-BACKEND-4](https://alimkhan-yergebayev.sentry.io/issues/155049020/) | One `daily_push` event, October 21, development. No underlying exception retained. |
| [HADITHLY-IOS-4](https://alimkhan-yergebayev.sentry.io/issues/157738077/) | One unsymbolicated native crash, development. The owner authorized sending its details to the reader chat. |

Read-only development configuration checks found Gemini and APNs configured.
All three required FCM environment variables were absent. Five stored push
registrations were Android registrations. No token, key or account identifier is
included in this record. Existing service-generated Russian translations had
both successful and failed attempts. Failures with known usage took roughly one
to two seconds. This does not identify their cause.

The owner then requested physical-device inspection. Device Hub, controlled
through computer use, showed the connected iPhone 16 Pro on Bukhari 7, Volume 1.
It displayed `Не удалось завершить перевод`, `Осталось переводов: 5 из 5`, and
`Повторить`. Viewing this screen did not initiate another model request.
The iOS configuration points to the same development deployment inspected here.
Contemporaneous backend logs contain `AI_INTEGRITY_REJECTED`,
`AI_GENERATION_RETRY` and `AI_SOURCE_UNAVAILABLE` for separate translation requests.
These distinct failures must not be treated as one proven provider defect.
Failed attempts do not consume the successful-translation allowance, so 5/5
remaining is consistent with the recorded failures.

## Repairs and executable evidence

Notification retry state previously counted failures until success, even though
the stated limit is per local date. Three failures could suppress all later
days. A retry from yesterday could also run before today's chosen delivery time.
The optional `lastFailureDate` now scopes counters and backoff to one local date.
Registration, preference changes and success clear that date. Legacy undated
failures resume at the next scheduled window. No backfill is needed.

The cron previously resolved translations before checking provider availability.
An unavailable provider could therefore trigger generation for a push it could
never deliver. The provider check now precedes content and translation resolution.
This matters for the observed development FCM configuration.

Three regressions failed before the fixes:

```text
Yesterday's exhausted attempts: expected due length 1, received 0.
Yesterday's retry before today's window: expected due length 0, received 1.
Unconfigured provider: expected generation count 0, received 1.
```

Real Convex mutation and cron tests also cover repeated daily rollover, initial
backoff on each day, preference and registration reset, and midnight rollover.
Both APNs and FCM continue using the existing platform-neutral payload contract.

AI cost records previously made malformed output and rejected completion
indistinguishable. The existing regression tests failed when they required an
actionable reason. They now pass with an optional validator-enforced reason:
`service_unavailable`, `provider_error`, `invalid_response`,
`completion_rejected` or `completion_error`. Successful and stale outcomes omit
the reason. Raw provider exceptions are excluded. Costs remain recorded once.
At this initial stage, Sentry grouping, caps and payload remained unchanged. Translation
acceptance, source permissions, comparison provenance and allowances are unchanged.
This is a diagnostic repair, not proof that the historical AI failures are fixed.

## Verification and remaining gates

The complete backend suite passed 564 tests across 45 files. Backend TypeScript
checking passed. The suite emits an existing scheduled Saved-folder validator
warning and an intentional analytics failure log; neither failed a test.
Focused notification, generation and diagnostics suites also passed.

The owner approved deploying `90edb59` to development and one physical-device
translation retry. `convex dev --once` completed against `festive-cobra-664`.
The first CLI attempt stopped because this repository has no nested
`convex/tsconfig.json`. The repository's `npm run typecheck` passed, then the
CLI deployment used `--typecheck disable`; it did not skip the repository check.
Production and credentials were unchanged.

After the phone reconnected, the approved Retry tap showed preparation, then the
same failed state and 5/5 allowance. Its new backend request failed with
`AI_SOURCE_UNAVAILABLE` before provider generation. Read-only canonical resolution
for Bukhari 7 initially reported `license.kind: unverified`. This was the effective
result of a missing cache link, not the terms of the existing source license. Its source block is 22,307 bytes,
below the 64,000-byte bound, with nonempty Arabic. The missing source-license binding,
not a missing comparison, blocked this demonstrated journey. No license was
fabricated or permission check bypassed.

The reader chat completed `3807fe9` before integration. Its paging checkpoint
was preserved when resolving the documentation overlap. The integrated checkout
passes the same 94 focused notification and generation cases plus typecheck.
Hashes of all six incoming regular files remain unchanged. No native test,
build, installation, credential change, migration, publication, push or Sentry
issue resolution occurred for this repair. The approved retry produced no model
generation, so it does not prove provider success.

The later source-link repair and successful physical translation are recorded
below. Actual physical notification delivery remains open; FCM provisioning was
subsequently approved and completed.
The iOS crash needs matching symbols or a reproducing native trace. All original
release, language, accessibility, A7 deferral and reader gates remain open.
The owner's proposed grounding tiers remain research only in
[GEMINI_GROUNDING_DECISION.md](GEMINI_GROUNDING_DECISION.md).

## November 4 notification continuation

Read-only checks found the existing production FCM sender configured for the
current Android Firebase project, `hadithlyapp`. The owner approved copying only
`FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL` and `FCM_PRIVATE_KEY` into development
`festive-cobra-664`. Copying used subprocess stdin, with no credential value in
arguments, output, files or git. Destination readback matches the approved source;
production readback is unchanged. No key was created or revoked. This proves
configuration, not provider acceptance or delivery.

Physical computer-use inspection of iOS Settings showed no Notifications category
under Hadithly. No permission or notification preference was changed. The phone
was restored to Hadithly, with Device Hub keyboard capture off. No physical Android
device was attached; one emulator was available. A real delivery check remains
open.

Two real local Convex regressions exposed a registration race. Saving a disabled
choice or 18:37 time before an APNs token existed returned zero updated rows.
The later token registration silently became enabled at 08:00. A further
two-account regression showed the same physical token carried the previous
account's enabled/time and delivery history into its new account.

Commits `327ba4d` and `f791606` fix those demonstrated paths. Explicit enabled/time
choices are now stored on the authenticated account, consistent with the existing
account-wide notification setting. New tokens inherit that choice, otherwise the
latest legacy token's choice through a bounded indexed read, otherwise disabled.
Same-account refreshes preserve the token's settings. Account transfer applies the
new owner's choice and clears the old delivery/retry history. Timezone and locales
remain per device. The optional fields need no data backfill; the added index and
code require a schema deployment.

Commit `c6c0c33` adds portable notification preferences to account export, with no
token or device identifiers. Missing or deleted account preferences export as null.
The full backend suite passed 570 cases before the export assertion extension.
Final integrated notification and export checks passed 28 cases, and typecheck
passed. The focused deletion case emitted the existing asynchronous cleanup
teardown warning; no assertion failed. All six incoming regular-file hashes remain
unchanged. The owner subsequently approved the deployment through `94b0933`.
`convex dev --once` completed against `festive-cobra-664` on November 4 after
repository typecheck passed. Convex confirmed adding `pushTokens.by_user_updated_at`
and reported functions ready. No model request or test notification was initiated.
A fresh HTTPS readback returned `status: ready`, `environment: development`, and
`component: notifications`. That heartbeat health result does not prove delivery.

The owner confirmed source reuse/translation permission exists. That confirmation
is sufficient; no email or additional proof is required. Subsequent inspection
found an already verified source license and a missing link on the cached hadith,
as detailed below.

For the separate native crash, Sentry identifies a missing image debug ID
`e5302d6a-f709-3751-a77c-e85454b0f3c3`, loaded at `0x00010a590000`.
No matching retained app binary or dSYM was found in the Hadithly artifacts,
temporary builds or Xcode DerivedData checked. No Hadithly crash report was found
in the local diagnostic report paths checked. No approximate binary was used for
symbolication. The crash remains undiagnosed, not resolved.


## November 4 successful translation and complete cache repair

The source record `sunnah_now` already held the verified Sunnah.now early-access
license. `confirmSunnahNowDevelopmentLicense` returned it unchanged. Its existing
display, redistribution and offline terms were preserved; the investigation did
not create or broaden a grant. The exact cache inspection instead returned
`pointer: missing` for Bukhari 7. `63e0797` restored only that reference. Readback
then returned `pointer: linked`, `linkedTermsKind: verified`, and a matching
canonical source license. Canonical resolution returned visible authorized text.

After the repair, a single computer-use Retry on the explicitly selected physical
iPhone 16 Pro displayed the Russian Bukhari 7 translation, replacing the failure
screen. The backend cost event recorded `outcome: published`, known token usage
and 7,341 ms duration. No Search grounding was enabled. This proves this live
translation journey; it is not a native-speaker quality approval. The allowance
was visible as 5/5 before generation; a post-success allowance value was not
captured, so no device quota decrement claim is made.

`aa6f5cf` adds an internal mutation repairing only missing or dangling Sunnah.now
license links in pages of at most 100 rows. `18fbfef` adds an internal action
running at most 100 such pages per invocation and returning a resume cursor and
aggregate counts. Both require the named development deployment and an existing
verified display license. Existing valid different bindings count as conflicts
and remain untouched. Other providers, all license terms and hadith content are
preserved. Mutation pagination, reruns, interrupted/resumed action batches,
rights/content preservation and development/page bounds have executable tests.

The integrated checkout also includes merged PR `e31d377`: unknown model-emitted
comparison IDs are ignored without creating citations or a grounding claim;
duplicate offered IDs still fail, and revoked/mismatched references remain
invalid. Sentry receives only an enumerated failure-stage tag and keeps its
existing grouping and report caps. No prompt, response, exception or account is
added to the payload. The integrated backend passed 583 tests across 48 files and
`npm run typecheck`, then deployed to `festive-cobra-664` at 06:35 local time.

The complete live repair scanned 11,998 Sunnah.now rows over 120 bounded pages,
repairing six additional links with zero conflicts. A second complete pass
scanned the same 11,998 rows and found zero repairs and zero conflicts. Bukhari 7
had already been repaired separately. The summary is retained locally at
`/tmp/hadithly-source-license-repair-20261104.json`; raw content, tokens and keys
are absent. Latest bounded cost-event readback showed three published results;
a 100-line recent backend log snapshot contained no `AI_*` error codes. This
short snapshot is not a guarantee of future reliability.

The Mac was locked when further computer use was attempted during continuation.
No automatic unlock succeeded. Physical notification delivery and fresh Sentry
browser readback therefore remain unverified. No device setting, native source,
production configuration, model, Search tool, subscription tier or billing setting
was changed. The original native crash still needs its exact matching symbols or
a reproduction; historical Sentry issues remain open until supported by evidence.


A fresh TLS-verified HTTPS readback at the regional development site returned
`component: notifications`, `environment: development`, `status: ready` after
the final deployment. Five development registrations remain Android, with no
recorded `lastSentDate` or consecutive failure count; no iOS registration exists.
These metadata checks do not prove provider acceptance or physical delivery.
The six incoming regular-file SHA-256 hashes still match the preservation record.


## Native registration-path review

Terra traced both native opt-in paths without changing native code. On iOS,
`SettingsDestinations.swift:816` calls `requestAuthorizationAndRegister` when the
signed-in user enables Daily hadith. `PushNotificationManager.swift:44` requests
OS authorization and registers with APNs; the app-delegate callback saves and
uploads the token. `AppEnvironment.completeSignIn` replays an existing token after
account setup. A new install does not request authorization merely at sign-in.
The absent OS Notifications entry and zero iOS tokens therefore do not by
themselves prove a registration defect. The actual OS prompt and callback still
need a device check.

On Android, `SettingsScreen.kt:856` requests/saves the FCM token when enabling;
API 33+ first uses the notification-permission launcher. Startup registration and
auth replay also exist. The backend preference repair covers asynchronous token
arrival relative to preference saving on both platforms. Source review found no
additional proven defect requiring a speculative native change. It does not
replace physical foreground/background/terminated delivery checks.


Independent GPT-6.1 Terra review checked the retained scan summary and commit
pointers, with no contradictory counts. The reviewer did not independently view
the earlier physical translation or deployment output; those claims rely on this
chat's contemporaneous device screenshot and CLI readback. The review also noted
that iOS currently ignores token-upload errors with `try?`; no evidence connects
that limitation to this device, so it was not changed speculatively.


## November 4 physical notification and onboarding continuation

After device access returned, computer use showed the existing Daily Hadith switch
off. Fresh authenticated Sentry readback showed 13 generation events, two total
daily-push events (latest `d221bb6e2ad54934a12ee6463b3a734c`, November 4 at
03:12:30 UTC), and the same single older iOS crash. No provider cause was retained
in that push event. The development registrations had fallen from five Android
rows to one, with `lastSentDate: 2026-11-04`, no consecutive failures and no retained
error. This proves a recorded provider send, not Android physical receipt, and
does not establish why the four former rows disappeared.

`f1f0cab` distinguishes known dead-token responses from malformed requests.
Confirmed FCM `UNREGISTERED` and APNs bad/unregistered-token responses are removed
without an error report. Ambiguous `INVALID_ARGUMENT`, topic mismatch, auth and
backpressure remain observable. Google documents that INVALID_ARGUMENT can also
mean an invalid payload, so treating every such response as a dead token could
delete a usable registration ([FCM error codes](https://firebase.google.com/docs/cloud-messaging/error-codes),
[token management](https://firebase.blog/posts/2023/04/managing-cloud-messaging-tokens)).
A failing-before real cron regression distinguished these paths. The integrated
backend then passed 587 tests and deployed to development through `f1f0cab`.

The owner approved temporary iPhone opt-in and exactly one cached APNs test,
restoring the app reminder off afterward while leaving OS authorization allowed.
`e92513f` provides the internal development-only test action: one enabled iOS token,
existing permitted Russian Bukhari 7 translation, normal payload builder, fixed
status only, no AI generation or preference writes. The selected iPhone registered
successfully. The one test returned `accepted`; Device Hub showed the Russian
Bukhari 7 notification in Notification Center under Do Not Disturb at about 12:28.
Tapping it opened Bukhari 7, Volume 1, with the Russian text. Focus was not changed.
This is physical background delivery and exact-target open evidence, not the full
N1 foreground/terminated/DST/accessibility matrix. No second test push was sent.

The physical preference attempt exposed a separate iOS response bug: the backend
stored enabled=true, but the UI showed off and “Could not save notification
settings.” Convex Swift's no-result mutation overload decodes `String?`; this
mutation returns a numeric row count. `93b4009` changes the call to decode Double,
as Android already does. The server write and retained iOS token were read back
without exposing the token. The corrected signed development build was installed in place. On the physical
iPhone the switch saved, showed Device registered and 08:00, then saved off
without the error. Readback confirmed both the account and iOS registration
were disabled at 08:00. OS authorization was left allowed as agreed.

The owner additionally requested notification permission on first Today landing
after onboarding, and explicitly confirmed that Allow should enable Daily Hadith
at the saved/default 08:00 time. Native work is isolated in
`Hadithly-notification-onboarding`; no Reader source is changed. The backend
`1f86b5c` fences optional notification writes with the existing account capability.
`1c98fd1` adds an atomic initializer: first-time accounts enable, existing explicit
or legacy choices are preserved, and a repeated onboarding retry cannot overwrite
a later Settings change. Optional token origin distinguishes new default-off
registration from an explicit choice, including Android token-first registration.
Old unmarked rows conservatively retain their legacy choice; no data backfill or
new grant is inferred.

The integrated backend passed 590 tests across 49 files plus repository typecheck.
The owner approved this schema deployment; `convex dev --once` completed against
`festive-cobra-664` at 12:35, adding the bounded origin index. A fresh TLS-verified
regional notification health read returned ready/development. Production stays
unchanged. Native onboarding is committed as `6694486`. Five iOS Today tests
passed on iPhone 18 Pro simulator. The Android Today JVM test and guarded
SharedPreferences fixture passed on emulator-5554. Two isolated Android app
identities then showed the actual system prompt over Today after guest onboarding.
Both Allow and Deny returned to Today without a repeat after activity recreation.
Separate ad-hoc signed iPhone 18 Pro simulator app identities also showed the
system prompt over Today after guest onboarding. Allow and Deny both returned
to Today and did not repeat after termination and relaunch. The simulator and
emulator runs used dummy configuration and preserved the retained app identity.
The iOS Allow run retained the guest intent after relaunch. Signed-in
initialization is covered by the backend tests. Captures and logs are
in `/Users/alim/Developer/Artifacts/Hadithly/onboarding-notifications-20261104`.
The physical iPhone build used for the Settings recheck precedes the onboarding
commit. Physical Android delivery remains unverified.

Device Hub's current Crashes filter returned no Hadithly result. An updated scan
of retained artifacts and DerivedData included DWARF files, app executables and
`Hadithly.debug.dylib`: 78 candidates, none with the missing debug UUID. The older
native crash remains unresolved; no approximate symbol file was substituted.
