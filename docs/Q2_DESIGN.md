# Q2 subscription authority and purchase operations

## Work phases

- [x] Ground the webhook, user projection, rolling quota, native SDK and Settings paths.
- [x] Compare transaction-event and authoritative-snapshot candidates.
- [x] Proceed under Q2 authorization; separately approve actual regional tiers and external rollout.
- [x] Implement snapshot reconciliation and both native account boundaries.
- [x] Revisit SDK operation serialization, durable recovery and rejected-request counters using reproduced defects.

## Problem and caller usage

RevenueCat events previously wrote a tier directly. A product-name substring
could grant Pro, billing grace could end early, and one store's expiry could
remove a valid purchase in another store. Equal-time events could overwrite each
other. Native purchase callbacks retained account state and Android restore did
not always finish. The store SDK can post a purchase under its current App User
ID after the system sheet returns, so callback filtering alone is insufficient.

The reader calls generation as before; Convex remains quota authority. Only a
quota rejection opens the existing paywall. Both native managers serialize store
operations with SDK identity operations, then call the identity-derived
`actions/subscriptions:refresh` before reporting purchase/restore success.
Settings subscribes to `subscriptions:getStatus` while visible, keyed by Clerk
account ID. It exposes manage and restore, never a second paywall entry.

## Shape

`lib/revenueCat.ts` parses untrusted delivery and subscriber data into exact
catalog purchases. `subscriptions.ts` owns user refresh revisions, receipt
replay, erasable retry bindings, and effective access. Node action
`actions/subscriptions.ts` owns the bounded RevenueCat GET and durable retry.
HTTP authorization precedes parsing, then atomically stores a receipt and
schedules processing. Native callers never provide identity, tier or products
to backend refresh.

```ts
type PurchaseAccess = {
  productId: string; store: "app_store" | "play_store";
  paidUntil: number; until: number; phase: "paid" | "cancelled" | "grace";
};
subscriptionAccess(user, now): PurchaseAccess | FiniteLegacyAccess | null;
parseRevenueCatSnapshot(wire, clerkId, policy): {
  observedAt: number; purchases: PurchaseAccess[]; ownershipConflict: boolean;
};
// Identity-derived, no client arguments.
actions/subscriptions:refresh(): Promise<boolean>;
subscriptions:getStatus(): EffectiveSubscriptionStatus;
```

A snapshot selects any eligible Apple or Play purchase. Two purchases still give
one allowance of 100 in any seven days. Paid cancellation keeps finite access;
explicit grace extends the deadline. Refunded, expired, held beyond paid/grace,
family-owned, unregistered, and wrong-environment purchases cannot grant.
Google's REST product key and `product_plan_identifier` normalize into the same
`subscriptionId:basePlanId` used by its SDK. Lifetime and weekly products never
enter the catalog. Legacy Pro needs a finite expiry during rollout.

A newer refresh revision fences older responses; snapshot observation time must
not move backward. Refund/expiry wakes can transiently suspend access before
reconciliation, including a valid overlapping purchase during an outage. Ordinary
refresh failures keep a known finite grant. Four bounded attempts are followed by
hourly recovery of at most 20 failed or stale queued receipts. Successful processing deletes
user bindings. Account deletion erases pending bindings; a stale action cannot
recreate the account. Receipt IDs without account data expire after 90 days.

Unexpected transfer destinations remain denied with an ownership conflict.
RevenueCat now keeps purchases with their original App User ID. Recovering a
lost or deleted original account requires an exceptional ownership correction,
not routine approval or an implicit receipt transfer to a new Clerk account.

Both native `PurchaseAccountGate` implementations clear state immediately and
fence completions by account/revision. `PurchaseOperationQueue` holds SDK identity
stable through store purchase or restore. The queue does not hold the identity
lock across backend reconciliation. A switched account rejects the old result;
SDK success with backend denial never unlocks generation. Restore always ends,
including no entitlement, account change and failure.

`PendingPurchaseStore` persists the owner and unresolved operation before the
SDK starts. On relaunch the SDK is configured with that owner; another account
cannot move it before resolution. A cancelled retry cannot erase older pending
ownership, and a no-purchase restore cannot clear an unresolved first purchase.
Corrupt storage fails closed. Both platforms retain private device state only
until settlement; actual interrupted receipt delivery remains store proof.
Backend-confirmed own-account access also works when the other platform's store
SDK is not configured, while local purchasing remains unavailable.

The approved free/service spend pool is $2 inside the existing aggregate $10
monthly AI budget. It reserves and settles atomically, separately from paid
attempts. Budget-rejected free requests consume no shared provider-attempt slots.
Pre-Q2 unattributed spend is conservatively counted as free until month end.

## Synthesis decision

The snapshot candidate is the base. The independent judge scored it 27/30 versus
24/30 for transaction reducers. Event history cannot infer missed grants,
overlapping purchases and hold/grace reliably; current RevenueCat state hides
that complexity behind one backend decision. Grafts from the event candidate are
finite deadlines, exact app/catalog admission, terminal restore outcomes, native
identity revisions, origin-store manage guidance and a lifecycle fixture matrix.
We reject dual event/snapshot tier writers and removed the old direct tier API,
including migration of its Q1 verification caller.

The chosen durable queue differs from a synchronous HTTP reconciliation. HTTP
acknowledges only after receipt and scheduling commit atomically. Retry state and
hourly recovery prevent an outage longer than the short retry series from
stranding a paid account. No new mobile backend or required operator queue exists.

## Accepted limits

REST v1 is product-keyed. Apple and Play IDs stay distinct, and sandbox accounts
must be isolated from production subscribers. Ambiguous historical refunds or
same-product collisions fail closed and require store readback before launch.
Exact catalog-to-pro association and origin-account restore behavior are external
configuration requirements, verified independently of builds.

The existing Apple SDK key supports subscriber GET without a new secret key or
grant/delete privileges. Only this GET is used. No customer attributes are needed.
Production rejects sandbox data; sandbox policy is allowed only at the exact
festive-cobra-664 cloud URL. Development rollout is separate from production.

Costs, approved tiers and maximum-source limits are in `Q2_PRICING.md`. Typical
quota profitability is proven by a reproducible calculation, not an assertion
that every free reader costs zero or every possible generation size is profitable.
Real store journeys and paid/grace/refund receipts remain separate launch gates.
