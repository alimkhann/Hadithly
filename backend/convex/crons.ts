import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Monthly AI quota reset. Runs at 00:00 UTC on day 1 of every month.
crons.monthly(
  "reset monthly AI generation usage",
  { minuteUTC: 0, hourUTC: 0, day: 1 },
  internal.quotas.resetMonthlyAiUsage,
);

// Daily hadith push notifications. The action itself only sends inside each
// token's configured 15-minute window, so a 15-minute interval is enough.
// Each platform is a no-op until its APNS_* or FCM_* env vars are configured.
crons.interval(
  "dispatch due daily hadith pushes",
  { minutes: 15 },
  internal.actions.daily.sendDueDailyPushes,
);

export default crons;
