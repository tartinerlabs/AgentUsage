//
//  ImportedFile.swift
//  ClaudeMeter
//

import Foundation
import SwiftData

/// Tracks file import state for incremental JSONL reading
@Model
final class ImportedFile {
    /// Unique file path
    @Attribute(.unique) var path: String

    /// Byte offset where we stopped reading (resume from here)
    var lastProcessedByteOffset: Int64

    /// File size at last import (detect truncation if current < saved)
    var fileSize: Int64

    /// Last modification date of the file
    var lastModified: Date

    init(path: String, lastProcessedByteOffset: Int64 = 0, fileSize: Int64 = 0, lastModified: Date = .now) {
        self.path = path
        self.lastProcessedByteOffset = lastProcessedByteOffset
        self.fileSize = fileSize
        self.lastModified = lastModified
    }

    /// Check if file needs re-import based on current file attributes
    func needsImport(currentSize: Int64, currentModified: Date) -> ImportAction {
        if currentSize < fileSize {
            // File was truncated or rotated - reset and re-import
            return .resetAndImport
        } else if currentSize > fileSize || currentModified > lastModified {
            // File has new content - incremental import
            return .incrementalImport
        } else {
            // No changes
            return .skip
        }
    }

    enum ImportAction {
        case skip
        case incrementalImport
        case resetAndImport
    }
}
