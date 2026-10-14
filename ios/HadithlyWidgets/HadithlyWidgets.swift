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
    private var locale: String { entry.snapshot?.locale ?? WidgetSnapshotStore.uiLocale() }

    var body: some View {
        ZStack {
            if redactionReasons.contains(.privacy) {
                Text(DailyWidgetCopy.locked(locale))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityLabel(DailyWidgetCopy.locked(locale))
            } else if let snapshot = entry.snapshot {
                Link(destination: canonicalURL(snapshot)) {
                    DailyWidgetReading(snapshot: snapshot, family: family)
                        .environment(\.locale, Locale(identifier: snapshot.locale))
                        .environment(\.layoutDirection, layoutDirection(for: snapshot.locale))
                }
                .accessibilityLabel(accessibilityLabel(for: snapshot))
                .privacySensitive()
            } else {
                Text(DailyWidgetCopy.empty(locale))
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
        Locale.Language(identifier: locale).characterDirection == .rightToLeft
            ? .rightToLeft : .leftToRight
    }

    private func accessibilityLabel(for snapshot: WidgetDailySnapshot) -> String {
        var label = "\(DailyWidgetCopy.title(snapshot.locale)), \(snapshot.reference), \(snapshot.sourceScope)"
        if snapshot.isAI { label += ", \(DailyWidgetCopy.ai(snapshot.locale))" }
        if WidgetRefreshPolicy.isStale(snapshot) { label += ", \(DailyWidgetCopy.stale(snapshot.locale))" }
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
            Text(DailyWidgetCopy.title(snapshot.locale)).lineLimit(1)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(shortReference).font(.headline).lineLimit(1)
                Text(DailyWidgetCopy.title(snapshot.locale)).font(.caption).lineLimit(1)
            }
        case .accessoryCircular:
            ZStack(alignment: .topTrailing) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 34, weight: .medium))
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(-2)
            }
            .accessibilityLabel(DailyWidgetCopy.title(snapshot.locale))
        default:
            homeReading(previewLines: 3, referenceFont: .headline, spacing: 5)
        }
    }

    private func homeReading(previewLines: Int, referenceFont: Font, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(DailyWidgetCopy.title(snapshot.locale).uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
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
            Text(DailyWidgetCopy.title(snapshot.locale).uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
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
        if snapshot.isAI { parts.append(DailyWidgetCopy.ai(snapshot.locale)) }
        if snapshot.isOffline { parts.append(DailyWidgetCopy.offline(snapshot.locale)) }
        if WidgetRefreshPolicy.isStale(snapshot) { parts.append(DailyWidgetCopy.stale(snapshot.locale)) }
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

    private var copy: ContinueWidgetPresentation {
        entry.snapshot?.presentation ?? ContinueWidgetPresentation(reference: "", progressFraction: nil, progressOrdinal: nil, progressTotal: nil, locale: WidgetSnapshotStore.uiLocale())
    }

    var body: some View {
        Group {
        if redactionReasons.contains(.privacy) {
            Text(copy.localizedLockMessage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel(copy.localizedLockMessage)
        } else if let snapshot = entry.snapshot {
            Link(destination: URL(string: "com.hadithly.app://continue")!) {
                ContinueWidgetReading(snapshot: snapshot, family: family)
                    .environment(\.locale, Locale(identifier: snapshot.locale))
                    .environment(\.layoutDirection, layoutDirection(for: snapshot.locale))
            }
            .accessibilityLabel("\(copy.title), \(copy.localizedReference), \(copy.progressLabel)")
            .privacySensitive()
        } else {
            Text(copy.localizedEmptyMessage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func layoutDirection(for locale: String) -> LayoutDirection {
        Locale.Language(identifier: locale).characterDirection == .rightToLeft
            ? .rightToLeft : .leftToRight
    }
}

private struct ContinueWidgetReading: View {
    let snapshot: WidgetContinueSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemSmall:
            home(spacing: 5)
        case .systemMedium:
            home(spacing: 7)
        case .systemLarge:
            largeHome
        case .systemExtraLarge:
            largeHome
        case .accessoryInline:
            Text(snapshot.presentation.accessoryInlineText).lineLimit(1)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.presentation.resumeText).font(.headline).lineLimit(1)
                Text(lockProgress).font(.caption).lineLimit(1)
            }
        case .accessoryCircular:
            progressGauge(size: 20)
                .accessibilityLabel(snapshot.presentation.title)
        default:
            home(spacing: 5)
        }
    }

    private func home(spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(snapshot.presentation.title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(snapshot.presentation.localizedReference)
                .font(family == .systemSmall ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(2)
            if family == .systemSmall {
                Text(snapshot.presentation.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: 7) {
                    progressGauge(size: 32)
                    Text(snapshot.presentation.progressLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if WidgetRefreshPolicy.isStale(snapshot.updatedAt) {
                Text(snapshot.presentation.staleMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeHome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.presentation.title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(snapshot.presentation.localizedReference).font(.title3).lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 7) { progressGauge(size: 32); Text(snapshot.presentation.progressLabel).font(.caption).foregroundStyle(.secondary) }
            if WidgetRefreshPolicy.isStale(snapshot.updatedAt) {
                Text(snapshot.presentation.staleMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
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
        guard let fraction = snapshot.progressFraction else { return snapshot.presentation.resumeText }
        return "\(Int((fraction * 100).rounded()))%"
    }
}


@main
struct HadithlyWidgets: WidgetBundle {
    var body: some Widget { DailyHadithWidget(); ContinueReadingWidget() }
}
