# E3 design

E2 passed in development on 2026-10-10. E1's remaining device matrix stays open.
This session adds contribution review and publication only. E4 remains closed.

## Work checklist

- [x] Ground the intake, extraction, publication, and deletion paths.
- [x] Compare two independent architecture sketches.
- [x] Select a design without a human checkpoint.
- [x] Implement permission assessment, review, publication, and native status.
- [x] Run backend, deployed, native, and adversarial verification.

## Caller and flow

The contributor continues using the existing evidence form and owner subscription.
When E2 finishes, it schedules one E3 action. That action claims an immutable
review packet, makes two fresh independent model requests, and submits their
results to one atomic mutation. Only that mutation can publish community text.

```ts
const claim = await ctx.runMutation(internal.evidenceReview.claim, {
  submissionId, reviewEnabled: configuredPaidReview,
});
if (!claim) return;
// Both calls receive the same packet. Neither receives the other's answer.
const passes = await reviewIndependently(claim.packet);
await ctx.runMutation(internal.evidenceReview.finish, {
  submissionId, token: claim.token, passes,
});
```

## Ownership

`lib/evidenceReviewPolicy.ts` owns deterministic assessment, citation validation,
review parsing, and the publication predicate. `evidenceReview.ts` owns trusted
permission ingestion, claims, snapshots, leases, and atomic writes.
`actions/evidenceReview.ts` owns bounded model transport only. Existing owner
queries project status and public-safe citations to both native apps.

A cached source policy grants specific rights once for a publisher and scope.
Canonical reference checks and exact hashes bind each new artifact to that policy.
An exact artifact permission grant binds source kind, source URL, raw artifact checksum,
extracted-text checksum, canonical hadith, exact language, rights-holder proof,
and permitted uses. Access, comparison, and model processing are separate from
adaptation, display, and redistribution. Uploaded prose and model output cannot
create a grant. Unknown rights are held privately without model disclosure or a required admin queue.

Source adapters read permitted materialized Sunnah.now English, explicitly
permitted Sunnah.com evidence, approved translations, related-language
translations, and labeled AI context. They never scrape or generate comparison
text. Historical approval and an AI label do not establish provenance or rights.

All source text, proposal text, and citation labels stay inside `untrustedData`.
Reviewers have no tools, network access, user identity, source storage IDs, or
credentials. Credentials exist only in the transport client. Two distinct model
IDs receive fresh requests with different fixed review instructions.

The final mutation reconstructs its snapshot, rereads permissions, scan state,
abuse/deletion state, and current translation defaults, and rejects stale input.
It checks stable span IDs and exact quotes against retained offsets, plus the complete comparison set. It never averages
or rounds confidence. The owner's E3 prompt says threshold boundaries do not
auto-publish, so exactly 0.95 is held; both passes must be strictly above 0.95.
This session-specific rule is stricter than the earlier plan's inclusive wording.

## Synthesis decision

Candidate A's single bounded action plus atomic finish is the base. Candidate B's
exact artifact grants, snapshot binding, and durable pass records are retained.
A resumable per-pass workflow would add states and expose coordination without
changing the publication guarantees. Failed reviews stay private; they do not
trigger unbounded paid retries. One global review lease bounds concurrency.

Account deletion and withdrawal must remove new private review records. Published
citations contain public source facts only, never contributor identity or files.
Existing account deletion removes that account's contributed translations as
before. E4 owns appeals, takedown, and broader retention policy.

## Owner-directed app-wide automation

Routine approval is retired across the app. The unused legacy submission writer
and manual queue were removed, both reader badges now identify contributor text,
and community citations no longer claim AI authorship. E4 will automate reports,
appeals, rechecks, and retention; its operator tool is optional. Topic classification
will suppress unresolved results after a bounded independent check rather than
create a required human backlog. Store/legal and credential action boundaries remain.

## Current runtime evidence

The actual development key was invalid. With owner authorization, the existing
valid production key was read privately, validated against Google, and installed
in development only. No key was created or revoked and production was not modified.
The real review probe returned `gemini-3.8-flash` and `gemini-3.5-flash-lite`,
both at confidence 1, with a deterministic `publish` decision for self-authored
synthetic text. Native status tests passed on the E2 simulator/emulator identifiers.
The updated Cloud Run worker passed its full 14-test Linux suite and private cloud checks. The final native publication and reader verification are recorded in `E3_VERIFICATION.md`.


## Offline and reader boundary after adversarial review

Version 1 translation packs do not carry per-entry permission, attribution, and
citations. They cannot export stored translations, including licensed E3 text,
unbound official text, historical community rows, or AI text. Base dumps keep
their existing verified license contract. A versioned pack format is an O2 gate.

English reader pages first resolve the stored public default without generating
text or requiring sign-in, then fall back to provider English. Contributor source
badges open the same source sheet as other stored translations. Public community
payloads omit model confidence and private contributor/review identifiers.
