# Repeat the local A6 audit

Run from the repository root. The matrix is generated from `gates.json`.
The baseline refers to the A6 starting commit and incoming working bytes, not a
future clean checkout. Do not regenerate the baseline to hide a changed input.

```sh
python3 scripts/verify-a6-readiness.py --render
python3 scripts/verify-a6-readiness.py --raw-native --output /tmp/hadithly-a6-repeat.json
python3 scripts/localization_audit.py --allow-drafts
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_localization_audit.py

git diff --check
git diff --cached --check
git diff --stat
git diff --cached --stat
```

The verifier checks every baseline gate entry remains present with only A6's
explicit-retention checkbox changed, matrix/inventory parity, owner/evidence/
missing-receipt/action fields, exact incoming working bytes/index blobs, A5 native
source hashes, all unchanged evidence files, historical requirements and allowed
local scope. Its raw mode re-reads completed xcresult/XML artifacts without
launching an app, test runner, account operation or device. All before failures,
rejected attempts and mixed bundles retain their per-case identity. Missing raw
artifacts fail explicitly; restore or rerun an approved local scope rather than
inventing a pass. Readbacks are historical, even when read again today.

The old A4/A5 preservation scripts freeze their own session scope and older
checklist state. A6's verifier carries those immutable records forward while
allowing this audit's documentation and A6 checkbox. Do not loosen those older
scripts to make a later session pass. Product behavior parity is established
here by exact source preservation, not a new native acceptance run.

Before committing, inspect both diffs and scan only staged UTF-8 text for secret
markers, credential assignments and accidental artifacts. Stage only A6 audit,
script/evidence and current program/handoff documents. Leave the five incoming
catalog/project files and Python cache unstaged. Commit locally and verify its
path list and remaining worktree. Never push as part of this unit.
