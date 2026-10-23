# A2 indexed Saved draft rows and compiler

October 24, 2026, after `fcb16fd`. Both native stores now retain derived private item/folder drafts and materialized selection indexes. This implements the storage/query/compiler component of the selected Saved cutover. It does not certify a complete view, publish an active presentation pointer, connect production UI, or enable row mode. All production Saved/Reader surfaces still use the existing display path.

## Implemented component

Derived items contain immutable private Saved fields, optional exact-target route classification and folder-removal provenance. They contain no Arabic/English provider passages. Items have at most sixteen fixed selection keys covering applicable facets, global/exact/unfiled folder selection, and global/known/unresolved route scopes. Folder directory and normalized-name indexes are separate fixed key ranges. Rank encodes positive finite Double bits plus UTF-8 target identity, preserving fractional timestamps and deterministic ties across platforms.

Draft pages seek one technical key range, read at most thirty-three index entries for a maximum thirty-two visible rows, then validate exact private rows. Selected reader collections report unresolved coverage through a separate one-entry seek; unknown routes are not silently assigned to a collection or called a complete empty library. Folder menus page beyond the first thirty-two rows and exact item/folder reads do not search a visible window. There is no base-overlay anti-join, tombstone scan or filter-after-limit query.

A batch writes at most eight private item/folder values. Each can maintain up to sixteen small technical indexes; replacement may remove sixteen old keys and insert sixteen new keys. Private-row and technical-mutation counts are stated separately. Rows, indexes, draft serial and shared export clock commit together. Scope admission and existing private epoch are rechecked on every operation. A draft ticket binds owner, generation, serial and selection; changed serial/selection rejects instead of silently continuing. iOS owner admission uses exact metadata count queries instead of decoding the account payload.

Allocation chooses a fresh generation UUID inside the store. Resume only reads an existing head and cannot recreate it. Bounded collision/orphan probes preserve headless retained evidence. At most three draft heads are admitted per owner scope. Terminal serial metadata remains readable; further writes reject before mutation. Android requires actual SQLite integer storage and full-width range checks for serial/kind, including export, rather than coercing malformed scalars.

The pure legacy compiler preserves the old reducer's independent facets, chronological point edits, delete time floors, exact removal tags and compact Undo eligibility. It keeps zero-facet intermediate values only while replaying a captured chronology and drops them from final output. The durable writer removes zero-facet rows and indexes; future queue integration must rebase/recompute the target chronology rather than treating a missing visible row as lost original history. Folder name aliases use shared normalized keys and the same UTF-8 folder rank.

## Migration, retained copies and erasure

Android schema 7 adds heads/private rows/indexes alongside the existing tables for installed versions 1–6. The immediate-v6 real disk fixture retains private/local state and creates the new tables on reopen. Existing v1/v2/v3/v4/v5 fixtures are reconstructed without newer view tables before upgrade and still pass. SwiftData adds three entities; the genuine captured older Saved store still reopens, preserves its 1,005 facts and activates through the new schema. This is local migration evidence, not all installed binary/backup/OS proof.

Existing private export streams now include bounded draft-head and private-row sections. They preserve private notes, route classifications and provenance from headless/partitionless historical copies in the captured subject/deployment. They exclude foreign scopes and provider passages. Derived technical indexes add no original private content beyond those records. Erasure covers all three new tables, deleting at most 128 small index rows or eight private rows/heads per step, while retaining its deletion fence. Guest originals and other scopes survive.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Full selected iOS planner/presentation/Settings suite | 134 pass, zero failures | `/tmp/hadithly-saved-view-ios-full.log`, matching `.xcresult` |
| Full Android connected planner/facade suite | 123 pass, zero skipped/failed | `/tmp/hadithly-saved-view-android-full.log`, actual connected JUnit XML |
| Android local unit suite | 212 pass, zero skipped/failed | Same full command, unit JUnit XML |
| Latest iOS metadata admission/lifecycle cases | 2 pass, zero failures | `/tmp/hadithly-saved-view-ios-admission-final.log`, matching `.xcresult` |
| Final iOS model-layout/migration/lifecycle follow-up | 3 pass, zero failures | `/tmp/hadithly-saved-view-ios-model-layout-final.log`, matching `.xcresult` |
| Generated native wire contract | Pass; native entities remain outside the generated region | `/tmp/hadithly-saved-view-wire-check-final.log` |
| Actual backend naming and portable-key fixtures | Pass | `python3 scripts/generate-saved-view-vectors.py --check` |
| Genuine prior SwiftData fixture | Pass, 1,005 facts | Existing capture helper `--verify` |
| Independent source recheck | No remaining concrete finding in this draft component | [Recheck](product-program/sync-design/scale/saved-cutover/view-store-recheck.md) |

The 2,001-item fixture compares private compiler output to the unchanged old reducer oracle, including offscreen membership movement, compact folder restore, final-facet removal/Undo, time floors, sparse facets and equal sort times. Real stores retain and page the same dataset after reopen, verify all facet selections and selected folder/collection scopes, read/update target 1999 without loading a visible window, reject an old ticket, page seventy-two folders and resolve equal-time Unicode folder-name aliases. Actual portable exports contain every private view item and the accepted offscreen note; scoped erasure removes all matching draft rows/indexes.

Android inspects the actual key-range query plan and requires an indexed SEARCH rather than SCAN. iOS executes the empty inner index seek against the populated store and requires fewer than one hundred SQLite VM steps. This is evidence about that seek, not a claim that all context admission, decoding or an entire refresh consumes fewer than one hundred steps. Broader practical throughput remains open.

Lifecycle cases delete empty heads and head-only metadata, reject resume, allocate a different identity and retain orphan notes for scoped export. Another same-subject owner's removed account does not authorize reads but its draft note is exported; a foreign subject's note is excluded and survives current-scope deletion. Serial exhaustion preserves data/fences. Android injects an actual serial-update SQLite abort after child mutations and proves complete rollback/retry. SwiftData tests a logical clock-exhaustion throw before save and context rollback; actual recoverable save failure remains open.

## Findings corrected and remaining work

Review found two native normalization/tie differences and three lifecycle/parser issues. Backend-derived fixtures now cover ECMAScript trimming, NFC and contextual Greek case conversion; alias ties use the shared rank. Allocation/resume are separate, terminal serial read/write bounds agree and Android scalar parsing is strict. The [initial policy](product-program/sync-design/scale/saved-cutover/view-policy-review.md) and [store review](product-program/sync-design/scale/saved-cutover/view-store-review.md) retain those findings. Foundation Date oracle comparisons use the same Date conversion boundary without rounding the new private Double fields or weakening rank fixtures.

The remaining controller must verify complete draft coverage, resume/catch up bulk work, retire old heads in bounded steps and atomically publish private generation, presentation, mode and queue effects. Accepted point edits must update the published view in their queue transaction. Both native Saved/Reader UIs then need the exact/window APIs and independent reference/full-text hydration, with safe old-array/cache retirement. Draft queries alone prove none of that completion.

Pending/positions/account blob scale, server export consistency/throughput, installed/backend-first rollout, real SDK/JWT, cross-device, physical-device, recoverable iOS save failure, A2 deployment and A1 dependencies remain open. Full PRODUCT_PROGRAM stays active. No deployment, paid call, production change or push occurred. Incoming Xcode/catalog changes remain separate.
