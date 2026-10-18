# First-reading implementation decision

October 18, 2026. Candidate B is the base. The requested independent reviewer
model was GPT-5.6 Sol; its first review completed, while the requested addendum
failed at the provider's usage limit. That addendum is not evidence of review.

Use one cache-only public query and at most three prepared references per exact
supported locale. It never calls a provider, reserves quota, writes a Daily pick,
or changes today's identity. Carry A's explicit Daily summary and exact displayed
target. An Arabic original is deliberately modeled as original text, not a
fabricated Arabic translation.

The response is a tagged ready/unavailable result. Ready distinguishes Daily
from starter, includes full actual text and narrow public attribution, and has a
validity deadline. Native clients subscribe to current authorization and clear
expired or replaced content. Transport failure has Retry; missing content offers
language choice and continuation without claiming reading success.

Prepare references through an internal idempotent operation, validate current
display permission, and resolve current content/default/publication state again
on read. Prepared references never grant rights. Reuse existing publication
authorization with a shared bounded-read budget. Do not weaken it or invent a
parallel permissive validator.

Override the review's blanket requirement for offline/export redistribution on
all native display. Current policy distinguishes display from redistribution;
the development license explicitly permits display while denying redistribution.
Published evidence retains its established publication permission checks.
Translation-specific permission gaps remain real, rather than being erased by
the presence of a live/default row.

Do not claim A1 passed from fixture results. Development currently has 46
translation rows in four locales (kk, ru, tr, uz); current publication, generation
identity, quality and permission still need validation. Other supported locales
need real authorized content. A truncated hadith inventory cannot prove complete
license coverage. No new research videos or later redesign starts here.
