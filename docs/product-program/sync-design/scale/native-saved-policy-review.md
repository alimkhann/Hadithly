# Native Saved wire/policy substep review

Read-only review of the selected contract, appended iOS `LibrarySemanticFingerprint`/`LibrarySavedPolicy`, Android `LibrarySavedPolicy.kt`/`LibrarySyncCodec.kt`, backend semantic digest extraction and parity fixture producer, wire generator/actual validators, generated Saved DTOs and six new policy tests on each native platform. No repository edit, cloud/account call, extra agent or independent test rerun performed.

## Disposition

**No concrete blocking correctness or compatibility finding in this substep.** Accept this as generated wire plus pure boundary/fingerprint/reducer evidence. It does not implement a raw row journal, durable collection/fold, migration, preparation, activation, erasure, export or production barrier/caller cutover.

## Correctness inspected

- The existing sync intent digest is extracted without changing its domain prefix (`library-intent-v1:`), canonical object-key ordering, UTF-8 string framing, finite IEEE-754 number representation, negative-zero normalization or SHA-256 algorithm. Existing intent callers continue invoking the same encoding through the generic helper.
- Saved facts use a distinct versioned digest domain. Backend-generated facts and expected private values come from the actual `savedFactsPage`/old reader fixture; their backend-generated fact digests are consumed and checked on both native platforms. This is stronger than duplicating the expected hash in a native helper test.
- Generated SavedPrivateItem/SavedFact/SavedFactsReply types derive the actual validators through the existing generator roots. Required/optional fields, discriminators and unavailable reasons are represented. Folder causal clock remains in the private item domain rather than disappearing with the old joined DTO shape.
- Both inspect implementations enforce owner, root, private version, exact requested input, start/ordinal progression, nondecreasing fact phase, finite safe integral counts, nonempty bounded tokens/IDs, current fact-count cap and UTF-8 serialized size caps. Empty advancing pages are accepted without fabricating ordinal progress. Immediate nonprogressing next tokens are rejected.
- A terminal reply requires exact total equal to start plus facts count. Further collection from a complete position is refused. Final confirmation requires an empty complete reply with the same owner/root/private version, exact completion input/output token and durable total/start.
- Canonical replacement completely clears absent fields while retaining first encounter ordinal. Bookmark/favorite folds take earliest facet time and aggregate created minimum without raising an existing updatedAt. Legacy-only initialization preserves its first source clock. Note replacement uses strict greater-than, keeps canonical/equal-legacy tie precedence, lowers aggregate createdAt and raises updatedAt. Effective folder membership/clock is preserved from server facts.
- Private missing-target references and whitespace/Arabic note content survive the pure fold; no canonical public lookup or missing-target filter is introduced. No store write, snapshot pruning or observation-barrier update is called by this policy.

## Evidence inspected

- `/tmp/hadithly-saved-policy-backend.log`: 511 tests, 42 files passed.
- `/tmp/hadithly-saved-policy-ios-first.log`: 95 tests, zero failures, `TEST SUCCEEDED`; result bundle `/tmp/hadithly-saved-policy-first.xcresult`.
- `/tmp/hadithly-saved-policy-android-first.log`: 78 connected tests finished and `BUILD SUCCESSFUL`.
- Typecheck log contains `tsc --noEmit` without diagnostics; parent explicitly supplied its successful terminal status. This reviewer did not consume the parent's live process handle.

The six added cases on each native platform cover actual-backend value/digest parity, canonical field clearing, legacy-only timestamp asymmetry and ties, checkpoint codec roundtrip/final recheck, malformed metadata matrix, phase/numeric/UTF-8 caps and retained private references. The checkpoint roundtrip is a codec test, not an on-disk reopen test. The fact parity fixture covers one combined backend merge case; additional real-store fixtures remain necessary for large mixed-target order and lifecycle behavior.

## Deliberate limits for the next unit

The pure policy rejects only immediate token repetition. Historical token cycles, duplicate source IDs at a different ordinal, exact historical page replay, same-input changed response and durable generation/session ownership need the selected raw journal and page receipts. The current position alone cannot prove them. Likewise `confirm` validates a completion response against a position but cannot prove the position came from verified persisted rows; the future opaque prepared handle/row transaction owns that authority.

Store integration must preserve current production barrier authority, capture/recheck session and durable owner incarnation around awaits, atomically save raw facts and continuation, enforce bounded row/byte work, and include every retained payload in bounded cleanup/erasure/export fencing. Actual installed-schema disk migration, reopened collection/fold/verification, recoverable store failure, atomic activation and all four Saved observation consumers remain unimplemented requirements. No production readiness or full store-component completion follows from these green policy checks.
