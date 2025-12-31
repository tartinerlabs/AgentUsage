//
//  Item.swift
//  ClaudeMeter
//
//  Created by Ru Chern Chong on 31/12/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
