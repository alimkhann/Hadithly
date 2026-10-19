# Held folder frame contract

Caller usage remains one queued folder operation. Both native coordinators retain
the immutable frozen frame while a server worker runs, poll a bounded work proof,
and settle only the final exact receipt. New freezes isolate delete/restore frames.
Already-frozen mixed frames retain their original representation and existing
synchronous handling until the complete folder cutover supplies a migration rule.

One stream has an optional outstanding slot, a union of committed receipt or
pending work. Pending metadata contains installation, sequence, batch ID/digest,
an exact cross-native content fingerprint,
manifest identity/generation and a bounded retry interval. The server retains the
bounded original batch in its pending slot. A cursor returns only the metadata.
There is no state with both pending and committed work.

`holdFolderFrame` is an internal domain call after owner, frame and manifest
admission. It binds one isolated immutable frame to one still-valid owner manifest.
Another frame or installation cannot steal that work. Application retries and a
new owner-checked poll return pending until a worker writes an exact terminal
receipt in the same transaction as its effect or no-effect conflict. Preparation
alone is not success. No public producer is enabled until logical delete/Undo and
their bounded outcomes/read/export paths are ready.

ACK cannot advance a pending slot. Invalid-frame retirement returns the pending
proof and cannot close it or skip valid earlier work. Future sparse retirements may
still be recorded, and are consumed only after the held frame reaches terminal
receipt and exact ACK. Manifest failure commits its terminal conflict before
cleanup; expiry cannot erase the only frame result. A missing worker/owner cannot
recreate erased stream data. Any success publisher must run within the future
logical business commit transaction, never merely on prepared status.

Native stores persist pending metadata before yielding. An exact fingerprint, not
IDs alone, identifies a matching frozen original. That original
stays frozen, without sequence increment, confirmation or ACK. A restored copy
with different local intent archives its available original as historical and
waits on the server proof. It may ACK a later foreign committed slot without
claiming its original intent was preserved. Unknown waiting proof survives reopen,
export and account changes in its existing owner partition. Polling happens before
new freeze/admission, with captured session checks and a delay instead of a tight
loop. Bad proof fields fail without clearing local originals.

The outstanding-slot wire and server schema replace the old active-only shape in
both native consumers together. No deployment is authorized. Before deployment,
read back any existing development stream data and migrate an old schema if it
exists. Real installed/client/SDK delivery remains a gate. The 501-member product
probe stays open until the producer, logical effects, Undo and native behavior
are complete.
