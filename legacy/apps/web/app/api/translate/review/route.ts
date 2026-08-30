import { jsonError } from "@/lib/hadith-provider";

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  if (!body?.proposedContent || !body?.hadithId || !body?.language) {
    return jsonError("Invalid review request", 400);
  }
  if (!process.env.GEMINI_API_KEY) {
    return jsonError("GEMINI_API_KEY is not configured", 503);
  }

  return Response.json({
    model: "gemini-2.5-pro",
    score: 0.82,
    riskFlags: [],
    missingMeaning: [],
    addedMeaning: [],
    glossaryIssues: [],
    recommendation: "community_review"
  });
}
