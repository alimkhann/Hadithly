# Native Saved read boundary accepted review

2026-10-22. Final read-only source/test/log recheck. No repository/code edits, delegates, cloud or account calls.

## Accepted local scope

The previously identified native boundary findings are resolved. Swift savedInvalidations builds its transport/timer inside Deferred, performs fresh captured-context/capability validation at subscription and per delivery, computes remaining absolute lifetime at subscription, and schedules that work on main. Prefix-until-expiry plus appended SessionChanged handles both quiet expiry and source EOF. Android evaluates lifetime/context at collection and explicitly fails on normal source completion, preserving outer cancellation with ensureActive after timeout handling.

The prior iOS first-head fixture failure is resolved by the correct synchronization boundary: the fake now exposes a one-shot handleEvents.receiveRequest signal, and the test awaits that explicit XCTest expectation before sending its PassthroughSubject head. This replaces bounded Task.yield/factory counting. Production source is unchanged after Deferred. The fresh suite proves first invalidation delivery, closed-source failure, delayed absolute expiry/stale no-transport and late hydration rejection together.

Captured read contexts bind write session/generation/owner, exact capability and absolute deadline. Separate domain states keep head invalidation, route metadata, complete passages and missing/unavailable outcomes distinct. Full text remains exact; no native truncation or public-hydration private-version authority is introduced. Generated wire/parity derives the actual backend validators/replies. The server boundary review remains in `read-boundary-review.md`.

## Authoritative terminal evidence inspected

- `/tmp/hadithly-saved-reads-ios-accepted2.log`:120 tests, zero failures, TEST SUCCEEDED. All four affected first-head/EOF/delayed-subscription/late-hydration tests pass explicitly in this run.
- `/tmp/hadithly-saved-reads-android-accepted.log`:102 tests finished, zero skipped/failed, BUILD SUCCESSFUL.
- `/tmp/hadithly-saved-reads-backend-first.log`:43 test files/524 tests pass.
- `/tmp/hadithly-saved-reads-typecheck-final.log`:strict tsc --noEmit completes without diagnostics.

Historical evidence retained honestly: initial native suites118/100 passed before EOF tests; actual focused EOF regressions failed on both platforms; delayed Swift regression failed for eager transport/extended deadline/stale admission; first accepted-suite attempt ran120 with1 fixture-delivery failure. The current120-zero-failure run supersedes that attempt after test-only readiness repair. These were diagnosed and corrected rather than counted as passes.

No remaining concrete native/server read-boundary ownership, expiry, EOF, text-integrity or private-barrier-authority defect found within the reviewed local scope. Accept this bounded server+native read boundary component.

## Gates retained

Production Saved observer/read/barrier consumers are not cut over by this acceptance. Reader exact-target state, bounded facet/folder/sorted UI paging, missing-summary UI, private/public hydration lifecycle, legacy partition transfer/full-cache retirement, full export/throughput scale, deployment/hosted and installed-SDK/cross-device/physical-device proof, and recoverable iOS save-failure remain open. This is not end-to-end sync, release or full-program completion evidence.
