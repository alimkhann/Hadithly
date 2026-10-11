# E4 verification

Updated 2026-10-11. E3's development pass was confirmed from its plan, verification,
and review records. E4 implements only evidence lifecycle work. Stop before Q1.
E1's remaining device matrix and the earlier release gates remain open.

## Local proof

| Gate | Evidence |
| --- | --- |
| Backend | Typecheck and 257 tests across 22 files passed. Real Convex test mutations/actions exercise the production handlers. |
| Automatic reports and appeals | Owned, idempotent appeal publication; report dismissal; incomplete comparison recovery; stale concern-batch retry; exact 30-day boundary; successful replacement without premature rejection clock; source-policy renewal and dependency deletion rechecks. |
| No required approval queue | Cases resolve or expire. Provider failures and worker timeouts have three total attempts; waiting consumes none. Unknown rights fail before model disclosure. |
| Abuse and spending | Five submissions/reports and three appeals per account per rolling day; concurrent report deduplication; withdrawal cannot reset admission. Six review pairs per target per 30 days, 100 anonymous global pairs per rolling day. Account deletion cannot reset the global ceiling. |
| Operator | JWT identity and server operator role reread on every call; required typed reason; current-version check; no publish or gate-waiver command. Unauthorized users fail. |
| Immutable audit | Typed insert-only facts retain opaque receipt, verified actor role, reason, coarse before/after state, lifecycle/publication policy revisions, and model revisions. Takedown/account deletion do not change earlier facts. Private identity mappings are erased. |
| Revocation and deletion | Permission changes fail public/default/notification-comparison reads before fanout. Prior defaults must pass current validity. Takedown invalidates late results and removes translation, proposal, storage, OCR, grants, report/appeal text, review quotes, and cases. Retention has bounded continuations. |
| Legacy migration | Two development community publications without evidence were withdrawn. The repeat migrated zero rows. A regression proves the private appeal window, idempotency, and eventual content deletion. |
| Consumer absence | Native source scan rejects operator endpoints, role queries, and retired admin navigation. Settings remains unchanged. |
| iOS | 222 unit tests, zero failures/skips, `/tmp/hadithly-e4-regression.xcresult`. Three production status/source/appeal UI tests passed in `/tmp/hadithly-e4-ui.xcresult`, including 44-point targets. |
| Android | 194 unit tests, zero failures/errors/skips. Debug and instrumentation builds passed with JDK 21. Five production status/source/appeal emulator tests passed in `/tmp/hadithly-e4-android-ui-final.log`, including the repaired 48 dp appeal target. |
| Offline | E3 still denies version-1 translation-pack manifests/exports. Both native readers now also suppress previously installed pack text because entry rights and revocation identity are absent. Licensed base dumps are unchanged. |

## Blast-radius review

Two independent read-only reviewers inspected the diff. One reproduced four
backend findings against real Convex handlers. Repairs cover report arrivals
during review, orphaned timeout retries, coalesced appeal explanations, and the
rejection clock after a successful replacement. The other found allegation-only
suppression of official text, separate permission deadlines, and installed pack
bypass. Accepted repairs are in the production code and focused regressions.

Public reads share one validity predicate. It checks current rights, revision and
output binding, abuse/deletion state, source avoidance, and comparison ancestry.
Native loaded translations subscribe to availability and clear content/citations.
Each permission deadline is enforced locally, even without a database mutation.
Public reads also recheck retained clean item/storage bindings and current
source-access scopes, independently of affirmative artifact reuse rights. A
deleted source blob or a narrowed Sunnah.com access scope fails closed. Stream
completion clears loaded text, and iOS restarts its watcher when the reader resumes.
Expiry and takedown delete the entire private submission record, including its
owner and target links. A request for an erased ID returns an empty expired
projection without keeping a linked tombstone. Repeated withdrawal is idempotent.

## Development and live proof

The owner approved development deployment, legacy migration, and disposable native
checks using the existing private processor and paid Gemini setup, with at most
24 model calls. `npx convex dev --once` deployed to `festive-cobra-664`. Production,
IAM, billing settings, credentials, and Cloud Run configuration were unchanged.

The opt-in proof uses self-authored synthetic text and real native Clerk sessions.
Each client uploads a PNG, observes actual private OCR and independent review,
reports the resulting translation, observes automatic resolution and withdrawal
of the old publication ID, then appeals a seeded adverse fixture decision through
the real owned API. The seeded decision does not fabricate model results, scan
facts, or rights. Actual appeals still pass the complete E3 publication gate.

The first live run held both fixtures because the challenge model omitted the
Arabic comparison despite confidence 1. The publication gate correctly refused
them. The request now requires the complete comparison count and IDs through
Gemini's [structured-output schema](https://ai.google.dev/gemini-api/docs/structured-output),
and incomplete judgments receive bounded automatic retries. The publication
predicate and strict greater-than-0.95 threshold remain unchanged.

Both signed-in complete flows passed without skips. Android reports `OK (1 test)`
in `/tmp/hadithly-e4-android-live2.log`. iOS passed in
`/tmp/hadithly-e4-ios-live3.xcresult`. The controller recorded 16 accepted passes
from 22 actual model requests, within the owner's 24-call ceiling. Additional
passes exercised malformed-output and stale-permission recovery. Models remained
`gemini-3.8-flash` and `gemini-3.5-flash-lite`; publication policy is
`e4-review-v1`, lifecycle policy is `e4-v1`.

`/tmp/hadithly-e4-native-controller3.log` confirms fixture cleanup and preservation
of existing user, evidence, translation, and case IDs. Synthetic hadiths, private
bytes, extraction text, grants, pass quotes, publication revisions, reports,
appeals, cases, and target spend records were removed. Detached non-sensitive
audit facts, one-day admission counters, and anonymous global spend events remain
under their documented retention. No ticket or credential was created or copied.

The recovered fixture is restored through the owner-only target query rather than
uploaded again. Both production forms use the same owned status recovery when
local draft metadata is absent. Source setup is idempotent so it does not refresh
permission timestamps during a claimed review.

The proof controller initially counted malformed pass rows as a completed report.
It now requires an actually resolved report case before seeding the adverse
decision. Its old synthetic state was repaired through a fresh guarded recheck,
never by marking a contribution published. Both native clients then completed
the real report and appeal paths under the same spending ceiling.

## Gate result

E4 passed in development. Automated resolution, absence of a mandatory queue,
operator authorization, appeal boundary, abuse limits, immutable audit,
revocation propagation, deletion, and consumer-app absence have direct local or
native integration evidence above. Final native regression readbacks are recorded
below. Stop before Q1.

## Limits and remaining gates

Final regression: backend typecheck and 257 tests passed; the final development
push succeeded. iOS passed 222 unit tests without skips in
`/tmp/hadithly-e4-regression.xcresult`. Android passed 194 unit tests, debug and
instrumentation builds. Its final five UI tests passed in
`/tmp/hadithly-e4-android-ui-regression.log`. Both disk-backed pack regressions
activated a real version-1 artifact and proved the reader did not expose its
community text while licensed base Arabic remained readable.

This is a development evidence gate, not a production launch claim. Connected
clients clear revoked loaded text. A disconnected device or an already delivered
notification cannot be recalled by a server mutation. Community text is not
exported into unvalidated durable packs, and Daily widgets exclude it. O2 still
owns a rights-preserving pack format. Wave 1 native-speaker QA remains in L1.
Earlier E1, sync, physical-device, widget, store, sandbox, push, and release gates
remain in `OPEN_GATES.md`.
