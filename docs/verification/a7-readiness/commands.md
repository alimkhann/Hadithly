# Repeat the local A7 readiness checks

Run from the repository root. These commands use no accounts, network services,
phones, participant data or encrypted volumes.

```sh
python3 scripts/verify-a7-readiness.py --output /tmp/hadithly-a7-readiness-repeat.json
python3 scripts/localization_audit.py --allow-drafts
python3 scripts/generate-analytics-catalog.py --check
git diff --check
git diff --cached --check
git diff --stat
git diff --cached --stat
```

The verifier freezes 1,747 starting tracked paths and five incoming working/index
paths at `157def4`. It preserves old verifiers, blank templates, fourteen metrics,
all original program checkboxes and historical sections. It compares all 41 copied
gate records to unchanged A6 input, including dates/scopes/receipts/dependencies
and actions. It checks eight dated capacity slots, latest possible D14 completion
before follow-up, day-21 close/day-28 deletion, draft wording hashes, links,
scoped stage paths and UTF-8 credential/artifact markers. Inspect the actual staged
content too; a pattern scan is not exhaustive. Do not replace the baseline to
conceal a changed input.

The inherited A7 verifier passed before edits. Its result is `inherited-check.json`.
It cannot accept this later scope. Do not loosen it or report a scope rejection as
a product failure. No new native artifact readback or app run is claimed here.

The earlier combined `audit-la2.mjs` failure is retained in the frozen A7 planning
record. Do not regenerate the old eight-locale copy catalog, add live flags or
label the combined audit passing. Closed-catalog and resource checks here are
fresh local checks; the prior twelve backend tests remain historical.

Stage only the packet, audit, this folder, `verify-a7-readiness.py`, current
program/handoff pointers and appended decision. Leave all five incoming paths
and the pre-existing Python cache unstaged. Run the verifier after staging to a
temporary output, then review staged and unstaged diffs separately. Commit without
pushing, inspect commit paths and rerun verification to a temporary path.

This proves documentation consistency and byte preservation only. Current
collection-off, qualified language review, actual rights, build/install approval,
encryption/deletion feasibility, consent and observation remain unverified.
