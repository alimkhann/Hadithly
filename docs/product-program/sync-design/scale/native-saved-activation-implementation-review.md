# Selected A activation implementation read-only review

2026-10-21. Parent implements; reviewer inspected the current implementation, selected activation sketch and actual new native test bodies. No repo/code edits, cloud calls or delegates.

## Findings

No demonstrated pointer, epoch, retirement, replay or export correctness defect found in the current implementation. Two bounded proof gaps remain before calling the local activation gate fully exercised:

1. **Overlapping identical activation:** current idempotency test calls activation sequentially after the first success. Start two store instances on the same real disk prepared candidate, suspend both final fetches, release a valid terminal reply to one then the other, and assert equal active handles plus an unchanged export fence after the first commit. Code appears to handle this through exact prepared-checkpoint CAS followed by the already-active check; the concurrent lost-return branch is not directly exercised by the sequential test.
2. **Monotonic active revision:** code rejects a prepared candidate whose version is lower than the existing active version, but no direct regression case was found. Activate version10, prepare version9, return its otherwise exact valid completion, and assert rejection leaves both old active handle/contents and the prepared candidate unchanged. This proves the guard protects authority rather than merely matching a reply to its own candidate.

A fuller wrong-final-owner/root/input/completion/start/total/nonempty-facts matrix would strengthen boundary proof, but existing policy checks and revision-mismatch tests already support the implementation. These are local test suggestions, not demands for external accounts or a new architecture.

## Source conclusions

- Final activation captures Prepared before awaiting, verifies exact completion, rereads durable candidate lease/checkpoint and owner/erase fences, and changes active pointer/retirement/export clock in the same native database transaction.
- Active inspection reads the stored active generation after validating the current owner scope, rather than mistakenly requiring active lease to equal the newer candidate lease. Every active page read compares the whole current active handle, rejecting superseded handles.
- Candidate refresh preserves the stable scope epoch and creates a new generation. Replacements preserve prior active data, cannot retire the active/current generation, and refuse an occupied retirement slot. Failed final checks preserve Prepared; Restart/Unavailable preserve previous active.
- Retired cleanup validates the stored retiring record and its distinctness from active/current, deletes at most8 scoped rows per transaction, and clears retirement metadata only after all three child sections are empty. Clock increments fence exports across cleanup.
- Export marks the actual active identity, emits nested active/retiring metadata where separate, streams all retained child collections, and excludes opaque continuation/root tokens from new metadata.
- Android v4 adds nullable columns on v3 and creates the final schema for v1/v2. The actual SQLite abort test exercises pointer+checkpoint+clock rollback in one transaction. The Swift prior-Saved fixture test opens a real older disk schema containing1,005 retained facts, completes fold and activates after additive migration. Fixture provenance from the previously built d1c80bc binary is parent-supplied; reviewer inspected fixture-consuming test and terminal result, not the earlier capture process itself.

## Fresh terminal evidence inspected

- `/tmp/hadithly-saved-activation-ios-second.log`:112 tests, zero failures, `TEST SUCCEEDED`.
- `/tmp/hadithly-saved-activation-android-second.log`:94 tests finished, zero skipped/failed, `BUILD SUCCESSFUL`.

Tests reviewed cover incomplete/mismatched/network final checks; exact replay without clock mutation; three successful generations and old-active visibility; bounded cleanup/reopen; stopped candidates and occupied retirement; late completion after candidate replacement/session change/erase; additive prior-Saved migration; actual Android pointer transaction abort.

## Scope retained

This is a local activation/lifecycle component. Production subscriptions, private Saved read/barrier consumers, manifest settlement/ACK and pruning, public hydration/UI, joined-cache retirement, whole-partition/export throughput and scale, real hosted/installed-SDK/cross-device/physical-device evidence and recoverable iOS save-failure remain open. No end-to-end, deployment or release-readiness claim follows from these tests.
