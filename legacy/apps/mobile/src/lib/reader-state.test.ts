import { describe, expect, it } from "vitest";

import {
  buildReaderHref,
  isReaderFeedbackVisible,
  normalizeReaderPage,
  pageProgressPercent,
  readerChromeReducer,
  swipeReaderPage,
} from "./reader-state";

describe("reader state helpers", () => {
  it("normalizes missing and invalid page numbers to the first page", () => {
    expect(normalizeReaderPage(undefined)).toBe(1);
    expect(normalizeReaderPage("0")).toBe(1);
    expect(normalizeReaderPage("-3")).toBe(1);
    expect(normalizeReaderPage("abc")).toBe(1);
    expect(normalizeReaderPage("4")).toBe(4);
  });

  it("builds reader routes with real collection and optional provider metadata only", () => {
    expect(buildReaderHref({ collectionSlug: "muslim", page: 2 })).toBe(
      "/reader/muslim?page=2&pageSize=8",
    );
    expect(
      buildReaderHref({
        collectionSlug: "bukhari",
        page: 3,
        pageSize: 10,
        volumeId: "1",
        chapterId: "2",
        hadithId: "sunnah_now:bukhari:9",
      }),
    ).toBe(
      "/reader/bukhari?page=3&pageSize=10&volumeId=1&chapterId=2&hadithId=sunnah_now%3Abukhari%3A9",
    );
  });

  it("reports progress from loaded pages without pretending to know final totals", () => {
    expect(pageProgressPercent({ page: 1, hasMore: true })).toBe(50);
    expect(pageProgressPercent({ page: 3, hasMore: true })).toBe(75);
    expect(pageProgressPercent({ page: 3, hasMore: false })).toBe(100);
  });

  it("turns pages with left swipe as next and right swipe as previous", () => {
    expect(swipeReaderPage({ page: 2, hasMore: true }, "left")).toBe(3);
    expect(swipeReaderPage({ page: 2, hasMore: true }, "right")).toBe(1);
    expect(swipeReaderPage({ page: 1, hasMore: true }, "right")).toBe(1);
    expect(swipeReaderPage({ page: 2, hasMore: false }, "left")).toBe(2);
  });

  it("keeps reader controls hidden until tapping and hides them while menu is open", () => {
    expect(readerChromeReducer({ chromeVisible: false, menuOpen: false }, "tap")).toEqual({
      chromeVisible: true,
      menuOpen: false,
    });
    expect(readerChromeReducer({ chromeVisible: true, menuOpen: false }, "open-menu")).toEqual({
      chromeVisible: false,
      menuOpen: true,
    });
    expect(readerChromeReducer({ chromeVisible: false, menuOpen: true }, "close-menu")).toEqual({
      chromeVisible: false,
      menuOpen: false,
    });
  });

  it("shows feedback only for AI or community translations", () => {
    expect(isReaderFeedbackVisible("Official")).toBe(false);
    expect(isReaderFeedbackVisible("Gemini AI")).toBe(true);
    expect(isReaderFeedbackVisible("Community")).toBe(true);
  });
});
