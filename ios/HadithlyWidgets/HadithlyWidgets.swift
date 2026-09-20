import SwiftUI
import WidgetKit
import Foundation

private struct WidgetEntry<Snapshot: Codable & Equatable>: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

private struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry<WidgetDailySnapshot> { .init(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry<WidgetDailySnapshot>) -> Void) {
        completion(.init(date: .now, snapshot: WidgetSnapshotStore.daily()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry<WidgetDailySnapshot>>) -> Void) {
        let entry = WidgetEntry(date: .now, snapshot: WidgetSnapshotStore.daily())
        completion(Timeline(entries: [entry], policy: .after(WidgetRefreshPolicy.nextRefresh(after: entry.snapshot))))
    }
}

private struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry<WidgetContinueSnapshot> { .init(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry<WidgetContinueSnapshot>) -> Void) {
        completion(.init(date: .now, snapshot: WidgetSnapshotStore.continue()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry<WidgetContinueSnapshot>>) -> Void) {
        let entry = WidgetEntry(date: .now, snapshot: WidgetSnapshotStore.continue())
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(60 * 60))))
    }
}

struct DailyHadithWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyHadithWidget", provider: DailyProvider()) { entry in
            DailyWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Hadith")
        .description("A private, cached reading prompt for today.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryInline, .accessoryRectangular, .accessoryCircular,
        ])
    }
}

private struct DailyWidgetView: View {
    let entry: WidgetEntry<WidgetDailySnapshot>
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        ZStack {
            if redactionReasons.contains(.privacy) {
                Text("Unlock Hadithly to view today’s hadith.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityLabel("Unlock Hadithly to view today’s hadith")
            } else if let snapshot = entry.snapshot {
                Link(destination: canonicalURL(snapshot)) {
                    DailyWidgetReading(snapshot: snapshot, family: family)
                        .environment(\.locale, Locale(identifier: snapshot.locale))
                        .environment(\.layoutDirection, layoutDirection(for: snapshot.locale))
                }
                .accessibilityLabel(accessibilityLabel(for: snapshot))
                .privacySensitive()
            } else {
                Text("Open Hadithly to prepare today’s hadith.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func canonicalURL(_ snapshot: WidgetDailySnapshot) -> URL {
        URL(string: "https://hadithly.app/hadith/\(snapshot.collectionSlug)/\(snapshot.providerHadithId)")!
    }

    private func layoutDirection(for locale: String) -> LayoutDirection {
        Locale.characterDirection(forLanguage: Locale(identifier: locale).languageCode ?? "en") == .rightToLeft
            ? .rightToLeft : .leftToRight
    }

    private func accessibilityLabel(for snapshot: WidgetDailySnapshot) -> String {
        var label = "Daily hadith, \(snapshot.reference), \(snapshot.sourceScope)"
        if snapshot.isAI { label += ", AI translation" }
        if WidgetRefreshPolicy.isStale(snapshot) { label += ", update when opened" }
        return label
    }
}

private struct DailyWidgetReading: View {
    let snapshot: WidgetDailySnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemSmall:
            homeReading(previewLines: 3, referenceFont: .headline, spacing: 5)
        case .systemMedium:
            homeReading(previewLines: 5, referenceFont: .title3, spacing: 7)
        case .systemLarge:
            largeReading
        case .systemExtraLarge:
            largeReading
        case .accessoryInline:
            Text("Daily hadith").lineLimit(1)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(shortReference).font(.headline).lineLimit(1)
                Text("Daily hadith").font(.caption).lineLimit(1)
            }
        case .accessoryCircular:
            ZStack(alignment: .topTrailing) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 34, weight: .medium))
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(-2)
            }
            .accessibilityLabel("Daily hadith")
        default:
            homeReading(previewLines: 3, referenceFont: .headline, spacing: 5)
        }
    }

    private func homeReading(previewLines: Int, referenceFont: Font, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text("DAILY HADITH").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(snapshot.reference).font(referenceFont).lineLimit(1)
            if snapshot.arabicVisible && snapshot.translationVisible {
                Text(snapshot.arabicText).font(.caption).lineLimit(1).multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                Text(snapshot.text).font(.subheadline).lineLimit(max(1, previewLines - 1)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(snapshot.translationVisible ? snapshot.text : snapshot.arabicText)
                    .font(.subheadline)
                    .lineLimit(previewLines)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(metadata).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeReading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAILY HADITH").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(snapshot.reference).font(.title3).lineLimit(1)
            if snapshot.arabicVisible && snapshot.translationVisible {
                Text(snapshot.arabicText).font(.body).multilineTextAlignment(.trailing).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Text(snapshot.text).font(.subheadline).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(snapshot.arabicVisible ? snapshot.arabicText : snapshot.text)
                    .font(snapshot.arabicVisible ? .body : .subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: snapshot.arabicVisible ? .topTrailing : .topLeading)
            }
            Text(metadata).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metadata: String {
        var parts = [snapshot.sourceScope]
        if snapshot.isAI { parts.append("AI translation") }
        if snapshot.isOffline { parts.append("Saved offline copy") }
        if WidgetRefreshPolicy.isStale(snapshot) { parts.append("Update when opened") }
        return parts.joined(separator: " · ")
    }

    private var accessoryContext: String {
        var parts = [snapshot.sourceScope]
        if snapshot.isAI { parts.append("AI") }
        if WidgetRefreshPolicy.isStale(snapshot) { parts.append("Update") }
        return parts.joined(separator: " · ")
    }

    private var shortReference: String {
        "\(snapshot.collectionSlug.capitalized) · \(snapshot.providerHadithId)"
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueReadingWidget", provider: ContinueProvider()) { entry in
            ContinueWidgetView(entry: entry)
        }
        .configurationDisplayName("Continue Reading")
        .description("Resume your private reading position.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .systemExtraLarge,
            .accessoryInline, .accessoryRectangular, .accessoryCircular,
        ])
    }
}

private struct ContinueWidgetView: View {
    let entry: WidgetEntry<WidgetContinueSnapshot>
    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
        if redactionReasons.contains(.privacy) {
            Text(ContinueWidgetPresentation.lockMessage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel(ContinueWidgetPresentation.lockMessage)
        } else if let snapshot = entry.snapshot {
            Link(destination: URL(string: "com.hadithly.app://continue")!) {
                ContinueWidgetReading(snapshot: snapshot, family: family)
                    .environment(\.locale, Locale(identifier: snapshot.locale))
                    .environment(\.layoutDirection, layoutDirection(for: snapshot.locale))
            }
            .accessibilityLabel("Continue reading \(snapshot.reference), \(snapshot.progressLabel)")
            .privacySensitive()
        } else {
            Text(ContinueWidgetPresentation.emptyMessage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func layoutDirection(for locale: String) -> LayoutDirection {
        Locale.characterDirection(forLanguage: Locale(identifier: locale).languageCode ?? "en") == .rightToLeft
            ? .rightToLeft : .leftToRight
    }
}

private struct ContinueWidgetReading: View {
    let snapshot: WidgetContinueSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemSmall:
            home(excerptLines: 2, spacing: 5)
        case .systemMedium:
            home(excerptLines: snapshot.presentation.mediumExcerptLineLimit, spacing: 7)
        case .systemLarge:
            largeHome
        case .systemExtraLarge:
            largeHome
        case .accessoryInline:
            Text(snapshot.presentation.accessoryInlineText).lineLimit(1)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Resume reading").font(.headline).lineLimit(1)
                Text(lockProgress).font(.caption).lineLimit(1)
            }
        case .accessoryCircular:
            progressGauge(size: 20)
                .accessibilityLabel("Continue reading")
        default:
            home(excerptLines: nil, spacing: 5)
        }
    }

    private func home(excerptLines: Int?, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text("CONTINUE READING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(snapshot.reference).font(.headline).lineLimit(1)
            if let excerptLines {
                Text(snapshot.translationVisible ? snapshot.translationExcerpt : snapshot.arabicExcerpt)
                    .font(.subheadline)
                    .lineLimit(excerptLines)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 7) {
                progressGauge(size: family == .systemSmall ? 28 : 32)
                Text(snapshot.progressLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if WidgetRefreshPolicy.isStale(snapshot.updatedAt) {
                Text("Position will be checked when opened").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeHome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTINUE READING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(snapshot.reference).font(.title3).lineLimit(1)
            if snapshot.arabicVisible && snapshot.translationVisible {
                Text(snapshot.arabicExcerpt).font(.body).multilineTextAlignment(.trailing).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Text(snapshot.translationExcerpt).font(.subheadline).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(snapshot.arabicVisible ? snapshot.arabicExcerpt : snapshot.translationExcerpt)
                    .font(snapshot.arabicVisible ? .body : .subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: snapshot.arabicVisible ? .topTrailing : .topLeading)
            }
            HStack(spacing: 7) { progressGauge(size: 32); Text(snapshot.progressLabel).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func progressGauge(size: CGFloat) -> some View {
        let gauge = WidgetProgressGaugeValue(fraction: snapshot.progressFraction)
        if let value = gauge.value {
            if family == .accessoryCircular {
                nativeGauge(value: value)
                    .accessibilityLabel("\(gauge.percent ?? 0) percent read")
            } else {
                nativeGauge(value: value)
                    .scaleEffect(0.52)
                    .frame(width: size, height: size)
                    .accessibilityLabel("\(gauge.percent ?? 0) percent read")
            }
        } else {
            Image(systemName: "book.closed")
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private func nativeGauge(value: Double) -> some View {
        Gauge(value: value, in: 0...1) { EmptyView() } currentValueLabel: {
            Image(systemName: "book.closed.fill")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .controlSize(.small)
    }

    private var lockProgress: String {
        guard let fraction = snapshot.progressFraction else { return "Resume" }
        return "\(Int((fraction * 100).rounded()))% read"
    }
}


@main
struct HadithlyWidgets: WidgetBundle {
    var body: some Widget { DailyHadithWidget(); ContinueReadingWidget() }
}
