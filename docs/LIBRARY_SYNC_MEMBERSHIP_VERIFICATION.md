# A2 membership clocks and guest claims

October 19, 2026. Continues `b198c18`. This is a local implementation checkpoint
on both apps and actual Convex functions. No deployment or private account call
was performed. Large-folder support and A2 remain open.

## Reproduced failures

Three actual backend cases failed before the shared writer correction:

- An equal-time, same-value removal replaced a folder deletion's causal mark,
  breaking its Undo.
- An older guest placement replaced a newer cloud folder choice.
- A guest import of the same folder rewound its clock, permitting an older delete.

Evidence: `/tmp/hadithly-membership-clock-red.log`. The independent review then
found that a later note edit could make an old folder choice appear new because
the planners used aggregate item time. That finding changed the implementation.

## Behavior

Ordinary sync, legacy assignment and V2 guest placement share one membership
writer. Same-value older/equal observations preserve the causal mark; different
equal-time choices retain cloud. Actual newer choices still apply. Legacy assignment
increments the Saved revision only after an accepted write. Physical bulk folder
delete/restore still use their current paths; no logical job is enabled here.

Both native planners and the V2 validator carry optional `folderUpdatedAt`
separately from note and item metadata. An import lacking that clock may seed an
unset membership, but cannot replace a cloud folder choice or explicit removal.
It stamps no fabricated clock. The durable command's placeholder time grants no
ordering authority. Rejected originals remain in recovery, and pending unknown-time
claims do not optimistically replace the subscribed cloud membership.

Both coordinators validate the stored source and wire frame together. A known old
frame whose timestamp-less source was given a guessed time uses the existing
fenced retirement path with its source retained as historical recovery. A mismatch
between source operations and wire operations stops without erasing either value.
Android also rechecks the captured session after suspending local reads.

Guest-merge clock validation runs before effects, including when a folder reference
cannot resolve. Ordinary sync already validates operation clocks at admission and
legacy assignment uses server time. The internal writer trusts these boundaries.
An additional red test caught aggregate `updatedAt` being rewound by a later facet
patch after a newer membership write. The final merge includes the accepted
independent clock and passes that case. Evidence:
`/tmp/hadithly-membership-metadata-red.log`. This was caught before commit.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| Actual membership sync/legacy/guest functions | 38 pass | `/tmp/hadithly-membership-clock-final-focused.log` |
| Complete backend suite | 413 tests, 36 files pass | `/tmp/hadithly-membership-final-backend.log` |
| Strict backend typecheck | Pass | `/tmp/hadithly-membership-final-typecheck.log` |
| iOS real stores/core/facade and Settings policies | 51 pass | `/tmp/hadithly-membership-guarded-ios.log`, `.xcresult` |
| Android real stores/core/facade and wire adapter | 30 pass | `/tmp/hadithly-membership-guarded-android.log` |
| Native wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |

Fixtures cover newer moves, older and tied observations, stale Undo, invalid clocks
with rollback, independent note/folder times, timestamp-less installed-style data,
projection, recovery serialization and mismatched frozen-frame retention. Native
tests use current SwiftData/JSON schemas and controlled RPCs, not previous installed
schema migration, actual SDK transport or cross-device delivery.

## Review and remaining gates

The initial and final independent read-only reports are in
`product-program/sync-design/scale/membership-review-initial.md` and
`membership-review-final.md`. The final report preceded test completion and the
last aggregate metadata/boundary corrections. Its Swift projection citation is
incorrect: that branch is in `Core/Saved/UserLibraryModel.swift`, not
`GuestMergePlanner.swift`. The raw review is preserved. The noted unresolved-folder
clock inconsistency is fixed by the final upfront boundary check.

Unknown-time intent cannot prove it is newer than a cloud choice. We retain it for
recovery rather than inventing a date. Unknown variants, malformed installed data,
whole-file native storage costs, bounded folder jobs, read/export pagination,
marker retention, account-erasure scale, SDK deletion, broad final review and real
approved account/device delivery remain open. The 501-member support probe remains
red. These checks close no production, release, localization or content gate.
