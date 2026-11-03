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
Sentry's privacy policy, grouping, caps and payload remain unchanged. Translation
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
for Bukhari 7 reports `license.kind: unverified`. Its source block is 22,307 bytes,
below the 64,000-byte bound, with nonempty Arabic. The source permission gate,
not a missing comparison, blocks this demonstrated journey. No license was
fabricated or permission check bypassed.

The reader chat completed `3807fe9` before integration. Its paging checkpoint
was preserved when resolving the documentation overlap. The integrated checkout
passes the same 94 focused notification and generation cases plus typecheck.
Hashes of all six incoming regular files remain unchanged. No native test,
build, installation, credential change, migration, publication, push or Sentry
issue resolution occurred for this repair. The approved retry produced no model
generation, so it does not prove provider success.

Next: resolve the source permission blocker, then verify an actual translation
and delivery. Android delivery additionally requires FCM provisioning approval
and actual physical delivery evidence.
The iOS crash needs matching symbols or a reproducing native trace. All original
release, language, accessibility, A7 deferral and reader gates remain open.
The owner's proposed grounding tiers remain research only in
[GEMINI_GROUNDING_DECISION.md](GEMINI_GROUNDING_DECISION.md).
