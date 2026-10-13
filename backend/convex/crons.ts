import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Daily hadith push notifications. The action itself only sends inside each
// token's configured 15-minute window, so a 15-minute interval is enough.
// Each platform is a no-op until its APNS_* or FCM_* env vars are configured.
crons.interval(
  "dispatch due daily hadith pushes",
  { minutes: 15 },
  internal.actions.daily.sendDueDailyPushes,
  {},
);

crons.interval(
  "expire abandoned evidence",
  { hours: 1 },
  internal.evidence.expireEvidence,
  {},
);

crons.interval(
  "sweep unreferenced file storage",
  { hours: 1 },
  internal.evidence.sweepStorageOrphans,
  {},
);

crons.interval(
  "recover stalled evidence processing",
  { minutes: 5 },
  internal.evidenceProcessing.recoverStalled,
  {},
);

crons.interval("dispatch queued evidence processing", { minutes: 5 }, internal.evidenceProcessing.dispatchPending, {});
crons.interval("dispatch evidence reviews", { minutes: 5 }, internal.evidenceReview.dispatch, {});
crons.interval("resolve evidence cases", { minutes: 5 }, internal.evidenceCases.dispatch, {});
crons.interval("retry transient evidence processing", { minutes: 5 }, internal.evidenceProcessing.retryFailedAutomatically, {});
crons.interval("reassess publication permissions", { minutes: 5 }, internal.evidenceCases.reassessPublished, { paginationOpts: { cursor: null, numItems: 25 } });
crons.interval("retain only permitted evidence facts", { hours: 1 }, internal.evidenceCases.retain, {});

crons.interval("subscription recovery", { hours: 1 }, internal.subscriptions.recoverDeliveries, {});
crons.interval("subscription receipt retention", { hours: 24 }, internal.subscriptions.pruneReceipts, {});
crons.interval("analytics summary retention", { hours: 1 }, internal.analytics.retain, {});
crons.interval("export anonymous analytics totals", { minutes: 5 }, internal.actions.analytics.exportDaily, {});

export default crons;
