---
name: hadithly-convex-cost
description: Diagnose Hadithly Convex usage against measured reader journeys before optimizing costs.
---

Start with one journey, such as cold launch to first reading or ten page swipes.
Record deployment, build, cache state, interval and whether the evidence is local
or live. Read the affected Convex functions and native subscription lifecycle.
Consult current official Convex documentation for the mechanisms under review.

Measure the available dimensions separately: function calls, database reads and
bytes, bandwidth, storage, action execution and provider calls. If dashboard or
account access is missing, mark those values unavailable. A local call count does
not establish billed usage, and a free-plan capacity claim needs a measured model.

Trace repeated work to its caller: duplicate subscriptions, broad reactive query
dependencies, repeated page fetches, retries, overfetching, missing shared cache
reuse or eager generation. Treat these as hypotheses until measured. Check
authorization, exact-locale/provenance identity, freshness, revocation, offline
behavior and quotas before changing query shape or cache lifetime.

Rank opportunities by measured cost, reader impact and correctness risk. Propose
one bounded change and compare the same journey before and after. Preserve Convex
as the only mobile API and control plane. Cloud configuration, deployments,
migrations, entitlement changes and paid generation require their existing
action-time approvals. Do not add a second backend or a hidden quota bypass.

Report the measured reduction and uncertainty. Estimate users supported only
from explicit workload and current plan assumptions; do not promise unlimited
free capacity. Stop after the agreed diagnostic or optimization unit.
