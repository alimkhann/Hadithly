import {
  getHadithProvider,
  jsonError,
  parsePositiveInt,
} from "@/lib/hadith-provider";
import { cacheHadithPage } from "@/lib/convex-server";

export async function GET(
  request: Request,
  context: { params: Promise<{ slug: string }> },
) {
  try {
    const { slug } = await context.params;
    const url = new URL(request.url);
    const page = parsePositiveInt(url.searchParams.get("page"), 1);
    const pageSize = parsePositiveInt(url.searchParams.get("pageSize"), 50);
    const volumeId = url.searchParams.get("volumeId") ?? undefined;
    const chapterId = url.searchParams.get("chapterId") ?? undefined;
    const result = await getHadithProvider().listHadiths({
      collectionSlug: slug,
      page,
      pageSize,
      volumeId,
      chapterId,
    });
    await cacheHadithPage(result.items);
    return Response.json(result);
  } catch (error) {
    return jsonError(
      error instanceof Error ? error.message : "Failed to list hadiths",
    );
  }
}
