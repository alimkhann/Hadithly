export const DEFAULT_READER_PAGE_SIZE = 8;

export type ReaderRouteParams = {
  collectionSlug: string;
  page?: number;
  pageSize?: number;
  volumeId?: string;
  chapterId?: string;
  hadithId?: string;
};

export function normalizeReaderPage(value: string | string[] | number | undefined) {
  const raw = Array.isArray(value) ? value[0] : value;
  const parsed = Number(raw);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
}

export function normalizeReaderPageSize(
  value: string | string[] | number | undefined,
) {
  const raw = Array.isArray(value) ? value[0] : value;
  const parsed = Number(raw);
  return Number.isInteger(parsed) && parsed > 0 && parsed <= 50
    ? parsed
    : DEFAULT_READER_PAGE_SIZE;
}

export function buildReaderHref(params: ReaderRouteParams) {
  const search = new URLSearchParams({
    page: String(params.page ?? 1),
    pageSize: String(params.pageSize ?? DEFAULT_READER_PAGE_SIZE),
  });
  if (params.volumeId) search.set("volumeId", params.volumeId);
  if (params.chapterId) search.set("chapterId", params.chapterId);
  if (params.hadithId) search.set("hadithId", params.hadithId);
  return `/reader/${params.collectionSlug}?${search.toString()}`;
}

export function pageProgressPercent({
  page,
  hasMore,
}: {
  page: number;
  hasMore: boolean;
}) {
  if (!hasMore) return 100;
  return Math.max(1, Math.min(95, Math.round((page / (page + 1)) * 100)));
}

export type ReaderSwipeDirection = "left" | "right";

export function swipeReaderPage(
  state: { page: number; hasMore: boolean },
  direction: ReaderSwipeDirection,
) {
  if (direction === "left") {
    return state.hasMore ? state.page + 1 : state.page;
  }
  return Math.max(1, state.page - 1);
}

export type ReaderChromeState = {
  chromeVisible: boolean;
  menuOpen: boolean;
};

export type ReaderChromeAction = "tap" | "open-menu" | "close-menu";

export function readerChromeReducer(
  state: ReaderChromeState,
  action: ReaderChromeAction,
): ReaderChromeState {
  if (action === "open-menu") {
    return { chromeVisible: false, menuOpen: true };
  }
  if (action === "close-menu") {
    return { chromeVisible: false, menuOpen: false };
  }
  if (state.menuOpen) return state;
  return { ...state, chromeVisible: !state.chromeVisible };
}

export function isReaderFeedbackVisible(
  sourceLabel: "Official" | "Gemini AI" | "Community",
) {
  return sourceLabel !== "Official";
}
