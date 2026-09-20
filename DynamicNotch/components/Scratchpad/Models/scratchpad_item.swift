//
//  scratchpad_item.swift
//  boringNotch
//

import Foundation

/// Represents a single text record stored in the scratchpad.
struct ScratchpadItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String?
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String? = nil,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = (trimmedTitle?.isEmpty ?? true) ? nil : trimmedTitle
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Whether this note has an explicit user-defined title.
    var hasCustomTitle: Bool {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !title.isEmpty
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
