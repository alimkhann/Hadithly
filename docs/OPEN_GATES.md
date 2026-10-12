# Open gates

Updated 2026-10-12 from the current plan, dashboard checklist, and E3 checks.
This is a record of outstanding proof, not a fresh production dashboard audit.
Later session records take precedence over older unchecked boxes and summaries.

## Completed or implemented sessions with remaining gates

| Session or track | Still open | Existing evidence |
| --- | --- | --- |
| D1 / D2 | Physical Android FCM retest against `hadithlyapp`; Apple sign-in full round trip and the remaining physical auth matrix roll into D4. Sunnah.now production read is still recorded as unverified and its rotation is owner-waived. | Production Gemini, FCM credential minting, and Apple-accepted APNs passed. The old provider rotation waiver is not reopened here. |
| D3A | Apple agreements, tax/banking, compliance/content-rights answers, review account/instructions, and store sandbox purchase/restore/expiry/refund/quota retry. Screenshots and listings remain for L1. | Domain, Apple product setup, RevenueCat offering/webhook, and operational Apple wiring passed. |
| D3G | Play Console account and store setup, signing/App Links fingerprint, Play subscriptions, RevenueCat Android production key, test tracks/testers, and sandbox lifecycle. | Explicitly deferred by the owner until a Play developer account is available. |
| F3 | Production fallback deployment/readback and release Android App Links verification. | Native routing and local fallback tests passed. The record still carries the live fallback deployment handoff; D3G supplies the Play signing fingerprint. |
| R3 | Reader direction, paging, long-content, boundary, and accessibility matrix on physical iPhone and Android. | Simulator/emulator matrices passed. Later reader work continued under the owner's exceptions. |
| F2 / R4 | Physical-device confirmation of preferences, typography, visibility, RTL, and accessibility through D4. | Native unit and simulator/emulator checks passed. R4's named review passed. |
| H3 / private sync follow-up | The reported missing cross-device Saved/progress sync must be reproduced, repaired if needed, and proved in both directions. | H3's native migration and interaction checks passed. The separate 2026-09-30 sync report remains unresolved in the plan. |
| O1 | Production-grade confirmation of content permission scope, including adaptation and redistribution where used. | Licensed development dumps and checksum/schema tests passed. The earlier MIT/local-use wording is not treated as blanket rights for every later use. |
| O2 | Translation packs need a versioned per-entry rights, attribution, and citations format before export, plus a real download/read/update/rollback proof. Version 1 pack generation is now blocked by E3 licensing checks; base dumps remain available. | Base collection downloads, offline reading, corruption/rollback fixtures, and physical iOS stalled-network recovery passed. |
| N1 | Physical locale/timezone/DST, retry, stale-target, selected-language, receipt, and exact-open matrix; physical Android FCM retest. | The development APNs request was Apple-accepted. Owner receipt/exact-open confirmation and the broader device matrix remain open. |
| W1 / W2 | iOS locked rendering, empty first install, exact nonzero restoration; synced widgets; offline and deleted-download behavior on both platforms; remaining iOS stale cases. | Installed iOS gallery/tap and Android guest offset/stale behavior have evidence. The full widget gate is not passed. |
| E1 | iOS progress/cancellation and account-switch tests; RTL and assistive-technology device matrix. | Signed-in native intake, private upload, withdrawal, and local recovery passed. E2 proceeded under an explicit owner exception. |
| E3 | Production provider-rights coverage and release rollout remain with O1/D4. | Development passed: 232 backend tests, 219 iOS units, both native upload/OCR/review/publication/readback paths, production status/source UI fixtures, private cloud controls, 14 Linux tests, and two final clean adversarial reviews. |
| Q1 | Authenticated Android generation/cache/allowance and physical iPhone Clerk-to-generation journey need a development login. Play Integrity decode/native round trip is explicitly deferred until Play Console exists. Production remains release work. | Development deploy/migrations, preserved existing rows, actual five-free/reject/upgrade retry and service quotas, iOS authenticated simulator, Android live guest cache, real physical Apple attestation/assertion/replay checks pass. Ten global generations produced ten unique events and ten ungrounded calls. Backend 293 tests; iOS 225 local passes; Android 195 units. See `Q1_VERIFICATION.md`. |
| E4 | Production rollout remains with the release track. | Development passed: owner-approved deployment and idempotent legacy revocation; backend 257, iOS 222 unit plus three UI, Android 194 unit plus five UI tests; both real signed-in native report/appeal flows and fixture cleanup passed. No mandatory human queue. |

R5, R6, H1, H2, and S1 have no separate unresolved implementation gate in their
latest records. They still participate in D4's production/physical regression
matrix. Historical Phase 4 tests that require the retired manual approval path
must be replaced by evidence-pipeline checks, not used to revive that workflow.

## Gates not yet executed

- D4 remains blocked by the release handoffs. It covers signed-out reading,
  auth, guest merge, cross-device sync, provider/AI reads, quotas/paywall,
  purchases, entitlements, push, privacy, and account deletion on production devices.
- E4 passed in development. Reports, appeals, rechecks, abuse, revocation, and
  retention run automatically. Operator handling is optional; production rollout
  stays with the release track.
- Q1's local gate, development rollout, live backend quotas and real Apple hardware
  proof pass. Its complete authenticated-device/Play gate remains open above.
  E2's deployed security and both authenticated native processing paths were
  refreshed successfully on October 12. Q2 is unopened.
- Q2, LA1 through LA4, and L1 remain future sessions, not passed feature gates.

## App-wide operation rule

The sole operator must not be required to approve routine content or clear a
review backlog. AI judgments plus deterministic safety/rights gates decide
routine outcomes. Unresolved suggestions stay private or expire automatically;
source-policy changes trigger automated reassessment. Optional operator controls
remain for exceptional correction, appeal, incident, or takedown handling.
Credential creation, store/legal declarations, and physical release verification
remain their existing action boundaries. They are separate from content review.
