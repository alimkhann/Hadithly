# Q1 generation and cost design

## Work phases

- [x] Ground the existing reader, cache, quota, entitlement, and deletion paths.
- [x] Sketch two distinct designs and compare them.
- [x] Proceed under the owner's Q1 instruction.
- [x] Implement and verify the chosen design locally.
- [x] Revisit source permission, proof binding, native request state, and budget reservations using reproduced defects.

## Problem

The old action checks a monthly counter, calls Gemini, increments the counter,
and writes the cache in separate transactions. A concurrent request can duplicate
provider spend or charge without publishing new content. Both readers also invoke
this action automatically for each non-English page item.

## Usage

Opening a page reads one bounded batch of existing exact-locale translations.
An explicit hadith translation action obtains a short-lived integrity challenge,
submits native proof, and calls `actions/ai:translateHadith`. The backend returns
cached text, a new translation, or a distinct quota, busy, rate, or integrity
error. Only a quota error offers the paywall. Remaining allowance and retry time
appear with the requested hadith, never in general Settings.

## Shape

`quotas` owns admission, reservations, fenced leases, completion, and rolling
allowance. `generationPolicy` defines canonical source keys, exact supported
locales, window boundaries, and numeric token costs. `generationIntegrity` owns
one-use challenges and credentials. Its Node verifier checks App Attest or
Google-decoded Play Integrity before admission. `actions/ai` owns the one bounded
structured-output provider call and passes numeric telemetry to completion.

```ts
type Admission =
  | { kind: "cached"; translation: PublicTranslation }
  | { kind: "busy"; retryAt: number }
  | { kind: "rejected"; code: GenerationError; retryAt: number | null }
  | { kind: "claimed"; jobId: GenerationId; attempt: number; hadith: Hadith };

// Internal mutations. The public action derives identity and verifies proof.
admit({ hadithId, language, clerkId?, verifiedProof? }): Promise<Admission>;
finish({ jobId, attempt, outcome, numericTelemetry }): Promise<PublicTranslation | null>;
// Identity scoped; no client user IDs, limits, clocks, models, or prompts.
getAllowance(): Promise<{ limit: number; remaining: number; retryAt: number | null }>;
```

One global key hashes canonical identity, authoritative source text, exact locale,
model, and prompt version. A pending job reserves one initiating user's slot.
Completion inserts the translation and immutable success event atomically. Service
successes record an anonymous global event and consume no user's allowance.
Approved or cached winners record no event. Failure records numeric attempt cost
and releases the reservation. Source changes and stale attempt tokens cannot
publish. Account deletion erases owned quota and credential records, detaches
the public cache, and retains an anonymous running lease until its deadline.

The counted interval is `(now - seven days, now]`. Admission includes active
reservations. Entitlement changes affect the limit immediately without rewriting
history. Retry time accounts for all events that must expire after a downgrade.

## Synthesis decision

Candidate A's synchronous action plus transactional admission/completion is the
base. It preserves the native request shape and hides quota coordination behind
two internal mutations. Candidate B's durable scheduled job would add job
subscriptions, scheduled executions, and lifecycle APIs. We retain its global
global success accounting, separately erasable charges, source-content fingerprints, batch cache reads,
and compact collection-count proposal. We reject a new polling cron and a second
backend. The independent design judge chose A, scoring it 25/30 against B's 24/30.

## Tradeoffs

The provider has no end-to-end idempotency guarantee. A bounded provider timeout
is shorter than the lease, and completion is fenced. A crash can leave an
ambiguous paid attempt, but cannot create duplicate publication or quota events.
No claim is made that an upstream provider bills exactly once across crashes.

Verified platform proof needs real device and service configuration. Development
can explicitly allow unavailable proof only on the named development deployment.
Production fails closed. Cached reading bypasses generation proof and quotas.

## Cost scope

Q1 removes automatic AI and ordinary grounding, batches page cache reads, removes
the monthly reset scan, and materializes compact outline counts for progress.
Full reader-page materialization, CDN deployment, notification scheduling, and
service-plan changes remain separate work. See `COST_REVIEW.md` for prior measured
usage, and `Q1_VERIFICATION.md` for current proof and open deployment gates.
