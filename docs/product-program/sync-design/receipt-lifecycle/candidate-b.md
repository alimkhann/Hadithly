# Candidate B: per-entity conditional versions, no batch receipt history

Parent-authored fallback candidate. The requested independent worker failed at the
account usage limit. This is a structurally separate parent sketch, not an agent
result or a source-reviewed implementation.

## Caller first

Each private read returns a version token for each facet, membership, folder key
and collection position. A native intent captures that base version along with
its desired value and unique operation ID. The server applies an intent only if
its base still equals the current entity version, then uses its operation ID as
the new version. A retry whose ID is still the entity's current version returns
preserved; otherwise a changed base returns an explicit conflict/unknown outcome.

## Shapes and state

Domain register {owner, entityKey, version, lastKind, valueOrTombstone}. Command
{operationID, baseVersion, desiredValue}. Native frozen batches retain commands and
original private values. Native receipt settlement retains conflicts; no explicit
server acknowledgement or per-batch ledger is needed.

Facet mutations and collection positions are independent registers. A membership
has a register separate from the facets. Folder creation is a register keyed by a
stable client folder identity; deletion updates that register and its affected
memberships atomically. A folder deletion must capture every affected member's
base version or choose a separately versioned folder-member snapshot contract.

## Failure transitions

- Apply response lost, entity still at operation ID: retry observes exact current
  preservation, performs no second mutation and returns receipt.
- Another write follows first apply: old base mismatches. Return unknown/conflict,
  keep original local intent for recovery and never reapply automatically.
- Crash before/after native settlement: frozen originals persist until that exact
  receipt is committed. Receipts need no server retention.
- Old backups have old bases; changes cannot be replayed after later deletes.
  Unknown outcomes retain available original content as historical recovery.
- Same base submitted concurrently: one conditional transaction wins. The loser
  retains its original intent, with the cloud winner selected automatically.
- Multiple devices need no stream coordinates, but require causal base versions
  from a verified owned read before every new entity intent.
- Erasure invalidates binding and discards domain registers. A newly created user
  has a different owner key. Old tombstone bases cannot authorize writes there.

## Undo

The undo base is the deletion's exact operation ID. A newer write changes that
base, so conditional restoration cannot overwrite it. Folder undo has the same
requirement on every requested membership and returns partial outcomes explicitly.

## Bounds and rationale

One version/tombstone per domain identity, with no per-batch or per-operation growth.
This is naturally bounded for repeated reading positions. The price is a new
causal contract in every private query, every write and all existing legacy callers.
A folder delete's many affected versions must be captured consistently before the
intent is frozen. Those reads cannot be substituted by a current boolean state.
Offline guest-to-account claim has no base token: it needs a distinct merge policy
that establishes a base before issuing normal conditional operations.

This alternative preserves available private content, but cannot return a past
exact receipt after the entity has changed. Repeated offline/account-claim conflicts
would produce more unknown recovery outcomes than candidate A. It also replaces
current newest-note/position semantics with first-valid-CAS unless an extra merge
layer is added. That changes the existing product contract and increases interface
complexity across all native call sites.

Rejected an unversioned last-write-wins timestamp-only register: old equal clocks,
folder creation and undo have no reliable causal identity. Rejected treating the
current query value as acknowledgement: it says nothing about an overwritten past
operation's actual preservation.
