import { getHadithProvider, jsonError } from "@/lib/hadith-provider";

export async function GET() {
  try {
    const books = await getHadithProvider().listBooks();
    return Response.json(books);
  } catch (error) {
    return jsonError(error instanceof Error ? error.message : "Failed to list books");
  }
}
