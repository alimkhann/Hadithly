# Bounded recovery and retiring an invalid frozen frame

October 19. Continue e1e75d5. Scope is unsendable persisted intent, separate from
large-folder architecture. No deployment authorized.

The current freeze loop limits selected valid operations, not inspected entries,
so one call can quarantine an entire invalid queue. A frozen frame bypasses fresh
local admission and retries unchanged even after a server rejects its old shape.

Rejected alternative: erase/requeue the frozen frame under a new operation or
sequence. A previously accepted/lost response, restored copy, or late RPC can then
apply twice or resurrect a later deletion. A cursor read alone is also insufficient:
a still-running old mutation can arrive after that read.

Chosen boundary: retireInvalidFrame(capability, clientKey, sequence) is a bounded,
owner-verified mutation carrying no operation payload. It fences only that sequence.
With no active receipt and the expected next sequence, it advances the closed cursor.
A future retirement records a sparse content-free fence without skipping valid
intervening work. Exact acknowledgement consumes only contiguous following fences.
At most 100 future fences may be outstanding per installation; completed prefixes
are compacted and ordinary expected-sequence retirement allocates no fence record.
This is an outstanding-work bound, not a lifetime ceiling. Active committed proof
is retained until its exact acknowledgement and is never labelled uncommitted.

The initial prefix high-water design was rejected after independent review found
that retiring seq7 could force another restored copy's unsent valid1-6 into
historical recovery. The revised actual Convex test executes1-6 normally, crosses
only the seq7 fence, then proves a late seq7 mutation cannot apply. Restored copies
still share the existing stream protocol's ambiguity for competing same-sequence
work; this fix does not invent unknown payloads or promise automatic restoration
of private data absent from a backup.

Native settlement verifies the captured owner, installation, requested sequence
and still-matching frozen frame before adopting the actual cursor. Available frozen
originals remain historical recovery, including unknown older acceptance; they are
never called exactly preserved. An occupied stream's proof is durably acknowledged
before a new frame. A lost retirement response leaves the original frozen frame
intact for safe retry. A stale response cannot clear a later frame.

Each freeze inspects at most 50 pending entries, retaining invalid originals. If
that produces no frame but pending work remains, the coordinator schedules another
bounded pass. Batch admission is rechecked before a frozen frame is sent. New valid
intent still uses exact ordinary receipts. Neither a device-local time reversal nor
policy tightening authorizes deletion of private originals or blind replay.
