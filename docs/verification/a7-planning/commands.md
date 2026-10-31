# Repeat A7's local planning checks

Run from the repository root. These commands do not use accounts, network
analytics, devices or participant data. Never replace the baseline with current
bytes to conceal a changed input. No participant template may be filled in git.

```sh
python3 scripts/verify-a7-planning.py --output /tmp/hadithly-a7-repeat.json
node scripts/audit-la2.mjs
python3 scripts/localization_audit.py --allow-drafts
git diff --check
git diff --cached --check
git diff --stat
git diff --cached --stat
```

The combined LA2 audit currently stops at its older eight-locale copy-generator
check against the later catalog. This failure also reproduces on starting commit
`a447fec`, independent of incoming catalog changes. Do not run the generator in
write mode to make it green. The recorded scoped alternatives are:

```sh
python3 scripts/generate-analytics-catalog.py --check
node scripts/create-analytics-dashboard.mjs
cd backend
npm test -- convex/analytics.test.ts
```

Compare the printed dashboard JSON with `docs/LA2_DASHBOARD.json` from the repository
root; it must match exactly. Do not use `--apply`. The actual local results and
the failed combined check are both retained in `local-checks.json`.

To regenerate the explicit G01-G41 carry-forward document from A6's unchanged
inventory, run `python3 scripts/verify-a7-planning.py --render-gates`. Inspect the
diff before staging. All 41 statuses must remain open, including G38.

The A7 verifier checks the 1,737 frozen immutable tracked inputs, incoming working
bytes and index entries, original program checkboxes, historical sections,
allowed file scope, all eight metric fields, catalog names, local links and staged
UTF-8 secret/artifact markers. It cannot judge consent comprehension, semantic
quality, actual participants, current service settings or release readiness.
Hash preservation is not a new app acceptance test. The LA2 audit runs only its
local catalog/dashboard/allowlist/expiry/cap/retry tests. Do not add `--live` or
`--dev-ingress`; those are external actions outside this unit.

At session start, before any A7 edit, this command passed:

```sh
python3 scripts/verify-a6-readiness.py --raw-native --output /tmp/hadithly-a7-inherited-readback.json
```

It re-read 37 historical artifacts without running apps. The compact copied
results are in `historical-readbacks.json`. A6's frozen verifier cannot accept a
later A7 documentation scope. Do not change it. Raw temporary artifacts may be
unavailable in a future checkout. Report missing artifacts rather than infer a
new pass from a committed summary.

Before commit, inspect both diffs and the catalog semantic delta without printing
the whole catalog. Stage only the A7 documents, verification folder, verifier and
current program/handoff pointers plus the append-only decision. Run the verifier
again after staging. Its staged scan is a pattern check, not a guarantee against
all secrets, so inspect the staged contents as well. Leave the five incoming
catalog/project files and pre-existing Python cache outside the commit. Verify
commit paths and remaining worktree after committing. Do not push.
