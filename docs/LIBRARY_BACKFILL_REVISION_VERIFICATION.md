# Saved backfill revision repair

October 21, 2026, after `bd2e77e`. Grounding the paged-read boundary found that
`migrateH3SavedItems` changes canonical Saved facets and timestamps without advancing
the owner's Saved revision. A reader could receive changed private data under the
same version. This affects both native consumers of `librarySync:savedSnapshot`.

The internal migration now advances Saved once per changed owner in each page,
inside the same transaction as its canonical writes. Multiple changed rows for
one owner share that advance. Unchanged replay and unrelated owners retain their
versions. Existing source merge rules and pagination remain intact. No mobile API,
wire shape or native behavior changes in this prerequisite.

Three regressions, one each for bookmarks, favorites and notes, run the actual
Convex migration and owned snapshot queries. Each uses two affected owners, multiple
rows for one owner and a third untouched account. Before the fix all three fail
with version zero instead of one. After the fix they verify exact target coverage,
once-per-owner advancement and stable full snapshot replay. Existing dual-read,
rollback and folder migration fixtures remain green.

| Check | Result | Evidence |
| --- | --- | --- |
| Before repair | Three expected regression failures | `/tmp/hadithly-saved-backfill-red.log` |
| Focused migration suite | Six pass | `/tmp/hadithly-saved-backfill-green.log` |
| Complete backend suite | 487 tests, 41 files pass | `/tmp/hadithly-saved-backfill-backend.log` |
| Strict typecheck | Pass | `/tmp/hadithly-saved-backfill-typecheck.log` |
| Whitespace | Pass | `git diff --check` |

No migration or deployment was run against a cloud account. Canonical public hadith
changes remain outside the private Saved clock; the upcoming read contract must
state that distinction. Bounded Saved/folder/export reads, native assembly and
whole-file scale, legacy transaction/age, actual SDK/installed/device matrices,
iOS save failure and full A2 remain open. Prior native 89/72 results belong to
`bd2e77e`; no new native runtime pass is claimed for this backend-only repair.
