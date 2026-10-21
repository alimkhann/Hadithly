# Selected A activation component accepted review

2026-10-21. Final read-only recheck after `activation-implementation-review.md`. No repository/code edits, external/cloud/account calls or delegation.

The two identified local proof gaps are resolved on both platforms. Actual disk tests now suspend two cloned activations before final responses, commit the first response, then deliver the second; they assert identical handles, unchanged post-first-commit export fence and durable reopened pointer. Separate tests activate version10, prepare version9, return its otherwise exact terminal confirmation, and assert rejection preserves active handle, Prepared candidate and export fence. These exercise the intended concurrent lost-return and monotonic authority branches rather than only sequential replay or a mismatched reply.

The Android facade additionally rechecks captured session immediately before the final network fetch. Existing inside-IO, post-await and post-return checks and durable transaction fences remain unchanged.

Fresh authoritative logs inspected directly:

- `/tmp/hadithly-saved-activation-ios-final.log`:114 tests, zero failures, `TEST SUCCEEDED`.
- `/tmp/hadithly-saved-activation-android-final.log`:96 tests finished, zero skipped/failed, `BUILD SUCCESSFUL`.

I inspected fixture README, consuming migration test and repeatable capture/verify script, then executed its verify mode locally. It verified the prior schema has no active/retiring columns, the recorded terminal-fold checkpoint and1,005 synthetic facts, and no `/Users/` bytes; decompressed SHA256 is `89c6329480fd7c93ec757057ace3e168bd8b61410b007a6f2d7faedd4e5a400a`, matching the provenance README. Capture origin from the previous d1c80bc binary remains documented by the parent; reviewer independently verified the resulting artifact and current migration test evidence, not the earlier capture event.

No remaining concrete pointer, epoch, retiring-generation, replay or export defect found in the reviewed local activation/lifecycle component. Accept this component within its stated scope.

Production subscriptions, private Saved read/version/barrier consumers, manifest settlement/ACK/pruning integration, public hydration/UI, joined-cache retirement, full-partition/export throughput and scale, real hosted/installed-SDK/cross-device/physical-device proof and recoverable iOS save-failure evidence remain open. The result neither deploys the change nor establishes end-to-end sync, release readiness or product-program completion.
