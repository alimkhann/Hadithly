# E4 design

E3 passed its development gate on 2026-10-11. E1's device matrix and the
release gates remain open. This session stops before Q1.

## Work checklist

- [x] Ground E1 intake, E2 extraction, E3 publication, public reads, and deletion.
- [x] Compare independent case-centric and publication-centric sketches.
- [x] Select the design without a human checkpoint.
- [x] Implement automated cases, revocation, retention, operator and native flows.
- [x] Verify real backend transitions and both native experiences.
- [x] Commit implementation and accurate gate records.

## Caller and flow

Contributors observe `evidence:getOwnEvidenceDraft` and submit an owned appeal.
Reports retain the existing `actions/ai:reportTranslation` contract. Both enter
durable automatic cases. A case can request a fresh E3 review, suppress content,
or expire. Only `evidenceReview.finish` can publish.

```ts
await client.mutation(api.evidenceCases.requestAppeal, { submissionId, reason });
await client.query(api.evidenceOperator.listCases, { paginationOpts });
await client.mutation(api.evidenceOperator.act, { caseId, action: "takedown", reason: "privacy" });
```

## Shape

`CaseKind = exception | report | appeal | audit | recheck | incident`.
Cases own a discriminated queued/running/resolved state, attempt count, deadline,
private context, and an opaque audit receipt. E3 review jobs refer to a case when
one triggered the review. An attempt starts only after a worker claim; three
attempts and bounded backoff end automatically. Permission and safety blockers
resolve privately without disclosing evidence to a model.

`lib/evidenceCasePolicy.ts` owns pure deadline and retry policy.
`evidenceCases.ts` owns authenticated admission, recheck preparation, resolution,
revocation, and retention. `evidenceOperator.ts` verifies JWT identity plus the
server operator flag on every command. A separate CLI tool uses these endpoints.
`lib/evidenceAudit.ts` appends typed coarse facts. A private identity mapping
links verified operator receipts until account deletion. Audit facts contain no
content, URLs, storage IDs, user IDs, or arbitrary metadata.

All public translation reads use one eligibility predicate that rereads current
permission dependencies. This closes the interval before scheduled revocation.
Native readers observe availability of loaded translations and clear withdrawn
text and citations. Expiration also clears proposal and case/report/appeal text.
Rejected evidence gets 30 days from the first rejection; retries never extend it.

## Alternatives and synthesis

Two independent sketches compared cases around E3 with a separate publication
lifecycle worker. A third reader scored the proposals against publication
authority, immediate visibility, retry/spend bounds, privacy, and interface size.
The case design is the base because it preserves one publisher. The publication
design supplied immediate public validity, stale-result rejection, connected
cache clearing, and cumulative spending limits. A second publisher and a required
operator inbox were rejected.

The implementation accepts temporary private suspension after an actual adverse
review. An allegation, stale concern batch, unavailable provider, or exhausted
budget cannot by itself withdraw an otherwise valid publication. Unbound
official/AI reports resolve as private incidents when licensed review provenance
is unavailable. Unknown-rights community rows stay hidden and expire. The optional
operator can make an audited takedown, but cannot invent provenance or rights.

Model work has three attempts per case, six independent-review pairs per target
over 30 days, and 100 pairs globally per rolling day. An anonymous global ledger
survives account deletion without retaining identity. The private target ledger
is deleted with the account. Processing retries retain E2's three-claim ceiling.
Waiting for the shared worker spends no attempt.

Successful replacement does not start a rejection clock. A new adverse decision
after publication gets a fresh 30-day window; an appeal or retry within that
window never extends it. Batch retention schedules bounded continuations rather
than leaving a backlog for the operator.

Comparison publication dependencies remain bound to their source revision. Its
deletion or rights change suppresses dependent public reads immediately and
queues fresh review. Local timers clear each separate permission deadline.
Previously installed version-1 pack text is suppressed on both clients because
that format cannot preserve entry rights or revocation identity. The new pack
format remains an O2 gate.

## Optional operator tool

Run `backend/tools/evidence-operator.mjs` with `HADITHLY_CONVEX_URL` and an existing
verified Clerk Convex JWT in `HADITHLY_OPERATOR_JWT`. Never use a deployment key as
consumer authentication. `list exception|appeal|audit|incident` returns coarse
state, an opaque audit receipt, and the current version. `audit <receipt>` reads
typed facts. `recheck|suppress|takedown <caseId> <version> <reason>` requires a
rights, privacy, unsafe, incorrect, policy, or audit reason. Every call rereads
identity and the server operator flag. A changed version requires a refresh.

This CLI is outside mobile navigation and Settings. There is no approve, publish,
force-safe, or rights-waiver command. Routine cases resolve or expire without it.
Application APIs cannot patch or delete audit facts; privileged deployment/database
administrators retain their existing powers.
