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
