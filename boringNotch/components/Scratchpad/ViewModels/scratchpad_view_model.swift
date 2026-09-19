//
//  scratchpad_view_model.swift
//  boringNotch
//

import AppKit
import Foundation

@MainActor
final class ScratchpadViewModel: ObservableObject {
    static let shared = ScratchpadViewModel()

    @Published private(set) var items: [ScratchpadItem] = [] {
        didSet {
            persistenceService.save(items)
        }
    }

    private let persistenceService: ScratchpadPersistenceService

    var isEmpty: Bool {
        items.isEmpty
    }

    init(persistenceService: ScratchpadPersistenceService = .shared) {
        self.persistenceService = persistenceService
        self.items = persistenceService.load()
    }

    @discardableResult
    func addItem(content: String, title: String? = nil) -> ScratchpadItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let item = ScratchpadItem(title: title, content: content)
            items.insert(item, at: 0)
            return item
        }

        // Avoid exact duplicate at the top
        if let first = items.first, first.content == content && first.title == title {
            return first
        }

        let item = ScratchpadItem(title: title, content: content)
        items.insert(item, at: 0)
        return item
    }

    func updateItem(id: UUID, title: String? = nil, content: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].title = (trimmedTitle?.isEmpty ?? true) ? nil : trimmedTitle
        items[index].content = content
        items[index].updatedAt = Date()
    }

    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func removeItem(_ item: ScratchpadItem) {
        removeItem(id: item.id)
    }

    func copyItem(_ item: ScratchpadItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
    }

    func item(for id: UUID) -> ScratchpadItem? {
        items.first { $0.id == id }
    }
}
