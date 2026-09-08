import { createInternalHadithId } from "@hadithly/hadith-provider";

import { findCachedHadithByInternalId } from "@/lib/convex-server";
import { jsonError } from "@/lib/hadith-provider";

export async function GET(
  _request: Request,
  context: { params: Promise<{ slug: string; id: string }> },
) {
  try {
    const { slug, id } = await context.params;
    const hadith = await findCachedHadithByInternalId(
      createInternalHadithId("sunnah_now", slug, id),
    );
    if (!hadith) {
      return jsonError(
        "Direct Sunnah.now hadith reads are disabled; load a paginated reader page first",
        404,
      );
    }
    return Response.json(hadith);
  } catch (error) {
    return jsonError(
      error instanceof Error ? error.message : "Failed to load hadith",
    );
  }
}
