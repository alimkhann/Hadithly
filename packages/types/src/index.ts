export type HadithProviderName = "sunnah_now" | "sunnah_com" | "local_dump";

export type AuthenticityGrade =
  | "sahih"
  | "hasan"
  | "daif"
  | "mawdu"
  | "mixed"
  | "unknown";
export type AuthenticityAppliesTo = "hadith" | "collection" | "none";
export type AuthenticityConfidence =
  | "source_provided"
  | "manual_mapping"
  | "unavailable";

export type Book = {
  collection: string;
  slug: string;
  arabicName?: string;
  hadithCount?: number;
  authenticityGrade?: string;
};

export type CollectionChapter = {
  chapterId: string;
  title: string;
  arabicTitle?: string;
  hadithCount?: number;
  route: {
    collectionSlug: string;
    volumeId?: string;
    chapterId: string;
  };
};

export type CollectionVolume = {
  volumeId: string;
  title: string;
  arabicTitle?: string;
  firstChapterTitle?: string;
  firstChapterArabicTitle?: string;
  hadithCount?: number;
  route: {
    collectionSlug: string;
    volumeId: string;
  };
};

export type CollectionIndex = {
  book: Book;
  volumes: CollectionVolume[];
  chapters: CollectionChapter[];
  indexTrusted: boolean;
  source: HadithProviderName;
  indexedAt?: number;
};

export type Hadith = {
  id: string;
  provider: HadithProviderName;
  providerHadithId: string;
  collectionSlug: string;
  bookId?: string;
  chapterId?: string;
  volumeId?: string;
  arabicText: string;
  englishText?: string;
  narrator?: string;
  referenceDisplay: string;
  collectionName: string;
  bookName?: string;
  chapterName?: string;
  authenticityGrade?: AuthenticityGrade;
  authenticityAppliesTo: AuthenticityAppliesTo;
  authenticitySource?: string;
  authenticityConfidence: AuthenticityConfidence;
  createdAt?: number;
  sourceUpdatedAt?: number;
};

export type Paginated<T> = {
  items: T[];
  page: number;
  pageSize: number;
  hasMore: boolean;
  sourceRoute?: string;
};

export type ListHadithParams = {
  collectionSlug: string;
  page?: number;
  pageSize?: number;
  volumeId?: string;
  chapterId?: string;
};

export type HadithSearchQuery = {
  query: string;
  language?: string;
  collectionSlug?: string;
  limit?: number;
};

export type SearchResult = Hadith & {
  highlight?: string;
};

export type TranslationSource = "official" | "gemini_ai" | "community";
export type TranslationStatus = "live" | "pending" | "archived" | "rejected";

export type Citation = {
  url: string;
  title?: string;
  domain?: string;
};

export type Translation = {
  id: string;
  hadithId: string;
  language: string;
  content: string;
  source: TranslationSource;
  sourceLabel: "Official" | "Gemini AI" | "Community";
  aiModel?: string;
  aiPromptVersion?: string;
  generatedByUserId?: string;
  status: TranslationStatus;
  isDefault: boolean;
  confidence?: number;
  riskFlags?: string[];
  groundingUsed: boolean;
  groundingSourceCount?: number;
  citations?: Citation[];
  sourceReferenceUrl?: string;
  upvotes: number;
  downvotes: number;
  ratingPercent?: number;
  contributorUserId?: string;
  contributorDisplayName?: string;
  createdAt: number;
  updatedAt: number;
  approvedAt?: number;
};
