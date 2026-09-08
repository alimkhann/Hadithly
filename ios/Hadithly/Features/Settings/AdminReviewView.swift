import Combine
import ConvexMobile
import Foundation
import Observation
import SwiftUI

private struct AdminSubmissionHadith: Decodable, Sendable {
    let referenceDisplay: String
    let arabicText: String
    let englishText: String?
}

private struct AdminSubmissionContributor: Decodable, Sendable {
    let displayName: String?
    let email: String?
}

private struct AdminTranslationSubmission: Decodable, Identifiable, Sendable {
    let _id: String
    let language: String
    let proposedContent: String
    let aiReview: TranslationAIReview
    let status: String
    let createdAt: Double
    let hadith: AdminSubmissionHadith?
    let contributor: AdminSubmissionContributor?

    var id: String { _id }
}

@MainActor
@Observable
private final class AdminReviewModel {
    private(set) var submissions: [AdminTranslationSubmission] = []
    private(set) var isLoading = true
    private(set) var approvingIds: Set<String> = []
    private(set) var errorMessage: String?

    private let convex: ConvexClientWithAuth<String>
    private var subscription: AnyCancellable?

    init(convex: ConvexClientWithAuth<String>) {
        self.convex = convex
    }

    func start() {
        guard subscription == nil else { return }
        subscription = convex
            .subscribe(
                to: "community:listPendingSubmissions",
                yielding: [AdminTranslationSubmission].self
            )
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = ReaderModels.errorMessage(of: error)
                    }
                },
                receiveValue: { [weak self] submissions in
                    self?.submissions = submissions
                    self?.isLoading = false
                    self?.errorMessage = nil
                }
            )
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    func approve(_ submission: AdminTranslationSubmission) async {
        guard !approvingIds.contains(submission.id) else { return }
        approvingIds.insert(submission.id)
        errorMessage = nil
        defer { approvingIds.remove(submission.id) }
        do {
            try await convex.mutation(
                "community:approveSubmission",
                with: ["submissionId": submission.id as ConvexEncodable?]
            )
        } catch {
            errorMessage = ReaderModels.errorMessage(of: error)
        }
    }
}

/// Minimal, server-authorized approval queue. It deliberately exposes no
/// voting, ranking, reputation, or public contribution statistics.
struct AdminReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var model: AdminReviewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().tint(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Translation review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if model == nil {
                let reviewModel = AdminReviewModel(convex: environment.convex)
                model = reviewModel
                reviewModel.start()
            }
        }
        .onDisappear { model?.stop() }
    }

    @ViewBuilder
    private func content(_ model: AdminReviewModel) -> some View {
        if model.isLoading {
            ProgressView().tint(Theme.textSecondary)
        } else if model.submissions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text("No translations are waiting")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .accessibilityIdentifier("admin.empty")
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(model.submissions) { submission in
                        submissionCard(submission, model: model)
                    }
                }
                .padding(16)
            }
        }
    }

    private func submissionCard(
        _ submission: AdminTranslationSubmission,
        model: AdminReviewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(submission.hadith?.referenceDisplay ?? "Hadith unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(languageName(submission.language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(submission.status == "needs_admin" ? "Careful review" : "AI passed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            Text(submission.proposedContent)
                .font(.body)
                .foregroundStyle(Theme.textPrimary.opacity(0.92))
                .lineSpacing(5)

            if !submission.aiReview.reviewNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(submission.aiReview.reviewNotes.enumerated()), id: \.offset) { _, note in
                        Text("• \(note)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Button {
                Task { await model.approve(submission) }
            } label: {
                HStack(spacing: 8) {
                    if model.approvingIds.contains(submission.id) {
                        ProgressView().tint(.black)
                    }
                    Text("Approve and publish")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accent)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(model.approvingIds.contains(submission.id))
            .accessibilityIdentifier("admin.approve.\(submission.id)")
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func languageName(_ code: String) -> String {
        SupportedLanguages.all.first { $0.code == code }?.name ?? code
    }
}
