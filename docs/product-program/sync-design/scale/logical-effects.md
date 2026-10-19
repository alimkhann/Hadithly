# Logical folder effects

The selected manifest is the deletion-time identity set. A prepared deletion
commits by checking the current owner/folder/epoch/time again, deleting the folder
row, storing an owner-scoped folder tombstone and publishing its bounded terminal
receipt in the same transaction. Raw member pointers remain, but reads expose no
folder and writers compare against at least the deletion clock. The 50/100/75
delayed removal therefore cannot destroy Undo eligibility.

Undo stages eligible identities in bounded pages. A member must still have the
same Saved row, original raw pointer and original membership clock. A changed or
missing identity gets a per-member disposition. Each staged item has one slot
referencing its manifest/member fact and restore operation. An accepted concurrent
move/removal clears that slot and adjusts the preparing counters transactionally.
Older/tied observations leave it intact. No staged member becomes visible yet.
The deleted-to-restoring transaction reserves exactly one restore operation ID.
Another ID is superseded without staging or taking the destination lock. A valid
Undo begun before retention expiry reserves a renewable inactivity lease; each
successful page renews the later of the retained deadline or 30 minutes from that
progress. Cleanup cannot race a progressing reserved restore.

An existing same-name destination is locked against structural deletion while
ordinary membership/facet edits remain available. A new destination is created
only at the final visibility commit; if the name appeared while staging, reuse
that stable owner folder. Stages resolve their destination through one manifest
lookup, so no pending folder or redirect chain is exposed. The final transaction
freezes exact restored/superseded/missing totals and publishes the restore receipt.
Later edits never alter those historical totals.

Bounded materialization rewrites staged pointers without changing their effective
visible state, then releases the destination's structural lock. Every existing
physical delete/restore path must respect that lock. The consumed deletion handle
cannot reactivate anything after a later folder delete. Old exact operation replay
returns its original result; a new operation using consumed authority is superseded.

An unconsumed handle has a 30-day server retention window from logical deletion,
not from the old offline operation timestamp. Successful restore details have
their own 30 days from the visibility commit. An unconsumed handle's expiry first
materializes orphan membership clocks in bounded pages before deleting tombstone
and facts. Expiry never leaves unclocked orphan pointers. Already-restored handles
must finish materialization before cleanup. An unavailable old Undo gets an
explicit recoverable unavailable result and cannot create a folder.

The immutable receipt remains an exact historical effect after detail retention
ends. The future native outcome-page collector must record unavailable detail
honestly before ACK, preserving all locally available originals. It cannot invent
the original member list. Read/export pagination, that collector and the public
producer remain cutover gates. Current native consumers must retain their frozen
originals rather than ACK bounded manifest outcomes before collection exists.

Storage work reads at most four Saved/hadith identities per transition step,
keeping full-document point reads below the platform transaction budget even for
large imported rows. Preparation keeps its existing row/byte-limited scan.
Owner/generation/restore-operation/step fences make repeated workers idempotent.
Recover dispatch and expiry must recognize all new lifecycle phases.
