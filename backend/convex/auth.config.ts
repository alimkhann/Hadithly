import type { AuthConfig } from "convex/server";

// Per the current Clerk ↔ Convex integration: activate the Convex
// integration in the Clerk dashboard, which pre-maps aud="convex" onto
// session tokens. applicationID here must match that audience.
export default {
  providers: [
    {
      domain: process.env.CLERK_FRONTEND_API_URL!,
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
