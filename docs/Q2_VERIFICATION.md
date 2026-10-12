# Q2 subscriptions, pricing, and free-generation protection

Date: 2026-10-12. Q2 implementation and approved development rollout are
complete. The full two-store sandbox gate remains open; L1 has not started.

## Scope and authorization

D3A's operational Apple/RevenueCat setup passed; its legal, compliance and
sandbox release handoffs did not. D3G remains explicitly deferred because the
owner has no Play developer account. Q1's local, development backend and Apple
hardware gates passed; its complete authenticated-device/Play gate did not.
The owner directed Q2 to proceed with those gaps recorded, rather than declaring
the prerequisites passed.

After seeing the cost table, the owner approved the exact 175 Apple regional
tiers in `q2-pricing/`, and explicitly approved a $2/month free/service generation
pool inside the existing $10 aggregate ordinary-generation budget. The owner
delegated selection of the margin floor; the selected 60% paid-unit floor
excludes free-user subsidy and fixed overhead. Development deployment,
existing RevenueCat subscriber-read key installation, equal Apple subscription
levels, multiseat off and 16-day paid-renewal sandbox grace were explicitly
approved. Production deployment, paid-plan upgrades, legal acceptance, store
submission and L1 were not performed.

## Implemented behavior

Convex reconciles RevenueCat's current subscriber snapshot, rather than granting
from webhook product names or the last event. Exact registered Apple/Play
products, `pro`, purchased ownership, environment and finite deadlines determine
access. Any valid overlapping purchase provides one shared rolling allowance.
Clients cannot supply identity or entitlement state. The previous direct tier
writer and its callers are removed.

| Lifecycle | Result | Evidence |
| --- | --- | --- |
| Purchase / renewal | Current eligible receipt grants 100 new generations in seven days. | Real HTTP/action/mutation/query boundaries in `subscriptions.test.ts`, deterministic subscriber transport. |
| Cancellation | Access continues until paid expiry. | Snapshot and quota integration cases. |
| Grace | Explicit store grace extends the finite deadline. | Paid expiry/grace transition integration cases. |
| Hold / expiry | No access beyond paid or explicit grace time; no delayed webhook is required for quota enforcement. | Current-time access evaluation and expiry cases. |
| Refund / revocation | Critical delivery suspends pending reconciliation; refunded or revoked current state cannot grant. | Signed delivery, fresh snapshot and denied quota cases. |
| Overlap / stale event | One store's terminal event cannot permanently remove the other valid purchase; newest refresh wins. | Concurrent refresh and overlapping Apple/Play cases. |
| Restore / account switch | Original Hadithly account only; stale completions never unlock another account; all restore paths end. | Both native gates, actual Swift manager transport harness, installed native UI tests. |
| Family / shared device | Family-owned snapshots cannot grant; one store account does not grant every Hadithly account. | Parser/transfer tests; original-account RevenueCat configuration readback. |
| Replay / outage | Atomic durable enqueue, completed replay no-op, bounded retry, hourly failed/stalled-worker recovery. | Backend queue/action tests and signed live development HTTP replay. |
| Delete / retention | Retry bindings are erased with the user; stale actions cannot recreate it. Receipt identifiers expire after 90 days. | Backend deletion/recovery/retention tests. |

Both native apps serialize SDK login/logout with purchase/restore and clear
visible state immediately on account change. They persist unresolved purchase
ownership before starting the SDK operation. Relaunch pins the SDK to that
owner until receipt settlement; another account cannot silently claim an
unfinished purchase. Corrupt local ownership storage fails closed. A cancelled
retry does not erase an older unresolved purchase. The stored owner is private
device state and remains until the pending operation resolves; lost/deleted
original accounts require exceptional recovery. Actual interrupted store receipt
delivery remains a sandbox acceptance row, not a claim made from persistence tests.

Settings has manage/restore and origin-store guidance. The quota rejection is
the only paywall entry. Free and Pro quotas use clear rolling-seven-day copy,
cached reading stays available, weekly/family plans are absent, and exhausted
Pro accounts can continue reading without an endless upgrade/retry loop.
Existing English, Arabic and Urdu UI resources carry the new copy on both apps.

## Verification artifacts

| Check | Result / artifact |
| --- | --- |
| Backend | Typecheck and 313 tests across 26 files pass. `/tmp/hadithly-q2-backend-final.log`; `subscriptions.test.ts` and `quotas.test.ts` retain lifecycle, race and budget regressions. |
| Free budget blast radius | Atomic admission/settlement protects paid headroom; budget-denied free requests do not consume shared provider-attempt slots. Unknown cost retains its reservation. |
| iOS | Full suite before the final persistence addition: 232 executed, four opt-in live skips, zero failures. Final focused four purchase tests pass, including compilation of the opt-in real-store read/purchase tests. `/tmp/hadithly-q2-purchase-final5.xcresult`. Physical signed device build also passes. |
| iOS installed UI | Five tests pass, zero skips/failures: Q1 reading/quota continuity plus the real Q2 quota sheet and failed restore. iPhone 18 Pro / iOS 27 simulator `40FDE642-C9F1-46C4-83E3-4D2469BDE3A6`; `/tmp/hadithly-q2-ios-ui4.xcresult`. |
| Android | 198 unit tests pass, zero failures/skips. Two installed Q2 tests pass on `hadithly`, Android 16, `emulator-5554`, including actual SharedPreferences relaunch/corruption. `/tmp/hadithly-q2-android-final-complete.log`. JDK 21. |
| SDK ownership boundary | `scripts/verify-q2-purchase-queue.sh`: six checks pass using the actual Swift manager and deterministic Clerk/SDK transport. This is not a store sandbox substitute. `/tmp/hadithly-q2-queue-final.log`. |
| Live development | Latest approved code deployed to `festive-cobra-664` with sandbox-only backend policy, exact Apple app ID, $10 total/$2 free caps and existing read key. `backend/scripts/verify-q2-live.mjs` passes actual RevenueCat GET, signed HTTP queue/replay, finite fixture projection and cleanup. `/tmp/hadithly-q2-live-final.log`. CLI fixture identity is not real Clerk or store purchase proof. |
| Regional pricing | All 175 monthly and annual Apple tiers pass the selected 60% floor: lowest monthly 78.6%, lowest annual 71.7%. Official/export deductions, 30% commission stress, 15% FX haircut and typical quota bursts included. `/tmp/hadithly-q2-pricing-final.log`; rerun command in `Q2_PRICING.md`. |

Live fixtures preserved the existing account IDs and erased private development
fixture records. One empty RevenueCat verification profile has no personal data
or store transactions. No paid Gemini request was needed for Q2 checks.
Secrets, downloaded keys, signed artifacts and result bundles remain outside git.

## External readbacks and remaining gate

Apple monthly/annual IDs are `com.hadithly.app.pro.monthly` and
`com.hadithly.app.pro.annual`. Both are level 1, App Store only, multiseat off,
Family Sharing off, and Prepare for Submission. Grace is 16 days, paid-to-paid,
sandbox only. The owner created one US sandbox tester; App Store Connect
readback confirms its storefront without retaining credentials.

RevenueCat's default offering contains only the actual Apple monthly and annual
packages. Restore behavior is saved as “Keep with original App User ID”, without
a sandbox transfer override. No new privileged API key was created; the existing
Apple SDK key supports the subscriber GET used by this implementation.

The catalog had a second legacy entitlement, “Hadithly Pro”, attached only to
Test Store weekly/monthly/yearly products. Those obsolete links were detached
reversibly and that entitlement was made inactive. The active entitlement list
now contains only `pro`, with both real Apple plans and the two retained Test
Store monthly/annual products. The Apple-key subscriber offerings GET still
returns exactly the registered Apple monthly and annual packages. The unused
Test Store weekly product is inactive; readback confirms it is absent from the
active product list.

The physical product-read test was started on `alimkhan`, iOS 27.0.1, but Xcode
cannot launch it while the device is locked. The owner was asked to unlock it
and sign in to the development app and sandbox tester. Rerunnable opt-in tests
are `PurchaseQ2LiveTests`; `Q2_LIVE_STORE_READ=1` reads real StoreKit products and
`Q2_LIVE_STORE_PURCHASE=1` runs the real monthly purchase, backend Pro/100 check
and original-account restore. Apple's confirmation is completed on the device
by the owner. Neither test has passed yet.

A new RevenueCat webhook draft points to
`https://festive-cobra-664.eu-west-1.convex.site/webhooks/revenuecat`, Sandbox
only, all event types. It is not saved: transmitting the existing development
Authorization credential to RevenueCat requires the specific approval requested
in this session. No credential was entered before that approval. This does not
affect the passing signed development HTTP tests, but real RevenueCat sandbox
callbacks require the integration.

Reproduce the physical read after unlocking the device and signing in:

```sh
TEST_RUNNER_Q2_LIVE_STORE_READ=1 xcodebuild \
  -project ios/Hadithly.xcodeproj -scheme Hadithly \
  -destination 'platform=iOS,id=00008140-001A24A01488801C' \
  -derivedDataPath /tmp/hadithly-q1-device \
  -clonedSourcePackagesDirPath /Users/alim/Library/Developer/Xcode/DerivedData/Hadithly-betzezfbgwsvcjehkzzgdxiskzhx/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -only-testing:HadithlyTests/PurchaseQ2LiveTests/testRealAppleOfferingLoadsForVerifiedHadithlyAccount \
  test-without-building
```

The existing physical `build-for-testing` result contains both live test
methods. Only run the purchase method with the US sandbox tester signed in and
the owner present for Apple's on-device confirmation; use
`TEST_RUNNER_Q2_LIVE_STORE_PURCHASE=1` and its exact method name above.

Apple rejected disabling Streamlined Purchasing because the latest approved
binary lacks the required StoreKit APIs. The installed SDK contains purchase
intent support, but an approved updated binary is a separate release action.
The unchanged production webhook still points to `giddy-ox-648`; Q2 code has
not been deployed there.

Before Q2's full gate can pass, record actual Apple and Google store receipts
and callbacks for purchase/renewal, cancellation, grace, hold, expiry,
refund/revocation, restore, account switch, shared-device ownership and an
interrupted purchase/relaunch. Include real cross-platform access and quota
retry. Google additionally needs its developer account, actual products/base
plans, SDK key, testers and complete regional export/approval. Apple legal and
compliance handoffs remain D3A release work. Local lifecycle fixtures and signed
development HTTP tests do not close those external gates. Stop before L1.
