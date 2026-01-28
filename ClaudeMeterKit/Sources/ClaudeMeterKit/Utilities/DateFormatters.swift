//
//  DateFormatters.swift
//  ClaudeMeterKit
//
//  Shared date formatting utilities to avoid duplication across views
//

import Foundation

/// Shared date formatting utilities
public enum DateFormatters {
    /// Format a date as a human-readable relative description
    /// - Parameters:
    ///   - past: The past date to describe
    ///   - current: The current reference date (defaults to now)
    /// - Returns: A string like "just now", "5m ago", "2h ago"
    public static func relativeDescription(from past: Date, to current: Date = Date()) -> String {
        let delta = current.timeIntervalSince(past)
        if delta < 1.5 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: past, relativeTo: current)
    }
}
