# A3 reference retrieval and translation trust

October 26, 2026. The local reference integration is implemented and verified.
A3 remains open for development rollout, real eligible-content inventory, provider
readback and semantic-quality review. The deployed development backend is still
A2 snapshot `e657024`; this document does not claim the A3 code is live.

## Result

Free, Pro and internal service generation share one selector for up to three
English or related-language comparison translations of the same canonical hadith.
It selects existing published, non-AI comparisons. It checks the exact translation,
publication, originating submission, language, text hash, current comparison/model
permissions, publication validity and retained scans/access dependencies. Unknown,
revoked, expired, unsuitable or oversized comparisons are omitted. No source policy
or permission is created by retrieval.

The existing E3 publication pipeline remains responsible for approving comparison
content. Ordinary AI output still uses the quota-controlled AI publication path;
a sourced comparison does not make the new output independently reviewed or
semantically approved. Model confidence and declared reference use are self-reports.

The provider receives source text and comparisons in separate untrusted JSON data
blocks. It returns `usedReferenceIds`, not arbitrary URLs. Only known, unique IDs
can become citations. The server rechecks the captured context before publication.
A mismatch or permission loss prevents publication and releases reader allowance;
actual provider cost is still recorded without prompts, text, identity or URLs.

Each captured reference binds its translation/publication IDs and one digest of
the exact language, text and effective citation. New generation keys include the
ordered comparison context and comparison policy version. A replaced reference
can produce a new generation; unchanged results are globally reusable without
another provider call or reader charge. Legacy AI entries without comparisons
retain their original identity and honest existing grounding metadata.

All supplied comparisons remain internal publication dependencies, even when the
model declares none used. Only declared used comparisons appear as citations or
count toward `groundingSourceCount`. This preserves input rights and cache identity
without padding the displayed source list.

The visible citation includes its retained source location, attribution and license
name. Duplicate source URLs are skipped. Comparison text is capped at 6,000 UTF-8
bytes per reference and the complete serialized comparison block at 24,000 bytes.
Private/capability-bearing links are rejected using the existing public-URL guard.

New AI output no longer invents a Sunnah.com URL from a different provider's number.
The old derivation helper is removed. In-flight older actions can still finish,
but their optional guessed reference URL is not published. Existing cached legacy
citation/reference metadata has not been migrated or independently audited.

## Expiry and native parity

The shared public availability check now validates captured comparison context.
Reader defaults, cached-generation reads and publication watches reject stale or
withdrawn context. The watch returns the earliest permission deadline, including
comparison dependencies. First reading uses that same deadline and retains
comparison attribution/license credits. It cannot keep a newly grounded starter
indefinitely after its source permission expires.

Both native readers already watch every loaded translation ID and remove its text
and citations at the returned deadline. The iOS and Android policy tests now cover
mixed AI/community results. The public response fields remain compatible; internal
reference bindings are not exposed as consumer API fields. No native screen or
new operator panel was added for this component.

The earlier Android source-disclosure repair, tappable source rows and fifteen-
locale disclosure drafts remain at `13d0199`. Those drafts still need native-copy
review. Their existing rendered fixtures are in `/tmp/hadithly-a3-reader-sources.png`
and `/tmp/hadithly-a3-ios-captures/2FC8176D-7653-4F9C-AFD3-FB83FACA805C.png`.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Citation-change and replacement-context regressions before their fixes | Both fail on the actual generation/completion paths | `/tmp/hadithly-a3-context-red.log` |
| Final backend strict typecheck | Pass | `/tmp/hadithly-a3-retrieval-complete-typecheck.log` |
| Final full backend suite | 545 tests in 44 files pass | `/tmp/hadithly-a3-retrieval-complete-backend.log` |
| iOS mixed AI/community expiry and revocation | Two tests pass | `/tmp/hadithly-a3-native-expiry-ios.log`, `.xcresult` |
| Android mixed AI/community expiry and revocation | Two tests pass | `/tmp/hadithly-a3-native-expiry-android.log` |
| Scoped whitespace and staged credential checks | Pass at commit | Git checks |

The backend fixtures use actual local Convex functions, real native DTO shapes and
an E3-published source fixture. Provider responses are controlled. They cover free/
Pro parity, one provider call, global cache reuse, unused references, invented and
duplicate IDs, in-flight revocation/citation changes, replacement context, expiry,
first-reading credits/deadlines, legacy cache identity, source-language retagging,
prompt bounds, private links and compatibility with an older action's URL field.
They are not live paid-model, rights-owner, language-quality or native cloud proof.

## Cost and source-policy readback

The implementation adds no web fetch, Google Search tool or extra model round trip.
Existing rolling allowances, single-flight, timeout, one-attempt HTTP policy and
monthly/daily budget controls remain in place. Numeric provider token usage still
settles the existing reservation.

Google's [official Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing#gemini-2.5-flash-lite),
checked October 26, lists standard paid text rates of $0.10 input and $0.40 output
per million tokens for the pinned Flash-Lite model. These match the existing code;
no pricing or billing setting was changed.

[Sunnah.now's official documentation](https://docs.sunnah.now/) describes its API
project as MIT-licensed. That statement alone does not satisfy the app's exact-text
comparison/model-processing permission fields. No additional content rights were
inferred or granted from it.

## Remaining gate

Deploy the tested code to development only with action-time approval. Inspect the
actual eligible comparison inventory before spending model calls. If none exists,
record the missing authorized content rather than fabricate citations or permissions.
Then verify provider output IDs, provenance and meaningful translation samples with
bounded live calls and inspect the resulting native source display. Retain the
existing original-source, historical-citation and independent semantic-review gaps.

No A3 deployment, permission change, private-account write, paid generation or
production operation was performed in this local integration. A2's prior approval
covered its own deployment and isolated sync tests, not these A3 actions.

The earlier WIP stash `035861f8d29985290a27bae6f32ecf69ec197830` is retained only as
historical recovery. It has been restored and superseded by this implementation;
do not reapply it over the finished reference integration.
