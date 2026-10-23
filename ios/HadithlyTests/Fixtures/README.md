# Prior Saved schema fixture

`SavedSchemaV3.store.gz` contains synthetic test data only. It came from the
already-compiled `d1c80bc` iOS simulator test binary on October 21, before adding
`activeData` and `retiringData` to `GuestSavedAssembly`. SQLite's backup API captured
the existing large-journal test at its terminal folding boundary. It contains
1,005 source facts, their exact page receipts, and the existing owner partition and
mutation clock. It has no active/retiring or rowMode columns and no `/Users/` path bytes.
V3 is the Saved component fixture label, not a registered SwiftData VersionedSchema.

The backup's journal mode was changed to DELETE before deterministic gzip
compression, so fixture inspection does not need missing WAL side files. Private
values and schema were otherwise preserved. This is a test database, not an app
build artifact or a copy of a real account.

Database SHA256: `89c6329480fd7c93ec757057ace3e168bd8b61410b007a6f2d7faedd4e5a400a`.
Compressed SHA256: `d450bffb69d52a004e439e850a215b47e71d9733047034dae62d5f40866169bd`.

Verify the fixture from the repository root:

```sh
python3 scripts/capture-saved-schema-fixture.py --verify \
  --output ios/HadithlyTests/Fixtures/SavedSchemaV3.store.gz
```

To recreate it, build `d1c80bc` in a separate checkout and simulator build directory.
Start the capture helper with `--containers` pointing to that simulator's
`data/Containers/Data/Application` directory and `--output` pointing to a temporary
gzip path. Concurrently run the already-built
`GuestMergePlannerTests/testSavedLargeJournalHasBoundedPagesPreservesDuplicatesAndNeverAdvancesJoinedBase`
using `xcodebuild test-without-building`. Container IDs can change when tests
reinstall the app; the helper watches the simulator's application directory.
Random owner-scope epochs change recreated file hashes. Compare the actual schema,
retained values and migration behavior rather than expecting identical binary bytes.

The migration test decompresses this file, opens it through the new SwiftData schema,
finishes the retained fold/verification, activates it after an exact final transport
fixture and reopens again. It supplements the pre-Saved schema test. It does not
prove physical-device migration or every supported OS release.

The observation migration test also requires the new `rowMode` property to default
to false after reopening this genuine older model, while preserving all 1,005 facts
and completing activation. This is lightweight migration from the captured prior
Saved model, not evidence from every intermediate installed build or device OS.

## Saved view vectors

`SavedViewVectors.json` is generated together with the Android instrumentation asset
by `scripts/generate-saved-view-vectors.py`. Naming results execute the actual backend
`normalizedFolderName` function. Technical key vectors use framed UTF-8 SHA256 and
positive IEEE754 timestamp bits. Run the helper with `--check` to verify both copies.
The cases include NFC/trim behavior, contextual Greek sigma, Turkish dotted I and
fractional timestamps. These are synthetic policy fixtures, not user content.
