import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// Monthly AI quota reset. Runs at 00:00 UTC on day 1 of every month.
crons.monthly(
  "reset monthly AI generation usage",
  { minuteUTC: 0, hourUTC: 0, day: 1 },
  internal.quotas.resetMonthlyAiUsage,
);

// Daily hadith push notifications land in Phase 3, once APNs/FCM
// registration is implemented in the clients.

export default crons;
