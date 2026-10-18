import SwiftUI
import ClerkKit

enum OnboardingStep: Int, CaseIterable { case welcome, language, demonstration, account }

struct OnboardingFlowView: View {
    let onComplete: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.readerPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("onboarding.la2.step") private var storedStep = 0
    @AppStorage("onboarding.la2.visited") private var visited = 0
    @State private var completedCreation: Bool?
    @State private var showingSignIn = false
    private var step: OnboardingStep { OnboardingStep(rawValue: storedStep) ?? .welcome }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome {
                    HStack {
                        Button { storedStep = max(0, storedStep - 1) } label: {
                            Label("la2.back", systemImage: "chevron.backward").frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding.back")
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 24)
                    .foregroundStyle(palette.textSecondary)
                }

                Group {
                    switch step {
                    case .welcome:
                        WelcomeView(showsBackground: false)
                    case .language:
                        LanguagePickerView(selection: Binding(
                            get: { environment.preferences.preferences.uiLocale },
                            set: { environment.preferences.applyOnboardingLanguage($0) }
                        ))
                    case .demonstration:
                        OnboardingTranslationView(locale: environment.preferences.preferences.translationLocale, onChooseLanguage: { storedStep = OnboardingStep.language.rawValue })
                    case .account:
                        VStack(spacing: 16) {
                            Spacer(minLength: 24)
                            Text("la2.account_title")
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                            Text("la2.account_body")
                                .font(.body)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                            Spacer(minLength: 24)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.opacity.combined(with: .offset(x: reducedMotion ? 0 : (layoutDirection == .rightToLeft ? -InterfaceMotion.travel : InterfaceMotion.travel))))

                footer
            }
            .animation(reducedMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: InterfaceMotion.step), value: storedStep)
            .background {
                if step == .welcome || step == .account { EntryArtworkBackdrop() }
                else { palette.background.ignoresSafeArea() }
            }
            .foregroundStyle(palette.textPrimary)
            .onAppear { recordStep() }
            .onChange(of: storedStep) { _, _ in recordStep() }
            .navigationDestination(isPresented: $showingSignIn) {
                SignInView(onAuthenticated: {
                    await environment.completeSignIn()
                    showingSignIn = false
                    guard Clerk.shared.session != nil else {
                        environment.analytics.record(.onboardingStepAuthFailed)
                        return
                    }
                    finish(completedCreation == true ? .onboardingCompletedAccountNew : completedCreation == false ? .onboardingCompletedAccountExisting : .onboardingCompletedAccountUnknown)
                }, onDismiss: {
                    environment.analytics.record(.onboardingStepAuthCancelled)
                    showingSignIn = false
                }, onCreationResult: { completedCreation = $0 }, onAuthenticationFailure: {
                    environment.analytics.record(.onboardingStepAuthFailed)
                }, embeddedInNavigation: true)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if step == .account {
            VStack(spacing: 12) {
                OnboardingPrimaryButton("la2.sign_in") {
                    completedCreation = nil
                    environment.analytics.record(.onboardingStepAuthStarted)
                    showingSignIn = true
                }
                .accessibilityIdentifier("onboarding.signIn")
                Button { finish(.onboardingCompletedGuest) } label: {
                    Text("la2.guest").frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("onboarding.guest")
            }
            .padding(24)
        } else {
            let title: LocalizedStringKey = step == .welcome ? "la2.get_started" : "la2.continue"
            OnboardingPrimaryButton(title) {
                if step == .welcome { environment.analytics.startOnboarding() }
                storedStep += 1
            }
                .padding(24)
                .accessibilityIdentifier(step == .welcome ? "onboarding.getStarted" : "onboarding.continue")
        }
    }

    private func recordStep() {
        let bit = 1 << step.rawValue
        guard visited & bit == 0 else { return }
        visited |= bit
        environment.analytics.record([.onboardingStepWelcomeViewed, .onboardingStepLanguageViewed, .onboardingStepDemoViewed, .onboardingStepEntryViewed][step.rawValue])
        if step != .welcome { environment.analytics.startOnboarding() }
    }

    private func finish(_ metric: AnalyticsMetric) {
        environment.analytics.completeOnboarding(metric)
        storedStep = 0
        visited = 0
        onComplete()
    }
}

struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @Environment(\.readerPalette) private var palette
    init(_ title: LocalizedStringKey, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 52).background(palette.interactive)
                .foregroundStyle(palette.onInteractive).clipShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(QuietPressStyle())
    }
}

enum FirstReadingResult: Decodable, Equatable {
    case ready(FirstReadingReady)
    case unavailable

    private enum Keys: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "ready": self = .ready(try FirstReadingReady(from: decoder))
        case "unavailable": self = .unavailable
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown first-reading outcome")
        }
    }
}

struct FirstReadingReady: Decodable, Equatable {
    enum Origin: String, Decodable { case daily, starter }
    let locale: String
    let origin: Origin
    let reading: FirstReadingDocument
    let validUntil: Double?
    let daily: FirstReadingDailySummary?

    private enum Keys: String, CodingKey { case locale, origin, reading, validUntil, daily }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        locale = try values.decode(String.self, forKey: .locale)
        origin = try values.decode(Origin.self, forKey: .origin)
        reading = try values.decode(FirstReadingDocument.self, forKey: .reading)
        validUntil = try values.decodeIfPresent(Double.self, forKey: .validUntil)
        daily = try values.decodeIfPresent(FirstReadingDailySummary.self, forKey: .daily)
        guard validUntil.map({ $0.isFinite && $0 >= 0 }) ?? true,
              reading.text.language == locale, !reading.text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reading.provider == "sunnah_now", ReaderModels.collections.contains(where: { $0.slug == reading.collectionSlug }),
              reading.canonicalId == "\(reading.provider):\(reading.collectionSlug):\(reading.providerHadithId)",
              origin != .daily || (daily?.canonicalId == reading.canonicalId && daily?.hasExactText == true),
              reading.text.kind != .original || (locale == "ar" && !reading.text.isAI && reading.text.text == reading.arabicText) else {
            throw DecodingError.dataCorruptedError(forKey: .reading, in: values, debugDescription: "Invalid exact-language reading")
        }
    }
}
struct FirstReadingDailySummary: Decodable, Equatable {
    let canonicalId: String
    let referenceDisplay: String
    let hasExactText: Bool
}
struct FirstReadingDocument: Decodable, Equatable, Identifiable {
    var id: String { canonicalId }
    let canonicalId: String
    let provider: String
    let collectionSlug: String
    let providerHadithId: String
    let collectionName: String
    let volumeId: String?
    let referenceDisplay: String
    let referenceUrl: String?
    let authenticity: ReaderAuthenticity
    let arabicText: String
    let text: ReadingText
    struct ReadingText: Decodable, Equatable {
        enum Kind: String, Decodable { case original, translation }
        let kind: Kind
        let text: String
        let language: String
        let sourceLabel: String
        let sourceUrl: String?
        let isAI: Bool
        let credits: [Credit]
        struct Credit: Decodable, Equatable {
            enum Scope: String, Decodable { case original, translation }
            let scope: Scope
            let attribution: String
            let licenseName: String
            let url: String?
        }
    }
}
enum FirstReadingPhase: Equatable {
    case loading, failed
    case result(FirstReadingResult)
    var ready: FirstReadingReady? {
        guard case .result(.ready(let ready)) = self else { return nil }
        return ready
    }
}

struct OnboardingTranslationView: View {
    let locale: String
    var onChooseLanguage: () -> Void = {}
    var source: ((String) -> AsyncThrowingStream<FirstReadingResult, Error>)?
    @Environment(AppEnvironment.self) private var environment
    @State private var phase = FirstReadingPhase.loading
    @State private var retry = 0
    @State private var openReading: FirstReadingDocument?
    @State private var recordedReading = false

    var body: some View {
        FirstReadingContent(phase: phase.ready?.locale == locale || phase.ready == nil ? phase : .loading,
                            onRetry: { retry += 1 }, onChooseLanguage: onChooseLanguage,
                            onOpen: { openReading = $0 }, onRendered: {
            if !recordedReading { recordedReading = true; environment.analytics.record(.onboardingStepDemoUsed) }
        })
        .task(id: "\(locale)|\(retry)") {
            phase = .loading
            recordedReading = false
            do {
                if let source {
                    for try await result in source(locale) {
                        guard !Task.isCancelled else { return }
                        receive(result)
                    }
                }
                else {
                    for try await result in environment.convex.subscribe(to: "firstReading:get", with: [
                        "timezone": TimeZone.current.identifier, "translationLocale": locale,
                    ], yielding: FirstReadingResult.self).values {
                        guard !Task.isCancelled else { return }
                        receive(result)
                    }
                }
            } catch {
                if !Task.isCancelled { phase = .failed }
            }
        }
        .task(id: phase.ready?.validUntil) {
            guard let expiry = phase.ready?.validUntil else { return }
            do {
                try await Task.sleep(for: .milliseconds(max(0, expiry - Date().timeIntervalSince1970 * 1000)))
                guard !Task.isCancelled, phase.ready?.validUntil == expiry else { return }
                phase = .result(.unavailable)
            } catch { }
        }
        .fullScreenCover(item: $openReading) { reading in
            ReaderView(collectionSlug: reading.collectionSlug, collectionName: reading.collectionName,
                       openVolumeId: reading.volumeId, openHadithNumber: reading.providerHadithId, targetSource: .canonicalLink)
        }
    }

    @MainActor private func receive(_ result: FirstReadingResult) {
        if case .ready(let ready) = result {
            guard ready.locale == locale else { phase = .failed; return }
            if let expiry = ready.validUntil, expiry <= Date().timeIntervalSince1970 * 1000 { phase = .result(.unavailable); return }
        }
        phase = .result(result)
    }
}

struct FirstReadingContent: View {
    let phase: FirstReadingPhase
    let onRetry: () -> Void
    let onChooseLanguage: () -> Void
    let onOpen: (FirstReadingDocument) -> Void
    var onRendered: () -> Void = {}
    @Environment(\.readerPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("la2.demo_title").font(.largeTitle.bold()).padding(.top, 28)
                switch phase {
                case .loading:
                    ContentSkeleton(kind: .daily, label: "Loading…").accessibilityIdentifier("onboarding.dailyLoading")
                case .failed:
                    Text("Reading could not load").foregroundStyle(palette.textSecondary)
                    Button("Try again", action: onRetry).frame(minHeight: 44).accessibilityIdentifier("onboarding.dailyRetry")
                case .result(.unavailable):
                    Text("No reading in this language is available yet.").foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("onboarding.readingUnavailable")
                    Button("Choose another language", action: onChooseLanguage).frame(minHeight: 44)
                        .accessibilityIdentifier("onboarding.chooseReadingLanguage")
                case .result(.ready(let ready)):
                    let item = ready.reading
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ready.origin == .daily ? LocalizedStringKey("Today's hadith") : LocalizedStringKey("A first reading"))
                            .font(.caption).accessibilityIdentifier("onboarding.readingOrigin")
                        Button(item.referenceDisplay) { onOpen(item) }
                            .font(.caption.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("onboarding.openReading")
                        Text(item.authenticity.displayLabel).font(.caption)
                    }.foregroundStyle(palette.textSecondary)
                    HadithReadingText(arabicText: item.arabicText,
                                      translation: item.text.kind == .translation ? item.text.text : nil,
                                      translationLanguage: item.text.language,
                                      arabicVisible: item.text.kind == .original,
                                      textColor: palette.textPrimary)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("onboarding.dailyText")
                        .onAppear(perform: onRendered)
                    if item.text.kind == .translation {
                        DisclosureGroup("Arabic") {
                            HadithReadingText(arabicText: item.arabicText, translation: nil,
                                              translationLanguage: "ar", textColor: palette.textPrimary)
                                .accessibilityElement(children: .contain)
                        }.font(.caption).accessibilityIdentifier("onboarding.readingArabic")
                    }
                    HStack(spacing: 6) {
                        if item.text.isAI { Text("AI translation") } else { Text(item.text.sourceLabel) }
                        if let raw = item.text.sourceUrl, let url = URL(string: raw) {
                            Link(destination: url) { Image(systemName: "arrow.up.right") }.accessibilityLabel("Translation source")
                        }
                        if let raw = item.referenceUrl, raw != item.text.sourceUrl, let url = URL(string: raw) {
                            Link("Original source", destination: url)
                        }
                    }
                    .font(.caption).foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("onboarding.translationSource")
                    DisclosureGroup("Sources") {
                        ForEach(Array(item.text.credits.enumerated()), id: \.offset) { _, credit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(credit.scope == .original ? LocalizedStringKey("Original source") : LocalizedStringKey("Translation source"))
                                    .font(.caption2).foregroundStyle(palette.textSecondary)
                                Text(credit.attribution).font(.caption)
                                if let raw = credit.url, let url = URL(string: raw) { Link(credit.licenseName, destination: url).font(.caption) }
                                else { Text(credit.licenseName).font(.caption) }
                            }.padding(.vertical, 4)
                        }
                    }.font(.caption).accessibilityIdentifier("onboarding.readingCredits")
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}
