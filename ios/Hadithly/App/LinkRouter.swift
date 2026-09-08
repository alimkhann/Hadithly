import Foundation
import Observation

struct CanonicalHadithLink: Equatable, Identifiable {
    static let host = "hadithly.app"
    static let pathPrefix = "/hadith/"

    let collectionSlug: String
    let providerHadithId: String

    var id: String { "\(collectionSlug)/\(providerHadithId)" }

    /// Display name from the seven-collection catalog; falls back to the
    /// slug when the backend adds a collection the catalog does not know.
    var collectionName: String {
        ReaderModels.collections.first { $0.slug == collectionSlug }?.name
            ?? collectionSlug
    }

    static func parse(_ url: URL) -> CanonicalHadithLink? {
        guard url.scheme == "https", url.host == host,
              let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              !encodedPath.contains("%")
        else { return nil }
        var path = encodedPath
        if path.hasSuffix("/") { path.removeLast() }
        guard !path.hasSuffix("/") else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0].isEmpty,
              components[1] == "hadith"
        else { return nil }
        return parse(collectionSlug: String(components[2]), providerHadithId: String(components[3]))
    }

    static func parse(collectionSlug: String, providerHadithId: String) -> CanonicalHadithLink? {
        guard (try? COLLECTION_SLUG_PATTERN.wholeMatch(in: collectionSlug)) != nil,
            (try? PROVIDER_HADITH_ID_PATTERN.wholeMatch(in: providerHadithId)) != nil
        else { return nil }
        return CanonicalHadithLink(
            collectionSlug: collectionSlug,
            providerHadithId: providerHadithId
        )
    }

    private static let COLLECTION_SLUG_PATTERN = /^[a-z][a-z0-9-]{1,31}$/
    private static let PROVIDER_HADITH_ID_PATTERN = /^[1-9][0-9]{0,11}(\.[0-9]{1,12})*$/
}

/// Routes inbound Universal Links into the reader. Malformed or foreign
/// links are ignored silently — a bad link never displaces what the user
/// was doing. A well-formed link waits here until the tab view appears,
/// so a link opened before onboarding completes still lands in the reader.
@MainActor
@Observable
final class LinkRouter {
    private(set) var pendingLink: CanonicalHadithLink?

    /// Handles an inbound URL. Returns whether it was a canonical link so
    /// debug surfaces can distinguish "ignored" from "queued".
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let link = CanonicalHadithLink.parse(url) else {
            return false
        }
        pendingLink = link
        return true
    }

    func consumePending() -> CanonicalHadithLink? {
        let link = pendingLink
        pendingLink = nil
        return link
    }
}
