//
//  UsageHistory.swift
//  ClaudeMeterKit
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

    /// Timestamp when this record was last updated
    public let updatedAt: Date

    public init(
        date: Date,
        peakSessionUtilization: Double,
        peakOpusUtilization: Double,
        peakSonnetUtilization: Double?,
        updatedAt: Date = Date()
    ) {
        self.date = date
        self.peakSessionUtilization = peakSessionUtilization
        self.peakOpusUtilization = peakOpusUtilization
        self.peakSonnetUtilization = peakSonnetUtilization
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

            records.append(DailyUsageRecord(
                date: normalizedDate,
                peakSessionUtilization: baseSession + Double.random(in: 0...15),
                peakOpusUtilization: baseOpus + Double.random(in: 0...10),
                peakSonnetUtilization: baseSonnet + Double.random(in: 0...10),
                updatedAt: date
            ))
        }

        return UsageHistory(records: records)
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

    /// Calculate trend from recent records
    public static func calculate(from records: [DailyUsageRecord], keyPath: KeyPath<DailyUsageRecord, Double>) -> UsageTrend {
        guard records.count >= 2 else { return .stable }

        let recent = records.suffix(3)
        let older = records.dropLast(min(3, records.count / 2)).suffix(3)

        guard !recent.isEmpty && !older.isEmpty else { return .stable }

        let recentAvg = recent.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(recent.count)
        let olderAvg = older.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(older.count)

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
