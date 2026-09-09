import Foundation

/// Source-provided chapter boundaries (R4). A strong typographic header is
/// rendered only when the provider data carries a chapter name; Hadithly
/// never invents one.
enum ReaderChapterBoundaries {
    /// The indices of `hadiths` that open a chapter on this page. A hadith
    /// opens a chapter when its source chapter name is non-empty and differs
    /// from the previous hadith's chapter name (a nil previous name starts a
    /// boundary, so the first named hadith on a page gets its header).
    static func openingIndices(in hadiths: [ReaderHadith]) -> Set<Int> {
        var openings = Set<Int>()
        var previousName: String?
        for (index, hadith) in hadiths.enumerated() {
            let name = hadith.chapterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty && name != previousName {
                openings.insert(index)
            }
            previousName = name.isEmpty ? previousName : name
        }
        return openings
    }
}
