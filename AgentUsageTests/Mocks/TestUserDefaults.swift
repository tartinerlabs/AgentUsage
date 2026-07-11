//
//  TestUserDefaults.swift
//  AgentUsageTests
//

import Foundation

final class TestUserDefaults {
    let defaults: UserDefaults

    private let suiteName: String

    init() {
        suiteName = "com.tartinerlabs.AgentUsageTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults suite")
        }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
