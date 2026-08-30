import SwiftUI

/// Volume index for the current collection, served from the cached outline.
struct CollectionOutlineSheet: View {
    let model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.volumes.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(Theme.textSecondary)
                        Text("Building the index…")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.volumes) { volume in
                                volumeRow(volume)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(model.collectionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func volumeRow(_ volume: OutlineVolume) -> some View {
        let isSelected = volume.volumeId == model.selectedVolumeId
        return Button {
            model.selectVolume(volume.volumeId)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(volume.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                    if let chapter = volume.firstChapterTitle, !chapter.isEmpty {
                        Text(chapter)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("\(volume.hadithCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Theme.accentSoft : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader.volume.\(volume.volumeId)")
    }
}

/// Reader settings: translation language and Arabic type size.
struct ReaderSettingsSheet: View {
    let model: ReaderModel
    @Binding var arabicFontSize: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    languageCard
                    typeSizeCard
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Reader settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Translation language", systemImage: "globe")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("AI translations are labeled and grounded in cited sources.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            ForEach(SupportedLanguages.all) { language in
                Button {
                    model.setLanguage(language.code)
                } label: {
                    HStack {
                        Text(language.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if model.language == language.code {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(model.language == language.code ? Theme.accentSoft : Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reader.language.\(language.code)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var typeSizeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Arabic type size", systemImage: "textformat.size")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                Text("أ")
                    .font(Theme.arabic(15))
                    .foregroundStyle(Theme.textSecondary)
                Slider(
                    value: $arabicFontSize,
                    in: 18...40,
                    step: 1
                ) { }
                    .tint(Theme.accent)
                Text("أ")
                    .font(Theme.arabic(28))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("\(Int(arabicFontSize)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Citations behind an AI translation. Every AI translation is labeled and
/// grounded; this sheet shows where its claims come from.
struct TranslationCitationsSheet: View {
    let translation: ReaderTranslation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(translation.translation)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(5)

                    if let reference = translation.sourceReferenceUrl, let url = URL(string: reference) {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "book")
                                Text(verbatim: reference)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().overlay(Theme.surfaceElevated)

                    if translation.citations.isEmpty {
                        Text("No external sources were cited for this translation.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(Array(translation.citations.enumerated()), id: \.offset) { index, citation in
                            citationRow(index: index + 1, citation: citation)
                        }
                    }

                    Text("This translation was generated by AI (\(translation.aiModel ?? "model unavailable")). It is not an authoritative rendering; verify important meanings against a qualified source.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("AI sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func citationRow(index: Int, citation: ReaderCitation) -> some View {
        Button {
            if let url = URL(string: citation.url) {
                openURL(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.title ?? citation.url)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let domain = citation.domain {
                        Text(domain)
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

/// Contextual contribution flow for the hadith currently on screen. The
/// proposal is reviewed by AI first and is never published without an admin.
struct TranslationSubmissionSheet: View {
    let model: ReaderModel
    let hadith: ReaderHadith
    let existingTranslation: ReaderTranslation?

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var result: TranslationSubmissionResult?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(
        model: ReaderModel,
        hadith: ReaderHadith,
        existingTranslation: ReaderTranslation?,
        initialContent: String
    ) {
        self.model = model
        self.hadith = hadith
        self.existingTranslation = existingTranslation
        _content = State(initialValue: initialContent)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    verdict(result)
                } else if model.canContribute {
                    submissionForm
                } else {
                    signInNotice
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle(result == nil ? "Suggest a translation" : "AI review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var submissionForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hadith.referenceDisplay)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Text("Write the clearest faithful rendering you can. AI checks meaning and terminology; an admin decides whether it is published.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                TextEditor(text: $content)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 230)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("submission.editor")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("submission.error")
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(.black) }
                        Text(isSubmitting ? "Reviewing…" : "Submit for AI review")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? Theme.accent : Theme.surfaceElevated)
                    .foregroundStyle(canSubmit ? .black : Theme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityIdentifier("submission.submit")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { isFocused = content.isEmpty }
    }

    private var signInNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
            Text("Sign in to contribute a translation.")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("You can sign in from Settings, then return to this hadith.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityIdentifier("submission.signInRequired")
    }

    private func verdict(_ submission: TranslationSubmissionResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: verdictIcon(for: submission))
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verdictTitle(for: submission))
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(verdictMessage(for: submission))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                if submission.aiReview.reviewNotes.isEmpty {
                    Text("The review found no specific meaning or terminology issues.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review notes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(Array(submission.aiReview.reviewNotes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                Text("Reviewed by \(submission.aiReview.model). AI review is advisory; only an admin can publish a contribution.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))

                if submission.status == "rejected" {
                    Button("Revise proposal") {
                        result = nil
                        errorMessage = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("submission.revise")
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("submission.verdict")
    }

    private var canSubmit: Bool {
        !isSubmitting && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var languageName: String {
        SupportedLanguages.all.first { $0.code == model.language }?.name ?? model.language
    }

    private func submit() async {
        let proposal = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposal.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            result = try await model.submitTranslation(
                for: hadith,
                proposedContent: proposal,
                replacing: existingTranslation
            )
            isFocused = false
        } catch {
            errorMessage = ReaderModels.errorMessage(of: error)
        }
    }

    private func verdictIcon(for submission: TranslationSubmissionResult) -> String {
        switch submission.status {
        case "rejected": "exclamationmark.triangle"
        case "needs_admin": "person.crop.circle.badge.exclamationmark"
        default: "checkmark.circle"
        }
    }

    private func verdictTitle(for submission: TranslationSubmissionResult) -> String {
        switch submission.status {
        case "rejected": "Please revise this translation"
        case "needs_admin": "Sent for careful admin review"
        default: "AI review passed"
        }
    }

    private func verdictMessage(for submission: TranslationSubmissionResult) -> String {
        switch submission.status {
        case "rejected":
            "The AI review found meaning or terminology concerns, so this version will not be published."
        case "needs_admin":
            "The AI found uncertainty that needs a human decision. Your proposal is waiting for an admin."
        default:
            "Your proposal is waiting for admin approval. It is not public yet."
        }
    }
}

/// Private report path for the currently displayed stored translation.
struct TranslationReportSheet: View {
    let model: ReaderModel
    let translation: ReaderTranslation
    let referenceDisplay: String

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var wasSubmitted = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if wasSubmitted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        Text("Report sent privately")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("An admin can review the translation and your note.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(32)
                    .accessibilityIdentifier("report.confirmation")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(referenceDisplay)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text("Describe a meaning, wording, or attribution concern. Reports are private and are not votes or ratings.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        TextEditor(text: $reason)
                            .focused($isFocused)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 130)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("report.editor")
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Button {
                            Task { await submit() }
                        } label: {
                            Text(isSubmitting ? "Sending…" : "Send private report")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(canSubmit ? Theme.accent : Theme.surfaceElevated)
                                .foregroundStyle(canSubmit ? .black : Theme.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("report.submit")
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Report translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(wasSubmitted ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { isFocused = true }
    }

    private var canSubmit: Bool {
        !isSubmitting && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await model.reportTranslation(translation, reason: trimmed)
            isFocused = false
            wasSubmitted = true
        } catch {
            errorMessage = ReaderModels.errorMessage(of: error)
        }
    }
}
