# E3 adversarial review

Updated 2026-10-11. Reviewers: GPT-5.6 Sol max and GPT-6.1 Sol high.
They reviewed code independently without modifying the shared checkout,
reading credentials, or making provider/cloud requests.

## Intent

Publish only clean, licensed, provable, consistent contributions after two
independent isolated reviews whose raw confidence values both exceed 0.95.
Evidence remains untrusted data; citations remain attached. Routine decisions
are automated and the operator is an optional exception path. Stop before E4.

## Accepted findings and repairs

| Finding | Review signal | Repair and proof |
| --- | --- | --- |
| Offline export could include unbound legacy/AI text and drop required attribution. | GPT-5.6 Sol; critical. | Version 1 translation packs are blocked for all stored translations; existing pack manifests are suppressed and base compatibility hints are cleared. The format cannot retain per-entry rights/attribution. Base dumps remain unchanged. Existing pack generation fixtures now assert denial; a versioned translation pack format is an explicit O2 follow-up. |
| Exact file permissions could leave a suggestion held. | GPT-5.6 Sol; warning. | File grants schedule the same idempotent reassessment as source-policy updates. A regression proves private hold to ready without direct state manipulation. The native fixture controller now records only the self-authored grant and lets production code requeue. |
| Sunnah.com provider dependencies and aliases were incomplete. | Both reviewers; warning. | Provider origin dependencies and canonical Arabic matching are retained. Both legacy underscore and actual hyphenated collection slugs map to scoped Sunnah.com paths. Seven alias fixtures cover the path. |
| Community citations were unreachable, and English ignored stored defaults. | GPT-5.6 Sol; warning. | Both readers resolve stored English defaults publicly without generation and prefer them to provider English. Community source controls open the production citations sheet. Native fixtures exercise text and source controls; stored public data excludes review confidence. |
| Earlier review found source URL query leaks, stale rights reuse, default ancestry loss, and access-policy normalization bypasses. | Earlier independent passes. | Public-safe URL boundary rejects queries/credentials; current rights are reread; deletion rewires descendants; worker origins normalize before deny and scoped access checks. Regression fixtures cover each repair. |

The reviewers agreed that the central publication mutation rebuilds its snapshot
and fails closed on changed rights, evidence, defaults, abuse, or deletion.
The initial no-findings review missed offline/native paths caught by the other
model; the lead accepted concrete findings rather than averaging verdicts.

## Scope decisions

E4 owns published-content revocation, reports/appeals, and retention refinements.
E3 already blocks future comparison reuse when rights change. It does not turn
an ambiguous source or a conditional license into affirmative permission.
Translation pack export remains unavailable until the pack format and both
native decoders retain translation-specific rights and attribution.

## Final verification

The final runtime and test record is `E3_VERIFICATION.md`. No review pass grants
permission to bypass a deterministic safety, provenance, or license check.


Both final re-reviews reported no critical, warning, or nit findings. Android
source targets enforce 48 dp with a bounds assertion. Final backend validation
passed 232 tests; the native and runtime evidence is in `E3_VERIFICATION.md`.
