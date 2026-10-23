# Materialized Saved view policy review

2026-10-23. Read-only review of new LibrarySavedView.kt and the matching Swift policy/capture code, against the unchanged old LibraryProjection reducers and actual private Saved validation/folder normalization contracts. No code/docs edits, delegation, cloud or new architecture competition. Parent remains sole implementer. Durable row/index APIs and future production publication are outside this pure-policy review.

## Findings

### P2: folder normalization differs across platforms and from backend trim

Swift nameKey currently uses native String.lowercased(), while Android uses Java Locale.ROOT lowercasing. Those do not implement identical contextual casing. Actual local runtime probes produced:

| Input | Current Swift | Java Locale.ROOT | Backend Node normalization |
|---|---|---|---|
| ΟΣ | U+03BF U+03C3, οσ | U+03BF U+03C2, ος | U+03BF U+03C2, ος |
| ` Folder ` | surrounding spaces retained | surrounding spaces retained | `folder` |

The backend `convex/lib/savedFolderPolicy.ts` trims before NFC and lowercasing. Both new native nameKey functions omit trimming. A pending local folder can retain the command's original name while a server row has normalized display name, so native restore alias/name-index matching can fail to identify an already existing folder. Greek final sigma also makes the two platforms select different aliases or index buckets for the same accepted name.

Use an explicit common normalization contract and shared fixture vectors. Swift Foundation lowercased(with: Locale(identifier: "en_US_POSIX")) produces the contextual final sigma matching these Java/Node probes; verify other supported Unicode/whitespace vectors rather than assuming String.lowercased is equivalent. Match backend trimming deliberately, including the whitespace set, instead of silently using each platform's broadest whitespace trim. NFC before/after lowercase should be defined consistently with backend keys.

This is a new policy parity issue even though old Swift/Android reducers already had inconsistent name comparison. Freezing the old oracle is correct; normalization is a deliberate specified repair and needs its own expected fixtures rather than changing the old reducer to hide the difference.

### P2: folder alias tie ordering bypasses the shared UTF-8 rank

The new persisted folderRank uses `(createdAt, UTF8-ID)` and is cross-platform deterministic, but equal-name alias selection in captureLegacy uses Swift String `<` versus Java String comparison. For otherwise accepted non-ASCII IDs those orders can disagree: actual probes show Swift `U+E000 < U+10000` is true, Java UTF-16 comparison is false. The private validator permits nonempty bounded Unicode IDs; the policy itself does not constrain these folder identities to ASCII.

Select the matching folder by the same folderRank key used by the directory/name index, or explicitly enforce and prove an ASCII identity contract at the relevant boundary. Reusing folderRank avoids inventing a second comparator and makes capture match the eventual durable name-index selection. This also covers future Unicode legacy/fixture identities without relying on current generated UUID/Convex IDs happening to be ASCII.

## Reducer parity checks

Apart from the explicit normalization/alias ordering issues above, the point fold matches the old reducer's private facet/membership semantics on inspection:

- bookmark/favorite add preserve earliest facet dates and floor aggregate updatedAt at operation time;
- note put retains first noteCreatedAt and replaces content/noteUpdatedAt using command times;
- absent-target removals do not create a private row;
- last-facet removal clears deletion provenance but keeps the intermediate value for subsequent chronological operations;
- explicit membership put, including none, clears removedBy; unconfirmed claim_if_unset remains ignored like the old reducer;
- facet restore preserves old bookmark/favorite timestamps and note restore behavior;
- folder delete clears membership, records the exact operation ID and floors updatedAt; compact Undo restores only the exact deletion tag while still saved/unassigned;
- explicit restored-member lists retain their existing behavior, without guessing membership from the current visible page;
- confirmed → selected projected frozen → pending order is preserved, and positions are excluded from Saved item materialization.

The new folderUpdatedAt metadata is additional to the old UI entry, not a contradictory facet mutation. It should be compared separately from the old oracle's missing field. Route is captured only from a reference whose exact target ID matches; an unresolved target remains private rather than borrowing a neighboring public route. Do not claim full public hydration from this route hint.

captureLegacy intentionally materializes the whole old base and queue once. That is an explicit migration/compiler cost, not the bounded steady-state query API or evidence that production Saved is already scalable. It validates old private rows, rejects duplicate identities instead of silently collapsing them, keeps zero-facet values during chronology, then filters them only at final output. Old deterministic tie/normalization expectations must be specified separately because the frozen old reducers only sort by timestamp and select the first matching dictionary folder.

## Index/rank inspection

The index-key construction emits at most4 facets ×2 folder scopes ×2 route/global scopes =16 keys per visible item. Unresolved gets its own route bucket; a known route gets one exact collection bucket plus global. It does not need a scan-and-postfilter to discover a selected facet/folder/known collection. The future query must still report unresolved coverage independently of known matching row exhaustion.

Positive finite IEEE754 bit order is monotonic; complementing fixed-width unsigned hex gives descending order. Both implementations canonicalize negative zero to positive zero, reject negative/nonfinite values, and append hex UTF-8 identity bytes for deterministic ties. IDs are bounded by the existing private item validator, so the technical key remains bounded. Exact time/rank parity still deserves fixtures around0, fractional timestamps, equal times, large finite values and non-ASCII IDs. Source inspection alone is not query-plan or disk proof.

LibrarySavedViewItem stores private facts, collection classification and deletion provenance only. It does not reintroduce public full-text cache rows. Identity/prefix hashing uses framed existing semantic hashing and fixed suffix delimiters; index rows must still validate exact owner/view/selection/rank when read at the durable boundary.

## Required chronological invariant for the later point-write integration

Do not lose zero-facet intermediate history between unacknowledged edits. The pure capture is correct because it retains those values until the full chronology ends. If a future point write physically drops a zero-facet effective row, a later add cannot safely use only `current=nil`: the old full reducer may still preserve its earlier createdAt/folder state from base/earlier pending operations. Recompute that target from immutable base plus its exact relevant queue chronology, or retain an appropriate hidden intermediate until its source history is no longer relevant. Do not turn this constraint into a hidden full-library replay. This is a future integration invariant, not an additional defect in the current pure capture.

## Focused next proof

Keep old LibraryProjection unchanged as the independent oracle for defined facet/date/membership outcomes. Add shared expected vectors for folder normalization/alias selection and the new deterministic UTF-8 tie contract. Exercise delete → move/explicit-none → compact Undo; remove-last-facet → recreate → Undo; same target duplicate legacy facets; equal note times; absent public route; and timestamp ties beyond the first page. Compare exact fields and target identity rather than only item counts. Then verify durable row/index write/seek budgets separately against real stores.

This review approves no runtime pointer or row-mode flip. Bounded durable index/component evidence, bulk staging/catch-up/publication, complete query/UI hydration and all broader A2 gates remain open.
