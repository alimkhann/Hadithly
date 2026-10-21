# Native Saved durable-store read-only review

2026-10-21. Scope: current uncommitted Swift Saved models/store/policy/export and Android SQLite v3 journal, GuestStore facade, Saved policy and export. Parent remains sole implementation owner. No repo modifications, cloud calls, private-account calls or delegates.

## Concrete finding

### P2: Android projection paging scans unrelated retained collections

`android/app/src/main/kotlin/com/hadithly/app/core/data/LibraryOutcomeJournal.kt:601-605` queries `saved_projection WHERE collection_key=? AND row_key>? ORDER BY row_key LIMIT 8`, with `after ?: ""` on the first page. The schema at lines159-164 has only the global row-key primary index and subject/namespace/owner index, not a collection/key index. SQLite uses the global row-key index and filters collection after visiting rows. This also affects the final verifying step with fewer than8 remaining rows, which can scan the rest of all retained collections. Thus LIMIT8 bounds returned records but does not bound unrelated disk scanning; other retained owners/generations increase work for this owner's tiny projection.

Executable local reproduction used an isolated in-memory SQLite schema matching the production table/index. EXPLAIN yielded `SEARCH saved_projection USING INDEX sqlite_autoindex_saved_projection_1 (row_key>?)`. With10,000 foreign-collection rows before one target row, the1-row query executed40,030 SQLite VM steps. No private data used.

Fix either with an additive index `(collection_key,row_key)` or a closed collection prefix range over row_key (Swift already uses `collection + ":r:"` through `collection + ":r:~"`). Preserve per-row collection/owner checks. Verify first, continuation and final windows stay on that scoped range, including many foreign-owner rows and an empty target collection.

## Retracted observation / accurate work bound

My first message incorrectly multiplied8 page receipts by8 facts. Actual generated `LibrarySyncLimits.savedFactRows` is1 and receipt guards enforce it before loading facts. CheckingPages therefore reads at most8 page receipts plus8 raw facts, with fixed header/clock/identity overhead. There is no current64-fact expansion. Folding reads8 facts and up to8 previous projection rows, then updates up to8 rows plus metadata. The selected contract's wording “sixteen-data-row transaction budget, counting all metadata and identity checks” is tighter than those total reads+writes; document the real fixed operation budget or adjust chunking before claiming that exact16-total-operation bound. This is a documentation/selected-budget alignment point, not a hidden whole-library materialization.

## Reviewed without another concrete defect found

- Append/replay checks persist exact continuation/page identity and raw fact atomically; changed retries, duplicate source identities, phase regression, ordinal gaps and token cycles reject.
- Terminal raw digest, page-chain reconstruction and projection row counts have explicit resumable stages; prepared rows do not grant production Saved version/receipt barriers.
- Subject/namespace/owner and durable epoch/generation are checked against retained headers around collection. Android account deletion invalidates the coordinator before suspending, durably persists intent then installs SQL erasure fence; Swift persists intent and shared mutation clock in one context save.
- Saved append, fold/check/verify, creation and erase steps bump the shared export mutation clock; raw, page, projection and assembly export sections cover retained rows with continuation tokens represented only by fingerprints.
- Android v1->v3 creates export metadata plus Saved tables; v2->v3 creates only additive Saved tables. No existing outcome tables are dropped. Actual old disk migration and reopen results still require the parent's terminal test evidence.
- No production page wiring, pointer activation, joined Saved barrier migration, native whole-file cache-scale or real hosted/device proof was inferred from this component.

This review did not run the full native build/test matrix (parent owns those runs). The only executed probe was the isolated SQLite query-plan/VM-step check above. Source was changing during review; parent should confirm the finding against the final diff and then obtain a bounded recheck after fixing.
