//
//  scratchpad_item.swift
//  boringNotch
//

import Foundation

/// Represents a single text record stored in the scratchpad.
struct ScratchpadItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Title line or preview snippet of the note.
    var previewTitle: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Empty Note"
        }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if firstLine.count > 40 {
            return String(firstLine.prefix(37)) + "..."
        }
        return firstLine
    }

    /// Subtitle or body preview of the note content.
    var previewSnippet: String {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else {
            return previewTitle
        }
        return lines.dropFirst().joined(separator: " ")
    }

    /// Formatted timestamp for compact card display.
    var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: createdAt)
    }
}
