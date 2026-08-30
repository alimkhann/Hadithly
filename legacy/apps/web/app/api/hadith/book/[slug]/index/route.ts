import { getHadithProvider, jsonError } from "@/lib/hadith-provider";

const indexCache = new Map<string, { expiresAt: number; value: unknown }>();
const INDEX_TTL_MS = 1000 * 60 * 60 * 12;

export async function GET(
  _request: Request,
  context: { params: Promise<{ slug: string }> },
) {
  try {
    const { slug } = await context.params;
    const cached = indexCache.get(slug);
    if (cached && cached.expiresAt > Date.now()) {
      return Response.json(cached.value);
    }
    const index = await getHadithProvider().getCollectionIndex(slug);
    indexCache.set(slug, {
      expiresAt: Date.now() + INDEX_TTL_MS,
      value: index,
    });
    return Response.json(index);
  } catch (error) {
    return jsonError(
      error instanceof Error
        ? error.message
        : "Failed to load collection index",
    );
  }
}
