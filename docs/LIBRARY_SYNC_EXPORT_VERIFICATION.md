# A2 portable library export, local verification

October 19, 2026. Follows production caller checkpoint `65276cb`. This unit covers
local export ownership and content. A2 and its deletion/device/deployment gates
remain open. No cloud or private-account calls were made.

## Change

Both native exports now include `localLibrary`, containing the captured owner's
pending/frozen original intent, recoverable conflicts and invalid drafts, accepted
projection and owned cached library state. This retains notes that have never
reached the server. Local provider Arabic/English passages are removed by their
structural field names. User notes containing words such as `arabicText` or
`pushTokens` remain verbatim. Binding capabilities are excluded.

The former native export DTOs silently omitted backend fields. Android dropped
preferences, legacy data, evidence and sync; iOS dropped evidence and sync. Both
now preserve the complete JSON returned by the identity-scoped export query and
add the sanitized local state. The obsolete export DTOs are removed. Structural
forbidden-key checks replace scanning user text for forbidden words.

The export dialog captures its account before confirmation, the native device
check or the Android file picker. The query carries that account's opaque binding;
server-side JWT/binding verification rejects delivery under another account.
Native code validates the captured context again before file creation. Account
changes clear stale export presentation. iOS cancels pending work when leaving,
checks cancellation after the query, uses complete file protection and removes
managed temporary exports on account transition, sign-out, deletion and startup.
It retains the file while the system share UI may need it. Android writes only to
the location explicitly chosen by the user; an abandoned picker after recreation
has no captured context and writes nothing. An already downloaded user export
is independent of the app's account storage.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| iOS production core/facade, presentation policy and Settings helpers | 41 pass | `/tmp/hadithly-sync-export-releasecheck-ios.log`, `.xcresult` |
| Android production core/facade and wire adapter | 19 pass | `/tmp/hadithly-sync-export-releasecheck-android.log` |
| Generated native wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| Whitespace | Pass | `git diff --check` |

The new actual-store/facade test on each app places an oversized original note in
recovery and a valid private note in the offline account queue. Export retains
both, excludes structural provider/capability fields, preserves notes containing
forbidden field words, retains server sync/evidence fields through JSON roundtrip,
and rejects the captured A context after switching to B. B's export contains
neither original. The iOS cleanup test removes a managed dated export while
preserving unrelated files and a similarly named backup.

These fixtures use controlled transports. The actual export query's wrong-JWT
binding rejection is covered by the prior local Convex integration suite, which
has 388 passes. No backend source changed in this follow-up. Native raw JSON
subscription decoders compile against the installed SDKs; real authenticated
query, biometric/passcode, share-sheet, Android picker/provider failures and
cancellation during external file writes remain device/SDK checks. No end-to-end
export or deletion claim follows from these local results.

## Remaining A2 work

Deletion needs persistent retry phases, server prevention of recreation and
scope-captured confirmation. See `product-program/sync-design/account-deletion.md`
for source findings and the unimplemented contract. Scale, >500-member folders,
vanished anchors, installed-schema/old frozen invalid data, bounded quarantine,
Android suspended commits, final independent review, actual private two-device
sync and A2 deployment approval remain open. Historical integration records retain
their checkpoint-specific limits. This follow-up closes only local export content
and ownership implementation checks.
