import { getHadithProvider, jsonError } from "@/lib/hadith-provider";

export async function GET(_request: Request, context: { params: Promise<{ slug: string }> }) {
  try {
    const { slug } = await context.params;
    const book = await getHadithProvider().getBook(slug);
    return Response.json(book);
  } catch (error) {
    return jsonError(error instanceof Error ? error.message : "Failed to load book");
  }
}
