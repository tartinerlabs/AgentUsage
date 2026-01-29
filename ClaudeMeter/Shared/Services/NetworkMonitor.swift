//
//  NetworkMonitor.swift
//  ClaudeMeter
//
//  Monitors network connectivity using NWPathMonitor.
//  Provides real-time updates on network availability.
//

import Foundation
import Network
import OSLog

/// Monitors network connectivity status
@Observable
@MainActor
final class NetworkMonitor {
    /// Shared singleton instance
    static let shared = NetworkMonitor()

    /// Whether the device currently has network connectivity
    private(set) var isConnected: Bool = true

    /// Whether the network is expensive (cellular)
    private(set) var isExpensive: Bool = false

    /// Whether the network is constrained (Low Data Mode)
    private(set) var isConstrained: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.tartinerlabs.ClaudeMeter.NetworkMonitor")

    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let status = path.status
            let isExpensive = path.isExpensive
            let isConstrained = path.isConstrained
            Task { @MainActor [weak self] in
                self?.updateStatus(
                    connected: status == .satisfied,
                    expensive: isExpensive,
                    constrained: isConstrained
                )
            }
        }
        monitor.start(queue: queue)
    }

    private func updateStatus(connected: Bool, expensive: Bool, constrained: Bool) {
        let wasConnected = isConnected
        isConnected = connected
        isExpensive = expensive
        isConstrained = constrained

        if wasConnected && !isConnected {
            Logger.api.info("Network connectivity lost")
        } else if !wasConnected && isConnected {
            Logger.api.info("Network connectivity restored")
        }
    }

    deinit {
        monitor.cancel()
    }
}
