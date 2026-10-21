# Native Saved read boundary implementation review

2026-10-22. Read-only review of generated new wire/parity, transport adapters, captured read context and native boundary policy/tests. No source/repo edits, delegates or cloud calls.

## Concrete finding

### P2: Swift quiet expiry is measured from publisher subscription using an interval captured earlier

`ios/Hadithly/Core/GuestData/GuestMergePlanner.swift` `savedInvalidations` validates savedCapability and computes `(context.validUntil-now())` while constructing the returned publisher. Combine's delayed Just starts that relative delay upon subscription. Retaining the publisher before subscribing therefore extends quiet-stream lifetime beyond the context's absolute validUntil by the retention duration. Also, a publisher created before an owner/session switch can initiate the old transport when later subscribed; current validation runs on its first delivered head, not immediately on subscription.

The new `prefix(untilOutputFrom: expiry).append(Fail(...))` fixes source EOF semantics but retains this earlier construction-time calculation. Wrap source/timer creation in a Deferred publisher, revalidate savedCapability there, and compute remaining lifetime at subscription. Preserve any desired synchronous creation-time validation, but do not use that as the sole subscription admission check. Android flow{} already evaluates its capability and timeout at collection time.

Decisive tests: create a publisher under a valid short-lived context, advance the fixture clock or wait until expired before subscribing, and assert immediate failure with no head transport subscription. Also delay subscription until partway through validity and prove a quiet stream expires after the remaining lifetime, not the original full interval. This is an actual cold-publisher lifecycle consequence, independent of network behavior.

## Parent-identified EOF defect

Inspected actual failing focused logs for both platforms:

- `/tmp/hadithly-saved-head-closed-ios-red.log`: finite empty head source failed to signal completion promptly because merged expiry kept the stream open.
- `/tmp/hadithly-saved-head-closed-android-red.log`: source EOF silently finished rather than signaling renewal/retry failure.

Current source now uses Swift prefix-until-expiry plus appended SessionChanged failure, and Android throws SessionChanged after normal upstream completion within the timeout. These edits address the diagnosed EOF path; this reviewer has not yet inspected their final green run. Android's ensureActive in the TimeoutCancellationException catch preserves outer cancellation instead of converting a cancelled caller into a session error. Add a direct caller-cancellation assertion if the parent wants that precise guarantee independently proved.

## Other source conclusions

- Read context binds captured write generation/session/owner, exact capability string and absolute validUntil. Hydration/fact calls validate context before await and again before delivery, rejecting binding renewal/account-switch late callbacks.
- Head values become a dedicated invalidation type only; policy does not mutate active generation, partition, observed revision, receipt/ACK or retention state.
- Metadata and complete-text types are distinct. Full passage wrapper preserves exact Arabic/English, including whitespace and JSON escapes. Missing/unavailable remain explicit states. Domain policy validates envelope owner/target, nested target identity, required route fields and endpoint wire bounds; unknown unavailable reasons fail.
- iOS production AppEnvironment and Android ConvexRepository call the actual new endpoints with capability/target arguments. Facts/reference/text consume the first SDK query result; no empty-stream success is fabricated. These adapter changes do not migrate production Saved subscription/consumer code.
- Generated wire derives backend validators and parity vectors consume actual Convex replies. Native encoding size uses non-slash-escaping JSON semantics appropriate to the backend's UTF-8 response checks. There is no substring/text truncation.

## Evidence scope

Inspected four new test bodies on each platform: actual wire/parity plus large complete text, owner/target/invalid-head/reason/metadata-size rejection, invalidation without private authority plus quiet expiry, and suspended hydration rejected after binding renewal/account switch. Initial terminal suites pass118 iOS/100 Android in `/tmp/hadithly-saved-reads-ios-first.log` and `/tmp/hadithly-saved-reads-android-first.log`. Those runs predate the additional EOF regression and current fix, so they do not prove final EOF behavior or the newly identified delayed-subscription case.

No additional concrete ownership, text-integrity or private-version-authority defect found. Finish the publisher subscription/expiry fix and focused proof before accepting this boundary. Production observer/read/barrier cutover, Reader exact-target/paged-list/UI behavior, joined full-cache retirement, hosted/installed SDK/device/cross-device paths and recoverable iOS save-failure gates remain open.
