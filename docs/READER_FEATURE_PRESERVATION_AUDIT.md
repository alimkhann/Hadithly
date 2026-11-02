# Reader feature and saving audit

November 2, 2026. The owner accepts that 1.34 ms/s may be sufficient and asks us
to stop marginal tuning if it is no longer useful. This audit answers whether
the scrolling repairs removed capabilities or weakened adjacent behavior. The
next product session is page/volume transitions, not another speculative
renderer rewrite. The owner tried the restored installed build and confirmed
that scrolling is good enough to close this round. The strict target remains
unachieved; this is acceptance under the owner's revised product decision.

## What changed

No reader capability was intentionally removed in the retained scrolling
changes from `85adf64` through `a6c3035`. Arabic and translation layers, font and
theme settings, source actions, bookmarks/favorites/notes, offline reading,
translation retrieval/generation, progress capture, account sync, focus controls
and semantic restoration remain in the production paths. Floating controls and
text behind them were restored. Gesture behavior is back to the retained code:
the early-axis experiment failed at 2.68 ms/s and was reverted.

There are real timing tradeoffs. Remote Saved/progress projections wait while
scrolling, so an update from another device may appear after a pause rather than
mid-gesture. The newest scroll position is initially in memory; durable saving
waits for quiet or an explicit lifecycle flush. These distinctions matter even
though the feature list remains intact.

The restored optimized development app is installed and launched on the iPhone.
Its binary is `17e3b4fda5021ccaf2dbda5b80a63758d79114f42df3c34fe7dc17da657a94df`.
Its tracked iOS source hash matches the retained measured source,
`2e4ba83c4f3f97e3bf3269c15a2636bb1290d041751a5c2c3213a3176b1572a8`.
The only later iOS changes are two audit tests. The exact owner-preferred older
bundle and tag remain available through [the checkpoint](SMOOTH_READER_CHECKPOINT.md).

## What interrupted scrolling

These were useful jobs running at the wrong time, rather than unnecessary
product features:

| Work | Problem observed | Retained repair |
| --- | --- | --- |
| Reading-position persistence | Repeated encoding, durable writes and projection refreshes on the UI thread | Capture the latest position cheaply; save after 500 ms of quiet and on explicit exit/background paths |
| Account state reads | Repeatedly decoding the same stored account state | Reuse decoded state only when owner and freshly fetched durable bytes match; refresh after a successful commit |
| Sync replies and library snapshots | Reconciliation, storage and UI projections overlapping active scrolling | Native scroll-phase gate; process after quiet through the existing ordered writer |
| Bursts of full read snapshots | Replaying every intermediate complete snapshot after quiet | Keep the newest version for each of the two read streams; durable user commands and receipts retain their ordering |
| Geometry/progress tracking | Frequent viewport updates | Bounded tracking preserves semantic anchors; its isolated hitch benefit is unproven |

Combined CPU/frame evidence attributes library/storage work to 16 of 19 early
late-frame windows. The retained matched large-type result is 1.34 ms/s, with
two 12.50 ms hitches, versus the initial 32.89–52.94 range. That is one matched
post-change run, not a whole-app FPS or universal zero-hitch claim. Storage and
projection work no longer overlap its active scrolling or associated late
app-update windows. The stricter below-1-ms/s gate was not achieved.

## What still runs, and what is bounded

- Local position capture and the floating progress display still update as the
  reader moves. Expensive persistence is separate from that display.
- Signed-in Saved/position subscriptions, the durable command queue, ordered
  reconciliation, acknowledgement and retry remain. Retries back off instead
  of spinning continuously. Owner/session/deletion fences remain.
- Page fetching and nearest-volume warming remain. Warming is limited to nearby
  volumes and deduplicated within the loaded outline.
- Translation reads and opt-in generation remain. Visible-hadith identity changes
  schedule a 450 ms settling task; duplicate request guards and quota/auth checks
  remain. AI generation was off for profiling, not removed from the app.
- Translation-publication availability still updates, with at most 40 loaded
  translation references watched and deadline handling retained.
- Reader analytics still record bounded events. A per-frame visibility callback
  does not emit a new reading-success event for every pixel.

Creating `Task {}` does not by itself move work off the UI thread. The current
store and reconciliation still use the main actor after quiet. This is better
scheduling and reuse, not a claim of a complete background-storage architecture.

## Saving and closing

| Situation on iPhone | Current behavior |
| --- | --- |
| Pause scrolling | After 500 ms without active interaction/motion, save the latest semantic position locally and queue account sync if signed in |
| Leave the reader | `onDisappear`, explicit saves and `stop()` flush pending progress through the existing writer |
| App becomes inactive/backgrounded | The scene-phase handler ends active viewport tracking and immediately saves locally |
| No network | Guest data remains local; signed-in progress is a durable pending command and can be retried later |
| Relaunch with a restored account session | RootView starts account synchronization again; pending durable commands are available for replay |
| Force-close after background save completed | The committed local position/queue remain; cloud upload may still be pending |
| Crash, sudden kill or power loss before a flush | Only the last committed checkpoint is guaranteed, not the latest in-memory offset |

The last row is a meaningful limitation. During uninterrupted scrolling, saving
can be deferred for the entire interaction. The change therefore increases the
potential unsaved window compared with periodic saving during scrolling. Normal
exit/background paths preserve the final position, but this does not prove
crash-proof exact-pixel recovery. A later reliability unit should establish a
bounded durable checkpoint using one properly ordered storage writer outside
the scrolling UI path, preserving account fences, ordering and rollback.

Local persistence and cloud upload are separate guarantees. There is no dedicated
background execution assertion for finishing library uploads before suspension.
Do not promise upload completion on Home, force-close or offline exit. Apple
documents that [termination callbacks are not generally guaranteed](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationwillterminate%28_%3A%29)
and [background execution is finite](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationdidenterbackground%28_%3A%29).

## Caching quality and unfinished work

The account decode cache is defensive: one account partition, an 8 MiB serialized
admission bound, fresh durable-byte/owner validation, invalidation on account
change/deletion/corruption and reuse only after successful writes. This avoids
repeated conversion of the same bytes without hiding newer disk data. It does
not cache reader pages or make networking instant.

The reading pipeline remains incomplete for the experience the owner wants:

- With a reachable backend, page/outline loading still normally requests Convex
  first. Verified offline dumps are used on an unreachable/failed/timeout path,
  so a download does not guarantee instant local-first opening while online.
- Adjacent-volume warming discards returned pages and primarily warms the server
  cache. It is not a reusable on-device volume/page cache. Targets are marked
  warmed before success, and the warming task is not stored among the reader's
  explicitly canceled page/translation/publication tasks. Its calls also bypass
  the reader's `timedReaderPage` wrapper; review cancellation/deadlines directly.
- Moving between volumes resets the loaded page surface. Existing local pages
  do not constitute a complete cross-volume transition cache.
- Guest/account and platform lifecycle paths are not identical. Android's close,
  disposal and ViewModel-clear saves remain; no fresh physical Android
  background/force-kill proof was performed in this audit.

These are follow-up findings, not repaired claims. They belong with the ordered
[post-goal sessions](POST_GOAL_BACKLOG.md). Preserve the completed Convex cost
reductions; no backend endpoint, schema, deployment or provider behavior changed
in the scrolling work.

## Evidence and limits

The retained implementation passed 171 focused iOS safety tests and ten reader
UI checks. Eight unchanged-Android parity cases retain their earlier scope.
Two new tests now reopen real on-disk stores and verify exact account queued
progress after a background-style save and guest progress after `stop()`.
Those and two existing lifecycle/account-switch cases freshly pass. See
[the four-test record](smooth-reader-verification/reader-durability-audit.json).

These tests prove the local writer paths, not a live cloud upload, an arbitrary
crash callback or physical VoiceOver acceptance. The original release/language/
accessibility gates remain open. No extra simulator, paid generation, cloud
change or backend rollback was used for this audit.

Terms: the **UI thread** handles touches and drawing; blocking it can delay a
frame. A **hitch** is a late frame. **ms/s** is accumulated hitch time per second
of active scrolling, not FPS. A **cache** reuses already obtained/decoded data.
A **durable queue** is work saved to disk so it can be retried after restart.
