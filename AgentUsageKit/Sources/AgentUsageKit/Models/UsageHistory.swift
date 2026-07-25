//
//  UsageHistory.swift
//  AgentUsageKit
//
//  Models for tracking historical usage data over time
//

import Foundation

// MARK: - Daily Usage Record

/// A record of usage for a single day
public struct DailyUsageRecord: Sendable, Codable, Identifiable {
    public var id: Date { date }

    /// The date this record represents (normalized to start of day)
    public let date: Date

    /// Peak session utilization observed during the day (0-100)
    public let peakSessionUtilization: Double

    /// Peak opus utilization observed during the day (0-100)
    public let peakOpusUtilization: Double

    /// Peak sonnet utilization observed during the day (0-100, optional)
    public let peakSonnetUtilization: Double?

    /// Peak fable utilization observed during the day (0-100, optional)
    public let peakFableUtilization: Double?

    /// Timestamp when this record was last updated
    public let updatedAt: Date

    public init(
        date: Date,
        peakSessionUtilization: Double,
        peakOpusUtilization: Double,
        peakSonnetUtilization: Double?,
        peakFableUtilization: Double? = nil,
        updatedAt: Date = Date()
    ) {
        self.date = date
        self.peakSessionUtilization = peakSessionUtilization
        self.peakOpusUtilization = peakOpusUtilization
        self.peakSonnetUtilization = peakSonnetUtilization
        self.peakFableUtilization = peakFableUtilization
        self.updatedAt = updatedAt
    }

    /// Create a record from a usage snapshot
    public static func from(snapshot: UsageSnapshot, date: Date = Date()) -> DailyUsageRecord {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)

        return DailyUsageRecord(
            date: normalizedDate,
            peakSessionUtilization: snapshot.session.utilization,
            peakOpusUtilization: snapshot.opus.utilization,
            peakSonnetUtilization: snapshot.sonnet?.utilization,
            peakFableUtilization: snapshot.fable?.utilization,
            updatedAt: Date()
        )
    }

    /// Merge this record with a newer snapshot, keeping the peak values
    public func mergedWith(snapshot: UsageSnapshot) -> DailyUsageRecord {
        DailyUsageRecord(
            date: date,
            peakSessionUtilization: max(peakSessionUtilization, snapshot.session.utilization),
            peakOpusUtilization: max(peakOpusUtilization, snapshot.opus.utilization),
            peakSonnetUtilization: mergePeak(peakSonnetUtilization, snapshot.sonnet?.utilization),
            peakFableUtilization: mergePeak(peakFableUtilization, snapshot.fable?.utilization),
            updatedAt: Date()
        )
    }

    private func mergePeak(_ existing: Double?, _ new: Double?) -> Double? {
        switch (existing, new) {
        case let (e?, n?): return max(e, n)
        case let (e?, nil): return e
        case let (nil, n?): return n
        case (nil, nil): return nil
        }
    }
}

// MARK: - Usage History

/// Collection of historical usage records
public struct UsageHistory: Sendable, Codable {
    /// Daily usage records sorted by date (oldest first)
    public private(set) var records: [DailyUsageRecord]

    /// Maximum number of days to retain
    public let maxDays: Int

    public init(records: [DailyUsageRecord] = [], maxDays: Int = 30) {
        self.records = records.sorted { $0.date < $1.date }
        self.maxDays = maxDays
    }

    /// Add or update a record for today based on the snapshot
    public mutating func record(snapshot: UsageSnapshot) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let existingIndex = records.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            // Update existing record with peak values
            records[existingIndex] = records[existingIndex].mergedWith(snapshot: snapshot)
        } else {
            // Add new record
            records.append(.from(snapshot: snapshot))
            records.sort { $0.date < $1.date }
        }

        // Trim old records
        trimOldRecords()
    }

    private mutating func trimOldRecords() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxDays, to: Date()) ?? Date()
        records.removeAll { $0.date < cutoffDate }
    }

    /// Get records for the last N days
    public func last(_ days: Int) -> [DailyUsageRecord] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return records.filter { $0.date >= cutoffDate }
    }

    /// Average session utilization over the recorded period
    public var averageSessionUtilization: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.peakSessionUtilization).reduce(0, +) / Double(records.count)
    }

    /// Average opus utilization over the recorded period
    public var averageOpusUtilization: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.peakOpusUtilization).reduce(0, +) / Double(records.count)
    }

    /// Days where usage exceeded 90%
    public var criticalDays: [DailyUsageRecord] {
        records.filter { $0.peakOpusUtilization >= 90 || $0.peakSessionUtilization >= 90 }
    }

    /// Empty history for previews
    public static let empty = UsageHistory()

    /// Sample history for previews
    public static var sample: UsageHistory {
        let calendar = Calendar.current
        var records: [DailyUsageRecord] = []

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let normalizedDate = calendar.startOfDay(for: date)

            // Generate somewhat realistic sample data
            let baseSession = Double.random(in: 20...60)
            let baseOpus = Double.random(in: 15...45)
            let baseSonnet = Double.random(in: 10...35)
            let baseFable = Double.random(in: 10...35)

            records.append(DailyUsageRecord(
                date: normalizedDate,
                peakSessionUtilization: baseSession + Double.random(in: 0...15),
                peakOpusUtilization: baseOpus + Double.random(in: 0...10),
                peakSonnetUtilization: baseSonnet + Double.random(in: 0...10),
                peakFableUtilization: baseFable + Double.random(in: 0...10),
                updatedAt: date
            ))
        }

        return UsageHistory(records: records)
    }
}

// MARK: - Provider Window Peak

/// The highest utilization observed for a single provider window on a single day.
///
/// Provider-neutral replacement for ``DailyUsageRecord``, whose fixed
/// session/opus/sonnet/fable fields can only describe Claude.
public struct ProviderWindowPeak: Sendable, Codable, Identifiable, Hashable {
    public let provider: Provider
    public let windowID: UsageWindowID
    /// Window name as the provider reported it when the peak was recorded.
    public let windowLabel: String
    /// Start of the day this peak belongs to.
    public let date: Date
    public let peakUtilization: Double

    public var id: String {
        "\(provider.rawValue)|\(windowID.rawValue)|\(Int(date.timeIntervalSince1970))"
    }

    public init(
        provider: Provider,
        windowID: UsageWindowID,
        windowLabel: String,
        date: Date,
        peakUtilization: Double
    ) {
        self.provider = provider
        self.windowID = windowID
        self.windowLabel = windowLabel
        self.date = date
        self.peakUtilization = peakUtilization
    }
}

// MARK: - Provider Usage History

/// Daily peak utilization across every monitored provider.
public struct ProviderUsageHistory: Sendable, Codable {
    /// Utilization at or above which a day counts as critical.
    public static let criticalThreshold: Double = 90

    /// Utilization at or above which a day counts as a warning.
    public static let warningThreshold: Double = 75

    /// Peaks sorted oldest first.
    public private(set) var peaks: [ProviderWindowPeak]

    public init(peaks: [ProviderWindowPeak] = []) {
        self.peaks = peaks.sorted { $0.date < $1.date }
    }

    public var isEmpty: Bool { peaks.isEmpty }

    /// Providers that recorded at least one peak, in `Provider.allCases` order.
    public var providers: [Provider] {
        let present = Set(peaks.map(\.provider))
        return Provider.allCases.filter(present.contains)
    }

    /// Restrict the history to the last `days` days.
    public func last(_ days: Int) -> ProviderUsageHistory {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return ProviderUsageHistory(peaks: peaks.filter { $0.date >= cutoff })
    }

    public func peaks(for provider: Provider) -> [ProviderWindowPeak] {
        peaks.filter { $0.provider == provider }
    }

    // MARK: Plottable series

    /// A named line of daily points, ready to plot.
    public struct Series: Sendable, Identifiable {
        public let id: String
        public let label: String
        public let provider: Provider
        public let points: [Point]

        public struct Point: Sendable, Identifiable {
            public var id: Date { date }
            public let date: Date
            public let utilization: Double

            public init(date: Date, utilization: Double) {
                self.date = date
                self.utilization = utilization
            }
        }

        public init(id: String, label: String, provider: Provider, points: [Point]) {
            self.id = id
            self.label = label
            self.provider = provider
            self.points = points
        }
    }

    /// One series per provider, each point that provider's worst window on the day.
    ///
    /// Collapsing to the worst window keeps the all-providers chart readable; the
    /// per-window detail is available from ``seriesByWindow(for:)``.
    public func seriesByProvider() -> [Series] {
        providers.map { provider in
            Series(
                id: provider.rawValue,
                label: provider.displayName,
                provider: provider,
                points: dailyMaxima(of: peaks(for: provider))
            )
        }
    }

    /// One series per window for a single provider.
    ///
    /// Labels are made unique: charts key a line by its label, so two windows
    /// reporting the same name would otherwise be drawn as one line.
    public func seriesByWindow(for provider: Provider) -> [Series] {
        let series = Dictionary(grouping: peaks(for: provider), by: \.windowID)
            .map { windowID, entries in
                Series(
                    id: "\(provider.rawValue)|\(windowID.rawValue)",
                    // Labels can change between releases; the newest one wins.
                    label: entries.max { $0.date < $1.date }?.windowLabel ?? windowID.rawValue,
                    provider: provider,
                    points: dailyMaxima(of: entries)
                )
            }
            .sorted { $0.label < $1.label }

        var counts: [String: Int] = [:]
        for line in series {
            counts[line.label, default: 0] += 1
        }
        return series.map { line in
            guard counts[line.label, default: 0] > 1 else { return line }
            let windowID = line.id.split(separator: "|").last.map(String.init) ?? line.id
            return Series(
                id: line.id,
                label: "\(line.label) (\(windowID))",
                provider: line.provider,
                points: line.points
            )
        }
    }

    private func dailyMaxima(of entries: [ProviderWindowPeak]) -> [Series.Point] {
        Dictionary(grouping: entries, by: \.date)
            .map { Series.Point(date: $0.key, utilization: $0.value.map(\.peakUtilization).max() ?? 0) }
            .sorted { $0.date < $1.date }
    }

    // MARK: Statistics

    /// Headline numbers for a slice of history.
    public struct Stats: Sendable, Equatable {
        /// Mean of the daily worst-window peaks.
        public let average: Double
        /// Highest peak observed.
        public let peak: Double
        /// Distinct days that reached ``ProviderUsageHistory/criticalThreshold``.
        public let criticalDays: Int
        /// Direction of travel across the slice.
        public let trend: UsageTrend

        public init(average: Double, peak: Double, criticalDays: Int, trend: UsageTrend) {
            self.average = average
            self.peak = peak
            self.criticalDays = criticalDays
            self.trend = trend
        }
    }

    /// Statistics over this history, optionally narrowed to one provider.
    ///
    /// Always computed from the receiver, so a history already narrowed by
    /// ``last(_:)`` yields statistics for exactly the period on screen.
    public func stats(for provider: Provider? = nil) -> Stats {
        let scoped = provider.map(peaks(for:)) ?? peaks
        guard !scoped.isEmpty else {
            return Stats(average: 0, peak: 0, criticalDays: 0, trend: .stable)
        }

        let daily = dailyMaxima(of: scoped)
        let criticalDays = daily.filter { $0.utilization >= Self.criticalThreshold }.count

        return Stats(
            average: daily.map(\.utilization).reduce(0, +) / Double(daily.count),
            peak: scoped.map(\.peakUtilization).max() ?? 0,
            criticalDays: criticalDays,
            trend: UsageTrend.calculate(from: daily.map(\.utilization))
        )
    }

    // MARK: Previews

    public static let empty = ProviderUsageHistory()

    public static var sample: ProviderUsageHistory {
        let calendar = Calendar.current
        let windows: [(Provider, UsageWindowID, String, Double)] = [
            (.claude, UsageWindowID(rawValue: "session"), "Session", 55),
            (.claude, UsageWindowID(rawValue: "opus"), "All Models", 40),
            (.codex, UsageWindowID(rawValue: "session"), "5h Limit", 70),
        ]

        var peaks: [ProviderWindowPeak] = []
        for dayOffset in (0..<14).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let day = calendar.startOfDay(for: date)
            // Deterministic wave so previews and snapshots stay stable.
            let wave = sin(Double(dayOffset) / 2.2)
            for (provider, windowID, label, base) in windows {
                peaks.append(ProviderWindowPeak(
                    provider: provider,
                    windowID: windowID,
                    windowLabel: label,
                    date: day,
                    peakUtilization: min(100, max(0, base + wave * 25))
                ))
            }
        }
        return ProviderUsageHistory(peaks: peaks)
    }
}

// MARK: - Usage Trend

/// Represents the trend direction of usage
public enum UsageTrend: String, Sendable {
    case increasing
    case decreasing
    case stable

    public var icon: String {
        switch self {
        case .increasing: return "arrow.up"
        case .decreasing: return "arrow.down"
        case .stable: return "arrow.forward"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .increasing: return "increasing"
        case .decreasing: return "decreasing"
        case .stable: return "stable"
        }
    }

    /// Calculate the trend across a time-ordered series of daily values.
    ///
    /// The series is split into two non-overlapping halves and their means
    /// compared. An earlier version sampled `suffix(3)` from each half, which
    /// could place the same value in both and understate the change.
    public static func calculate(from values: [Double]) -> UsageTrend {
        guard values.count >= 2 else { return .stable }

        let midpoint = values.count / 2
        let older = values.prefix(midpoint)
        let recent = values.suffix(values.count - midpoint)

        guard !recent.isEmpty && !older.isEmpty else { return .stable }

        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)

        let difference = recentAvg - olderAvg

        if difference > 5 {
            return .increasing
        } else if difference < -5 {
            return .decreasing
        } else {
            return .stable
        }
    }
}
