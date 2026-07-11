//
//  DailyUsageRecordEntity.swift
//  AgentUsage
//

import Foundation
import SwiftData
import AgentUsageKit

/// SwiftData-backed daily usage history row.
@Model
final class DailyUsageRecordEntity {
    @Attribute(.unique) var id: String
    var date: Date
    var peakSessionUtilization: Double
    var peakOpusUtilization: Double
    var peakSonnetUtilization: Double?
    var peakFableUtilization: Double?
    var updatedAt: Date

    init(record: DailyUsageRecord) {
        self.id = Self.id(for: record.date)
        self.date = Calendar.current.startOfDay(for: record.date)
        self.peakSessionUtilization = record.peakSessionUtilization
        self.peakOpusUtilization = record.peakOpusUtilization
        self.peakSonnetUtilization = record.peakSonnetUtilization
        self.peakFableUtilization = record.peakFableUtilization
        self.updatedAt = record.updatedAt
    }

    var record: DailyUsageRecord {
        DailyUsageRecord(
            date: date,
            peakSessionUtilization: peakSessionUtilization,
            peakOpusUtilization: peakOpusUtilization,
            peakSonnetUtilization: peakSonnetUtilization,
            peakFableUtilization: peakFableUtilization,
            updatedAt: updatedAt
        )
    }

    func update(with record: DailyUsageRecord) {
        date = Calendar.current.startOfDay(for: record.date)
        id = Self.id(for: date)
        peakSessionUtilization = record.peakSessionUtilization
        peakOpusUtilization = record.peakOpusUtilization
        peakSonnetUtilization = record.peakSonnetUtilization
        peakFableUtilization = record.peakFableUtilization
        updatedAt = record.updatedAt
    }

    static func id(for date: Date) -> String {
        String(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))
    }
}
