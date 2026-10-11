import ClerkKit
import ConvexMobile
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

struct EvidenceProcessingStatusView: View {
    @Environment(\.readerPalette) private var palette
    let status: String
    let retryItems: [String]
    let errorMessage: String?
    let onRetry: (String) -> Void
    let onWithdraw: () -> Void
    var citations: [EvidenceCitation] = []
    var appeal: EvidenceAppealState? = nil
    var onAppeal: (String) -> Void = { _ in }

    var body: some View {
        ScrollView {
        VStack(spacing: 12) {
            if status == "awaiting_processing" {
                ProgressView().accessibilityLabel("Processing evidence").accessibilityIdentifier("submission.processing")
                Text("Evidence received; awaiting checks.").font(.headline).accessibilityIdentifier("submission.confirmation")
                Text("Processing evidence. Your suggestion stays private and has not been reviewed or published.")
                    .font(.subheadline).foregroundStyle(palette.textSecondary)
            } else if ["under_review", "approved", "held", "rejected", "review_unavailable", "revoked"].contains(status) {
                Text(reviewTitle).font(.headline).accessibilityIdentifier("submission.\(status)")
                Text(reviewMessage).font(.subheadline).foregroundStyle(palette.textSecondary)
                if status == "under_review" { ProgressView().accessibilityLabel("e3.reviewing") }
            } else if status == "evidence_ready" {
                Image(systemName: "checkmark.circle").font(.largeTitle)
                Text("Evidence checks complete").font(.headline).accessibilityIdentifier("submission.ready")
                Text("e3.waiting")
                    .font(.subheadline).foregroundStyle(palette.textSecondary)
            } else {
                Image(systemName: "exclamationmark.circle").font(.largeTitle)
                Text(status == "infected" ? "Evidence cannot be used" : "Evidence processing failed")
                    .font(.headline).accessibilityIdentifier(status == "infected" ? "submission.infected" : "submission.failed")
                Text("Your suggestion remains private. Withdraw it and submit different evidence if needed.")
                    .font(.subheadline).foregroundStyle(palette.textSecondary)
            }
            if ["awaiting_processing", "processing_failed"].contains(status) {
                ForEach(retryItems, id: \.self) { itemId in
                    Button { onRetry(itemId) } label: {
                        Text("Retry evidence").frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("submission.retryProcessing")
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(palette.textSecondary).accessibilityIdentifier("submission.error") }
            EvidenceAppealContent(appeal: appeal, onAppeal: onAppeal)
            if !citations.isEmpty {
                Text("e3.sources").font(.headline)
                ForEach(Array(citations.enumerated()), id: \.offset) { index, citation in
                    if let url = EvidenceClientPolicy.httpsURL(citation.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(citation.title).multilineTextAlignment(.leading)
                                Text(citation.location).font(.caption).foregroundStyle(palette.textSecondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.accessibilityIdentifier("submission.citation.\(index)")
                    }
                }
            }
            if status != "approved" {
            Button(role: .destructive, action: onWithdraw) {
                Text("Withdraw suggestion").frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("submission.deleteDraft")
            }
        }
        .foregroundStyle(palette.textPrimary).frame(maxWidth: .infinity).padding(30)
        }
    }

    private var reviewTitle: LocalizedStringKey {
        switch status {
        case "under_review": "e3.reviewing"
        case "approved": "e3.published"
        case "held": "e3.exception"
        case "rejected": "e3.rejected"
        case "revoked": "e4.revoked"
        default: "e3.unavailable"
        }
    }
    private var reviewMessage: LocalizedStringKey {
        switch status {
        case "under_review": "e3.reviewing_message"
        case "approved": "e3.published_message"
        case "held": "e3.exception_message"
        case "rejected": "e3.rejected_message"
        case "revoked": "e4.revoked_message"
        default: "e3.unavailable_message"
        }
    }
}

struct EvidenceAppealState: Decodable {
    let available: Bool
    let deadline: Double?
    let status: String
    var canRequest: Bool { available && status == "not_requested" && (deadline ?? 0) > Date().timeIntervalSince1970 * 1000 }
}

struct EvidenceAppealContent: View {
    let appeal: EvidenceAppealState?
    let onAppeal: (String) -> Void
    @State private var reason = ""
    var body: some View {
        if let appeal {
            if appeal.canRequest {
                Text("e4.appeal_window").font(.caption)
                TextField("e4.appeal_reason", text: $reason, axis: .vertical)
                    .lineLimit(3...8).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("submission.appealReason")
                Button { onAppeal(reason) } label: { Text("e4.appeal").frame(minHeight: 44) }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 || reason.count > 2000)
                    .accessibilityIdentifier("submission.appeal")
            } else if appeal.status != "not_requested" {
                Text(appeal.status == "processing" ? "e4.appeal_processing" : "e4.appeal_resolved")
                    .font(.subheadline).accessibilityIdentifier("submission.appealStatus")
            }
        }
    }
}

struct EvidenceCitation: Decodable {
    let url: String
    let title: String
    let location: String
}

#if DEBUG
struct EvidenceProcessingFixture: View {
    @State private var status = "awaiting_processing"
    @State private var showCommunitySources = false
    private var communityTranslation: ReaderTranslation {
        ReaderTranslation(translationId: "fixture", translation: "This is a test text.", confidence: nil, riskFlags: [], glossaryNotes: [], source: "community", sourceLabel: "Community", aiModel: nil, groundingUsed: false, citations: [ReaderCitation(url: "https://example.org/fixture", title: "Licensed source", domain: "example.org")], sourceReferenceUrl: "https://example.org/fixture", cached: true)
    }

    var body: some View {
        VStack {
            ForEach(["awaiting_processing", "processing_failed", "infected", "evidence_ready", "under_review", "approved", "held", "rejected", "review_unavailable", "revoked"], id: \.self) { state in
                Button(state) { status = state }.accessibilityIdentifier("e2.fixture.\(state)")
            }
            EvidenceProcessingStatusView(status: status, retryItems: ["test-item"], errorMessage: nil,
                onRetry: { _ in status = "awaiting_processing" }, onWithdraw: {},
                citations: [EvidenceCitation(url: "https://example.org/fixture", title: "Licensed source", location: "p. 1")],
                appeal: ["held", "rejected", "review_unavailable"].contains(status) ? EvidenceAppealState(available: true, deadline: Date().timeIntervalSince1970 * 1000 + 600_000, status: "not_requested") : nil,
                onAppeal: { _ in status = "under_review" })
            ReaderStoredTranslationView(text: "This is a test text.", translation: communityTranslation, palette: .dark) {
                showCommunitySources = true
            }
        }.background(ReaderPalette.dark.background).environment(\.readerPalette, .dark)
        .sheet(isPresented: $showCommunitySources) {
            TranslationCitationsSheet(translation: communityTranslation)
        }
    }
}
#endif

private struct EvidenceDraftView: Decodable {
    struct Item: Decodable, Identifiable {
        let itemId: String
        let clientItemKey: String
        let kind: String
        let state: String
        let retryable: Bool?
        let url: String?
        let displayName: String?
        let declaredMime: String?
        var id: String { itemId }
    }
    let submissionId: String
    let status: String
    let proposedContent: String
    let items: [Item]
    let citations: [EvidenceCitation]?
    let appeal: EvidenceAppealState?
}

private struct EvidenceSubmitResult: Decodable { let status: String }
private struct LegacyEvidenceProposal: Decodable { let submissionId: String; let proposedContent: String }

private struct EvidenceChoice: Identifiable, Codable, Equatable {
    let id: String
    let kind: String
    let label: String
    let url: URL?
    let fileURL: URL?
    let mime: String?
    let size: Int?
    let sha256: String?
}

private struct LocalEvidenceDraft: Codable {
    let submissionId: String?
    let draftKey: String
    let proposedContent: String
    let urlInput: String
    let choices: [EvidenceChoice]
    let legacySubmissionId: String?
    let createdAt: Double
}

enum EvidenceLocalDrafts {
    static func clear(for accountId: String) {
        let prefix = "evidence.draft.\(accountId)."
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "EvidenceDrafts", directoryHint: .isDirectory).standardizedFileURL
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(prefix) {
            if let data = value as? Data, let draft = try? JSONDecoder().decode(LocalEvidenceDraft.self, from: data) {
                for choice in draft.choices {
                    guard let file = choice.fileURL?.standardizedFileURL,
                          file.deletingLastPathComponent() == directory else { continue }
                    try? FileManager.default.removeItem(at: file)
                }
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

enum EvidenceClientPolicy {
    static let maxFileBytes = 10_000_000

    static func acceptsFileSize(_ size: Int) -> Bool { (1...maxFileBytes).contains(size) }

    static func httpsURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

private final class EvidenceUploadProgress: NSObject, URLSessionTaskDelegate {
    let report: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

/// Private evidence intake and coarse E2 processing status.
struct TranslationSubmissionSheet: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let model: ReaderModel
    let hadith: ReaderHadith
    let existingTranslation: ReaderTranslation?
    let initialContent: String

    @State private var content: String
    @State private var urlText = ""
    @State private var evidence: [EvidenceChoice] = []
    @State private var draft: EvidenceDraftView?
    @State private var draftKey = UUID().uuidString
    @State private var localCreatedAt = Date().timeIntervalSince1970 * 1_000
    @State private var legacySubmissionId: String?
    @State private var isPickingFile = false
    @State private var replacingItemKey: String?
    @State private var isSubmitting = false
    @State private var progress = 0.0
    @State private var errorMessage: String?
    @State private var activeUpload: Task<Void, Never>?
    @State private var localReady = false

    init(model: ReaderModel, hadith: ReaderHadith, existingTranslation: ReaderTranslation?, initialContent: String) {
        self.model = model
        self.hadith = hadith
        self.existingTranslation = existingTranslation
        self.initialContent = initialContent
        _content = State(initialValue: initialContent)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !model.canContribute || Clerk.shared.user == nil {
                    Text("Sign in from Settings to suggest a translation with evidence.")
                        .foregroundStyle(palette.textSecondary)
                        .padding(28)
                        .accessibilityIdentifier("submission.signInRequired")
                } else if draft?.status == "expired" {
                    VStack(spacing: 12) {
                        Text("Evidence expired").font(.headline)
                            .accessibilityIdentifier("submission.expired")
                        Text("The private files were removed before processing. You can start a new suggestion.")
                            .font(.subheadline).foregroundStyle(palette.textSecondary)
                        Button("Start a new suggestion") { Task { await deleteDraft() } }
                            .frame(minHeight: 44)
                    }
                    .padding(30)
                } else if let draft, ["awaiting_processing", "evidence_ready", "processing_failed", "infected", "under_review", "approved", "held", "rejected", "review_unavailable", "revoked"].contains(draft.status) {
                    processingStatus(draft)
                } else {
                    form
                }
            }
            .background(palette.background)
            .navigationTitle("Suggest a translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { activeUpload?.cancel(); dismiss() }
                }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.jpeg, .png, .webP, .pdf], allowsMultipleSelection: true, onCompletion: receiveFiles)
            .task(id: ownerLanguageKey) {
                activeUpload?.cancel()
                activeUpload = nil
                isSubmitting = false
                progress = 0
                errorMessage = nil
                localReady = false
                draft = nil
                evidence = []
                content = initialContent
                urlText = ""
                legacySubmissionId = nil
                draftKey = UUID().uuidString
                localCreatedAt = Date().timeIntervalSince1970 * 1_000
                let restored = await restoreDraft()
                guard !Task.isCancelled else { return }
                if !restored { await loadLegacyProposal() }
                guard !Task.isCancelled else { return }
                localReady = true
                persistLocal()
            }
            .onChange(of: content) { _, _ in persistLocal() }
            .onChange(of: urlText) { _, _ in persistLocal() }
            .onChange(of: evidence) { _, _ in persistLocal() }
            .onChange(of: ownerLanguageKey) { _, _ in activeUpload?.cancel() }
            .onDisappear { activeUpload?.cancel() }
            .task(id: draft?.submissionId) {
                guard let submissionId = draft?.submissionId else { return }
                await observeProcessing(submissionId, owner: ownerLanguageKey)
            }
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(hadith.referenceDisplay).font(.headline)
            Text("Add one to three public source links or files. Evidence stays private while checked.")
                .font(.caption).foregroundStyle(palette.textSecondary)
            TextEditor(text: $content)
                .frame(minHeight: 170)
                .padding(8)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(!localReady)
                .accessibilityLabel("Proposed translation")
                .accessibilityIdentifier("submission.editor")

            HStack {
                TextField("https://source.example/page", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .frame(minHeight: 44)
                    .disabled(!localReady)
                    .accessibilityIdentifier("submission.evidence.url")
                Button("Add link") { addURL() }
                    .frame(minHeight: 44)
                    .disabled(!localReady || evidence.count >= 3)
            }
            Button("Add image or PDF") { isPickingFile = true }
                .frame(minHeight: 44)
                .disabled(!localReady || evidence.count >= 3 || draft != nil)
                .accessibilityIdentifier("submission.evidence.file")

            ForEach(evidence) { item in
                HStack {
                    Image(systemName: item.kind == "url" ? "link" : "doc")
                    Text(item.label).lineLimit(2)
                    Spacer()
                    if draft == nil {
                        Button("Remove") { remove(item) }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Remove \(item.label)")
                    }
                }
                .font(.subheadline)
                .padding(12)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let draft {
                ForEach(draft.items) { item in
                    HStack {
                        Text("\(item.displayName ?? item.url ?? "Evidence"): \(item.state.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                        if item.kind == "file" && item.state != "quarantined_unscanned" && evidence.first(where: { $0.id == item.clientItemKey })?.fileURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) != false {
                            Button("Select again") {
                                replacingItemKey = item.clientItemKey
                                isPickingFile = true
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
            if isSubmitting {
                ProgressView(value: progress)
                    .accessibilityLabel("Evidence upload progress")
                    .accessibilityValue(Text("\(Int(progress * 100)) percent"))
                    .accessibilityIdentifier("submission.uploadProgress")
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("submission.error")
            }
            if isSubmitting {
                Button("Cancel upload") { activeUpload?.cancel() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("submission.cancelUpload")
            }
            if draft != nil && !isSubmitting {
                Button("Delete draft") { Task { await deleteDraft() } }
                    .frame(minHeight: 44)
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("submission.deleteDraft")
            }
            Button(draft == nil ? "Submit with evidence" : "Retry evidence upload") {
                activeUpload = Task { await submit() }
            }
            .frame(minHeight: 44)
            .disabled(!localReady || isSubmitting || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft == nil && evidence.isEmpty))
            .accessibilityIdentifier("submission.submit")
            Text("e3.consent").font(.caption).foregroundStyle(palette.textSecondary)
        }
        .foregroundStyle(palette.textPrimary)
        .padding(20)
    }

    private func processingStatus(_ draft: EvidenceDraftView) -> some View {
        EvidenceProcessingStatusView(status: draft.status,
            retryItems: draft.items.filter { $0.state == "failed" && $0.retryable == true }.map(\.itemId),
            errorMessage: errorMessage,
            onRetry: { itemId in Task { await retryProcessing(itemId, submissionId: draft.submissionId) } },
            onWithdraw: { Task { await deleteDraft() } }, citations: draft.citations ?? [],
            appeal: draft.appeal, onAppeal: { reason in Task { await requestAppeal(reason, submissionId: draft.submissionId) } })
    }

    private func requestAppeal(_ reason: String, submissionId: String) async {
        do {
            let _: EvidenceSubmitResult = try await environment.convex.mutation("evidenceCases:requestAppeal", with: ["submissionId": submissionId as ConvexEncodable?, "reason": reason as ConvexEncodable?])
            draft = try await fetchDraft(submissionId)
            errorMessage = nil
        } catch { errorMessage = String(localized: "e4.appeal_error") }
    }

    private func observeProcessing(_ submissionId: String, owner: String) async {
        let stream = environment.convex.subscribe(
            to: "evidence:getOwnEvidenceDraft",
            with: ["submissionId": submissionId as ConvexEncodable?],
            yielding: EvidenceDraftView.self
        )
        do {
            for try await remote in stream.values {
                guard !Task.isCancelled, ownerLanguageKey == owner else { return }
                draft = remote
                if remote.status != "draft" {
                    for choice in evidence { if let file = choice.fileURL { try? FileManager.default.removeItem(at: file) } }
                    evidence = []
                    content = remote.proposedContent
                    urlText = ""
                    persistLocal()
                }
            }
        } catch {
            if !Task.isCancelled && ownerLanguageKey == owner { errorMessage = "Evidence status is unavailable. Try again when connected." }
        }
    }

    private func retryProcessing(_ itemId: String, submissionId: String) async {
        do {
            let _: Bool = try await environment.convex.mutation("evidenceProcessing:retryOwnEvidenceProcessing", with: [
                "submissionId": submissionId as ConvexEncodable?, "itemId": itemId as ConvexEncodable?
            ])
            errorMessage = nil
        } catch {
            errorMessage = "Evidence could not be retried right now."
        }
    }

    private var ownerLanguageKey: String { "\(Clerk.shared.user?.id ?? "guest").\(model.language)" }
    private var localKey: String { "evidence.draft.\(ownerLanguageKey).\(hadith.internalId)" }

    private func addURL() {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard evidence.count < 3, let url = EvidenceClientPolicy.httpsURL(raw) else {
            errorMessage = "Enter an HTTPS source link without a username or password."
            return
        }
        evidence.append(EvidenceChoice(id: UUID().uuidString, kind: "url", label: url.host ?? raw, url: url, fileURL: nil, mime: nil, size: nil, sha256: nil))
        urlText = ""
        errorMessage = nil
    }

    private func receiveFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard (replacingItemKey != nil && urls.count == 1) || (replacingItemKey == nil && evidence.count + urls.count <= 3) else { throw NSError(domain: "Evidence", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose no more than three evidence items."]) }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "EvidenceDrafts", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                guard EvidenceClientPolicy.acceptsFileSize(bytes) else { throw NSError(domain: "Evidence", code: 2, userInfo: [NSLocalizedDescriptionKey: "Each file must be 10 MB or smaller."]) }
                let mime: String
                switch url.pathExtension.lowercased() {
                case "jpg", "jpeg": mime = "image/jpeg"
                case "png": mime = "image/png"
                case "webp": mime = "image/webp"
                case "pdf": mime = "application/pdf"
                default: throw NSError(domain: "Evidence", code: 3, userInfo: [NSLocalizedDescriptionKey: "Choose a JPEG, PNG, WebP, or PDF."])
                }
                let id = replacingItemKey ?? UUID().uuidString
                let oldCopy = evidence.first(where: { $0.id == id })?.fileURL
                let copy = directory.appending(path: "\(UUID().uuidString).\(url.pathExtension.lowercased())")
                let hash: String
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: copy.path)
                    hash = SHA256.hash(data: try Data(contentsOf: copy)).map { String(format: "%02x", $0) }.joined()
                } catch {
                    try? FileManager.default.removeItem(at: copy)
                    throw error
                }
                if let oldCopy { try? FileManager.default.removeItem(at: oldCopy) }
                evidence.removeAll { $0.id == id }
                evidence.append(EvidenceChoice(id: id, kind: "file", label: url.lastPathComponent, url: nil, fileURL: copy, mime: mime, size: bytes, sha256: hash))
            }
            replacingItemKey = nil
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ item: EvidenceChoice) {
        if let file = item.fileURL { try? FileManager.default.removeItem(at: file) }
        evidence.removeAll { $0.id == item.id }
    }

    private func persistLocal() {
        guard model.canContribute, Clerk.shared.user != nil, localReady else { return }
        if draft == nil && content.isEmpty && evidence.isEmpty && urlText.isEmpty {
            UserDefaults.standard.removeObject(forKey: localKey)
            return
        }
        let local = LocalEvidenceDraft(
            submissionId: draft?.submissionId, draftKey: draftKey,
            proposedContent: content, urlInput: urlText, choices: evidence,
            legacySubmissionId: legacySubmissionId, createdAt: localCreatedAt
        )
        if let data = try? JSONEncoder().encode(local) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    private func restoreDraft() async -> Bool {
        guard model.canContribute, Clerk.shared.user != nil else { return false }
        let restoredKey = localKey
        guard let data = UserDefaults.standard.data(forKey: restoredKey),
              let local = try? JSONDecoder().decode(LocalEvidenceDraft.self, from: data) else { return false }
        if local.submissionId == nil && Date().timeIntervalSince1970 * 1_000 - local.createdAt > 7 * 24 * 60 * 60 * 1_000 {
            for choice in local.choices { if let file = choice.fileURL { try? FileManager.default.removeItem(at: file) } }
            UserDefaults.standard.removeObject(forKey: restoredKey)
            return false
        }
        draftKey = local.draftKey
        localCreatedAt = local.createdAt
        content = local.proposedContent
        urlText = local.urlInput
        evidence = local.choices
        legacySubmissionId = local.legacySubmissionId
        guard let submissionId = local.submissionId else { return true }
        do {
            let stream = environment.convex.subscribe(to: "evidence:getOwnEvidenceDraft", with: ["submissionId": submissionId as ConvexEncodable?], yielding: EvidenceDraftView.self)
            guard let remote = try await stream.values.first(where: { _ in true }) else { return true }
            guard !Task.isCancelled, localKey == restoredKey else { return true }
            draft = remote
            content = remote.proposedContent
        } catch {
            guard !Task.isCancelled, localKey == restoredKey else { return true }
            errorMessage = "This draft could not be loaded. Retry after the connection returns."
        }
        return true
    }

    private func loadLegacyProposal() async {
        guard model.canContribute, Clerk.shared.user != nil else { return }
        let requestedKey = localKey
        let owned = environment.convex.subscribe(to: "evidence:getOwnEvidenceForTarget", with: ["hadithInternalId": hadith.internalId as ConvexEncodable?, "language": model.language as ConvexEncodable?], yielding: EvidenceDraftView?.self)
        if let latest = try? await owned.values.first(where: { _ in true }), let latest {
            guard !Task.isCancelled, localKey == requestedKey else { return }
            draft = latest
            content = latest.proposedContent
            return
        }
        let stream = environment.convex.subscribe(
            to: "evidence:getOwnLegacyProposal",
            with: ["hadithInternalId": hadith.internalId as ConvexEncodable?, "language": model.language as ConvexEncodable?],
            yielding: LegacyEvidenceProposal?.self
        )
        if let proposal = try? await stream.values.first(where: { _ in true }), let proposal {
            guard !Task.isCancelled, localKey == requestedKey else { return }
            legacySubmissionId = proposal.submissionId
            content = proposal.proposedContent
            persistLocal()
        }
    }

    private func fetchDraft(_ submissionId: String) async throws -> EvidenceDraftView {
        let stream = environment.convex.subscribe(
            to: "evidence:getOwnEvidenceDraft",
            with: ["submissionId": submissionId as ConvexEncodable?],
            yielding: EvidenceDraftView.self
        )
        guard let result = try await stream.values.first(where: { _ in true }) else {
            throw NSError(domain: "Evidence", code: 8, userInfo: [NSLocalizedDescriptionKey: "Draft status is unavailable. Retry when connected."])
        }
        return result
    }

    private func submit() async {
        let submissionOwner = ownerLanguageKey
        isSubmitting = true
        errorMessage = nil
        defer {
            if ownerLanguageKey == submissionOwner {
                isSubmitting = false
                activeUpload = nil
            }
        }
        do {
            let retrying = draft != nil
            let current: EvidenceDraftView
            if let draft {
                current = try await fetchDraft(draft.submissionId)
                try ensureCurrentOwner(submissionOwner)
                self.draft = current
                if ["awaiting_processing", "evidence_ready", "processing_failed", "infected", "under_review", "approved", "held", "rejected", "review_unavailable", "revoked"].contains(current.status) {
                    for choice in evidence { if let file = choice.fileURL { try? FileManager.default.removeItem(at: file) } }
                    evidence = []
                    persistLocal()
                    return
                }
                if current.status == "expired" { persistLocal(); return }
            }
            else {
                persistLocal()
                let descriptors: [ConvexEncodable?] = evidence.map { choice in
                    if choice.kind == "url" {
                        return ["kind": "url", "clientItemKey": choice.id, "url": choice.url?.absoluteString] as [String: ConvexEncodable?]
                    }
                    return ["kind": "file", "clientItemKey": choice.id, "declaredMime": choice.mime, "declaredSize": Double(choice.size ?? 0), "declaredSha256": choice.sha256, "displayName": choice.label] as [String: ConvexEncodable?]
                }
                var args: [String: ConvexEncodable?] = [
                    "hadithInternalId": hadith.internalId,
                    "language": model.language,
                    "proposedContent": content.trimmingCharacters(in: .whitespacesAndNewlines),
                    "draftKey": draftKey,
                    "items": descriptors as ConvexEncodable?,
                ]
                if let existingTranslation { args["replacesTranslationId"] = existingTranslation.translationId }
                if let legacySubmissionId { args["legacySubmissionId"] = legacySubmissionId }
                current = try await environment.convex.mutation("evidence:createEvidenceDraft", with: args)
                try ensureCurrentOwner(submissionOwner)
                draft = current
                persistLocal()
            }
            for item in current.items where item.kind == "file" && item.state != "quarantined_unscanned" {
                try Task.checkCancellation()
                guard let choice = evidence.first(where: { $0.id == item.clientItemKey }), let file = choice.fileURL, FileManager.default.fileExists(atPath: file.path) else {
                    throw NSError(domain: "Evidence", code: 4, userInfo: [NSLocalizedDescriptionKey: "Select this file again to retry the upload."])
                }
                if retrying {
                    let bytes = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.doubleValue ?? 0
                    let descriptor: [String: ConvexEncodable?] = ["kind": "file", "clientItemKey": item.clientItemKey, "declaredMime": choice.mime, "declaredSize": bytes, "declaredSha256": choice.sha256, "displayName": choice.label]
                    let _: Bool = try await environment.convex.mutation("evidence:replaceEvidenceSlot", with: ["submissionId": current.submissionId as ConvexEncodable?, "itemId": item.itemId as ConvexEncodable?, "descriptor": descriptor as ConvexEncodable?])
                    try ensureCurrentOwner(submissionOwner)
                }
                progress = 0
                try await upload(file: file, item: item, mime: choice.mime ?? item.declaredMime, submissionId: current.submissionId)
                try ensureCurrentOwner(submissionOwner)
            }
            let _: EvidenceSubmitResult = try await environment.convex.mutation("evidence:finalizeEvidenceDraft", with: ["submissionId": current.submissionId as ConvexEncodable?, "contributionConsentVersion": "e3-contribution-v1" as ConvexEncodable?])
            try ensureCurrentOwner(submissionOwner)
            draft = try await fetchDraft(current.submissionId)
            try ensureCurrentOwner(submissionOwner)
            for choice in evidence { if let file = choice.fileURL { try? FileManager.default.removeItem(at: file) } }
            evidence = []
            persistLocal()
        } catch is CancellationError {
            if ownerLanguageKey == submissionOwner { errorMessage = "Upload paused. Retry when you are ready." }
        } catch {
            if ownerLanguageKey == submissionOwner { errorMessage = ReaderModels.errorMessage(of: error) }
        }
    }

    private func ensureCurrentOwner(_ owner: String) throws {
        try Task.checkCancellation()
        guard ownerLanguageKey == owner else { throw CancellationError() }
    }

    private func deleteDraft() async {
        let deletingOwner = ownerLanguageKey
        guard let draft else {
            discardLocalDraft()
            return
        }
        do {
            let _: Bool = try await environment.convex.mutation("evidence:deleteEvidenceDraft", with: ["submissionId": draft.submissionId as ConvexEncodable?])
            try ensureCurrentOwner(deletingOwner)
            self.draft = nil
            discardLocalDraft()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            if ownerLanguageKey == deletingOwner { errorMessage = ReaderModels.errorMessage(of: error) }
        }
    }

    private func discardLocalDraft() {
        for choice in evidence { if let file = choice.fileURL { try? FileManager.default.removeItem(at: file) } }
        evidence = []
        content = ""
        urlText = ""
        draftKey = UUID().uuidString
        localCreatedAt = Date().timeIntervalSince1970 * 1_000
        UserDefaults.standard.removeObject(forKey: localKey)
    }

    private func upload(file: URL, item: EvidenceDraftView.Item, mime: String?, submissionId: String) async throws {
        guard let token = try await Clerk.shared.auth.getToken() else { throw NSError(domain: "Evidence", code: 5, userInfo: [NSLocalizedDescriptionKey: "Sign in again to upload evidence."]) }
        guard var components = URLComponents(string: environment.config.convexURL), let host = components.host, host.hasSuffix(".convex.cloud") else { throw NSError(domain: "Evidence", code: 6, userInfo: [NSLocalizedDescriptionKey: "Upload endpoint is unavailable."]) }
        components.host = String(host.dropLast(".convex.cloud".count)) + ".convex.site"
        components.path = "/evidence/upload"
        guard let url = components.url else { throw NSError(domain: "Evidence", code: 6) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(submissionId, forHTTPHeaderField: "X-Evidence-Submission-Id")
        request.setValue(item.itemId, forHTTPHeaderField: "X-Evidence-Item-Id")
        let delegate = EvidenceUploadProgress { value in Task { @MainActor in progress = value } }
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file, delegate: delegate)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Upload failed"
            throw NSError(domain: "Evidence", code: 7, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
