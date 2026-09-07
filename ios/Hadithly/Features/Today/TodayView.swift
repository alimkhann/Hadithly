import ClerkKit
import ConvexMobile
import SwiftUI

/// Wire shape of actions/daily:getDailyHadith.
struct DailyHadith: Decodable, Identifiable, Equatable {
    let _id: String
    let provider: String
    let canonicalId: String
    let providerHadithId: String
    let collectionSlug: String
    let collectionName: String
    let volumeId: String?
    let arabicText: String
    let englishText: String?
    let referenceDisplay: String
    let authenticity: ReaderAuthenticity

    var id: String { _id }
}

/// What drives the reader cover from outside the Library tab: a collection
/// plus an optional landing position inside it.
struct ReaderOpenTarget: Identifiable, Equatable {
    let slug: String
    let name: String
    var volumeId: String?
    var hadithNumber: String?

    var id: String { "\(slug)-\(volumeId ?? "-")-\(hadithNumber ?? "-")" }
}

/// Today: the same daily hadith for every reader that day, plus the private
/// continue-reading card. Quiet, one column, nothing to compete over.
struct TodayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @Environment(UserLibraryModel.self) private var library

    @State private var dailyHadith: DailyHadith?
    @State private var isLoadingDaily = false
    @State private var loadFailed = false
    @State private var openTarget: ReaderOpenTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                dailyCard

                if let _ = library.continueReading {
                    continueReadingCard
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .task {
            library.refresh()
            await loadDailyHadith()
        }
        .refreshable {
            await loadDailyHadith()
        }
        .fullScreenCover(item: $openTarget) { target in
            ReaderView(
                collectionSlug: target.slug,
                collectionName: target.name,
                openVolumeId: target.volumeId,
                openHadithNumber: target.hadithNumber
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("As-salamu alaykum")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(dailyHeading)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, 6)
    }

    private var dailyHeading: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date.now)
    }

    // MARK: - Daily hadith

    @ViewBuilder
    private var dailyCard: some View {
        if let hadith = dailyHadith {
            Button {
                openTarget = ReaderOpenTarget(
                    slug: hadith.collectionSlug,
                    name: hadith.collectionName,
                    volumeId: hadith.volumeId,
                    hadithNumber: hadith.providerHadithId
                )
            } label: {
                DailyHadithCard(hadith: hadith)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.dailyCard")
        } else if isLoadingDaily {
            cardShell {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.textSecondary)
                    Text("Bringing today's hadith…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if loadFailed {
            cardShell {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's hadith could not load")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Pull down to try again.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else {
            emptyDailyCard
        }
    }

    private func dailyCardBody(_ hadith: DailyHadith) -> some View {
        DailyHadithCard(hadith: hadith)
    }

    private var emptyDailyCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 8) {
                Text("No hadith cached yet")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Open a collection in the Library and today's hadith will appear here.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Continue reading

    private var continueReadingCard: some View {
        Group {
            if let entry = library.continueReading, let hadith = entry.hadith {
                Button {
                    openTarget = ReaderOpenTarget(
                        slug: entry.collectionSlug,
                        name: hadith.collectionName,
                        volumeId: hadith.volumeId,
                        hadithNumber: hadith.hadithNumber
                    )
                } label: {
                    cardShell {
                        HStack(spacing: 14) {
                            Image(systemName: "book")
                                .font(.body)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 38, height: 38)
                                .background(Theme.accentSoft)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Continue reading")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .textCase(.uppercase)
                                Text(hadith.collectionName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                if !hadith.referenceDisplay.isEmpty {
                                    Text(hadith.referenceDisplay)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.continueCard")
            }
        }
    }

    private func cardShell<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Loading

    private func loadDailyHadith() async {
        isLoadingDaily = true
        defer { isLoadingDaily = false }
        do {
            let result: DailyHadith? = try await environment.convex.action(
                "actions/daily:getDailyHadith",
                with: ["timezone": TimeZone.current.identifier]
            )
            withAnimation(.easeOut(duration: 0.2)) {
                dailyHadith = result
                loadFailed = false
            }
        } catch {
            loadFailed = true
        }
    }
}

/// The daily hadith card body, shared with the loading/empty shells above.
private struct DailyHadithCard: View {
    let hadith: DailyHadith

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hadith of the day")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .textCase(.uppercase)

            Text(hadith.arabicText)
                .font(Theme.arabic(22))
                .lineSpacing(22 * 0.75)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let english = hadith.englishText, !english.isEmpty {
                Text(english)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(hadith.referenceDisplay)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            Text(hadith.authenticity.displayLabel)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("today.authenticity")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
