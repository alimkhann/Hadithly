import Foundation

struct ReaderMeasurement {
    private(set) var started = false
    private(set) var rendered = false
    private var failed = false
    private var closed = false
    private var targetSettled = false
    private var guest = true
    private var restoration = false
    private var notification = false

    mutating func begin(guest: Bool, restoration: Bool, notification: Bool) -> [AnalyticsMetric] {
        guard !started else { return [] }; started = true
        self.guest = guest; self.restoration = restoration; self.notification = notification
        var facts: [AnalyticsMetric] = [guest ? .readerOpenResultGuestStarted : .readerOpenResultAccountStarted]
        if restoration { facts.append(.restorationResultStarted) }
        if notification { facts.append(.notificationOpenResultStarted) }
        return facts
    }
    mutating func failure() -> [AnalyticsMetric] {
        guard started, !closed, !failed else { return [] }; failed = true
        return rendered ? [.recoverableErrorReader] : [.readerOpenResultFailed, .recoverableErrorReader]
    }
    mutating func visible(offline: Bool) -> [AnalyticsMetric] {
        guard started, !closed else { return [] }
        var facts: [AnalyticsMetric] = []
        if !rendered {
            if failed { facts.append(guest ? .readerOpenResultGuestStarted : .readerOpenResultAccountStarted) }
            facts.append(guest ? (offline ? .readerOpenResultGuestOffline : .readerOpenResultGuestOnline)
                         : (offline ? .readerOpenResultAccountOffline : .readerOpenResultAccountOnline))
            rendered = true
        }
        if failed { facts.append(.recoverableErrorReaderRecovered); failed = false }
        return facts
    }
    mutating func settleTarget(exact: Bool) -> [AnalyticsMetric] {
        guard started, !closed, !targetSettled else { return [] }; targetSettled = true
        var facts: [AnalyticsMetric] = []
        if restoration { facts.append(exact ? .restorationResultExact : .restorationResultFallback) }
        if notification { facts.append(exact ? .notificationOpenResultExact : .notificationOpenResultFallback) }
        return facts
    }
    mutating func close() -> [AnalyticsMetric] {
        guard started, !closed else { return [] }
        var facts: [AnalyticsMetric]
        if failed, !rendered, !targetSettled {
            targetSettled = true; facts = []
            if restoration { facts.append(.restorationResultFailed) }
            if notification { facts.append(.notificationOpenResultFailed) }
        } else { facts = settleTarget(exact: false) }
        if !rendered, !failed { facts.append(.readerOpenResultAbandoned) }
        closed = true
        return facts
    }
}
