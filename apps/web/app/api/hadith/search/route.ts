import {
  getHadithProvider,
  jsonError,
  parsePositiveInt,
} from "@/lib/hadith-provider";
import { searchCachedHadiths } from "@/lib/convex-server";

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const query = url.searchParams.get("q")?.trim();
    if (!query) {
      return jsonError("Missing q query parameter", 400);
    }

    const searchArgs = {
      query,
      language: url.searchParams.get("language") ?? undefined,
      collectionSlug: url.searchParams.get("collectionSlug") ?? undefined,
      limit: parsePositiveInt(url.searchParams.get("limit"), 20),
    };

    const cachedResults = await searchCachedHadiths(searchArgs);
    const results =
      cachedResults.length > 0
        ? cachedResults
        : await getHadithProvider().search(searchArgs);
    return Response.json(results);
  } catch (error) {
    return jsonError(
      error instanceof Error ? error.message : "Failed to search hadiths",
    );
  }
}
