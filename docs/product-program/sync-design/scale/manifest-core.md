# Resumable manifest preparation contract

The selected manifest design starts with a durable preparation, not a deletion
receipt. LibrarySync will hold the immutable folder frame until the later logical
commit supplies a terminal receipt. Preparation never changes visible membership.
This unit implements that preparation and automatic cleanup/recovery only. The
current native entry point is not switched to it yet.

The future caller invokes `prepareFolderManifest(ctx, verifiedOwner, operation)`
after validating the frame. It receives an owner-scoped manifest ID or a bounded
conflict. Repeating a still-valid operation/target/time returns the same preparation.
Changed, abandoned, expired and purging preparations return a terminal conflict,
never a live handle. Retry also rechecks the captured folder identity and epoch.
Reusing an operation ID for different intent is rejected. A folder has at most one
active preparation; an owner may have four. These are concurrent-work bounds, not
member limits. A blocked structural operation must remain pending in the future
coordinator, rather than being acknowledged as a successful delete.

Storage is a manifest header and small member facts. The header captures the
folder epoch, metadata time and identity. Facts retain item ID, hadith ID, raw
membership time and ordinal; they copy no note/provider text. Each scheduled step
checks owner existence, folder owner/epoch/time, generation and expected step.
It reads at most 50 members with an owner/folder index and explicit row/byte
pagination limits. Facts, cursor, count and next scheduled step commit together.
An interrupted transaction creates neither a partial page nor an advanced cursor.
Duplicate/late steps cannot append facts twice. The final page marks `prepared`
only after rechecking the same guard in that transaction. Prepared is not a
committed delete or an ACK-able receipt.

Any intervening placement clock change, move, restore or last-facet deletion
abandons preparation without touching the user library. Missing original folder
identity cannot be replaced by a newly created same-name folder. This bounded
conflict avoids rescanning a changing folder indefinitely. Worker recovery retries
stalled scanning headers in bounded indexed pages. Valid progress renews a
30-minute inactivity lease, so folder size is not capped by a fixed total runtime.
Unused prepared or abandoned facts expire automatically in 50-row cleanup steps.
No completed deletion/Undo authority is subject to this preparation lease. Its
separate retained-handle policy is still required before enabling logical deletion.

Account erasure removes the owner immediately and schedules bounded fact/header
cleanup. Headers remain discoverable until their facts are gone, so expiry can
recover interrupted cleanup. A worker whose owner/header disappeared cannot
recreate either. Fact enumeration is owner checked, paged and available only for
prepared manifests at the expected generation. Preparation metadata and facts are
not exposed through a mobile API in this unit. The later account export/page and
native pending-receipt migrations must be complete before cutover.

The temporary header is not permanent operation history. The frame adapter must
record an exact terminal conflict/commit proof before header cleanup can remove
its only status. A later unbound internal preparation may scan again after expiry
because no visible effect occurred; a committed or closed client frame may not.

Proof uses actual Convex contexts and scheduled functions at 501 and 2,001 members,
including interruption, duplicate steps, epoch changes, same-name recreation,
expiry, erasure and foreign IDs. Hosted byte limits, exact pending/terminal wire,
phase-aware effective membership, logical commit, restore, immutable outcome
pagination and both native integrations remain open. Preparation passing does not
turn the old 501-member support probe green.
