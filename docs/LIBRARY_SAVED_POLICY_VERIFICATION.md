# A2 native Saved wire and policy verification

October 21, 2026, after `2a287fd`. A2 remains active. This implements the first
wire/reducer/boundary substep of native private Saved assembly. Durable row storage,
fold execution, installed-schema migration, erasure/export and activation remain
unimplemented. Production still consumes the old complete joined snapshot.

## Implemented

Actual SavedPrivateItem, SavedFact and SavedFactsReply validators now feed both
native wire value sets through the existing generator. Row/byte/cursor limits also
derive from backend constants. The backend row limit now has a named constant;
its value and behavior remain one row per page.

The native policy checks owner, root, private version, exact input, ordinal and
source phase continuity, safe integers, bounded identifiers/tokens, UTF-8 payload
limits and exact terminal totals. Empty advancing pages preserve transport progress
without adding a fact. Immediate repeated next tokens fail. Terminal collection
cannot continue as an ordinary page. A final check accepts only an empty completion
with the same owner/root/version/token/total. It does not grant storage or activation
authority; a future opaque prepared handle must prove durable verification.

The deterministic single-row reducer preserves canonical-last values and clears
absent replacement fields while retaining first encounter order. Legacy facets
keep earliest timestamps without raising an already-existing aggregate updatedAt.
Notes use strict timestamp precedence with the existing minimum-created/maximum-
updated rules. Empty folders, effective folder clocks and private references lacking
public text retain their own values. It performs no whole-library merge or lookup.

Saved semantic fingerprints reuse the existing UTF-8 framing, IEEE-754 numeric
encoding, negative-zero normalization, sorted wire keys and SHA-256 implementation
under a separate versioned domain. Existing sync intent callers retain their exact
prefix and values; syncBatchDigest is unchanged.

The generator now executes the actual bounded backend parity fixture. It emits the
received fact JSON, the existing reader's expected private row and backend-computed
fact digests into both native value files. Both native tests decode those real
fixtures and compare row values and every digest. Expected values are not copied
from either native reducer.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Complete backend suite | 511 tests, 42 files pass | `/tmp/hadithly-saved-policy-backend.log` |
| Backend strict typecheck | Pass | `/tmp/hadithly-saved-policy-typecheck.log` |
| iOS selected planner/presentation/Settings suites | 95 pass, zero failures | `/tmp/hadithly-saved-policy-ios-first.log`, `/tmp/hadithly-saved-policy-first.xcresult` |
| Android selected connected planner/facade suite | 78 pass | `/tmp/hadithly-saved-policy-android-first.log` |
| Reproducible native wire/parity generation | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| Local API source and whitespace checks | Pass | local API `--check`, `git diff --check` |

Six added cases per platform cover real backend row/digest parity, canonical field
clearing, legacy-only timestamp asymmetry/ties, checkpoint codec roundtrip and final
recheck, malformed metadata, phase/numeric/UTF-8 bounds and retained Arabic/whitespace
content. The checkpoint roundtrip is a codec check, not a persistent-store reopen.
Existing intent and sync tests pass with the extracted shared hash implementation.
Independent review found no blocking defect in this exact substep; see
`product-program/sync-design/scale/native-saved-policy-review.md`.

## Remaining contract

The selected A21/25 design retains raw facts and exact page identities, followed by
bounded fold and persisted verification. B's tighter total row budget is retained.
No raw journal, durable replay/source-identity uniqueness, historical token-cycle
check, generation/session fence or opaque prepared handle is implemented here.
The pure position alone cannot prove those properties. Every retained future payload
needs bounded cleanup, erasure and streamed export/fences before production wiring.

Next implement that store component on both native persistence systems with actual
old-schema disk files, interrupted/reopened collection, controlled transaction
failure and account/erasure races. Then prove final server recheck, atomic activation,
all four private observation consumers, bounded UI/public hydration and old cache
migration together. Whole-partition pending/cache/export scale, practical throughput,
iOS save failure, hosted SDK/auth, installed-client/cross-device and physical-device
gates remain open. No cloud deployment, paid call or push occurred.
