//
//  scratchpad_persistence_service.swift
//  boringNotch
//

import Foundation

final class ScratchpadPersistenceService {
    static let shared = ScratchpadPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil) {
        let fm = FileManager.default
        let baseDir: URL
        if let directoryURL = directoryURL {
            baseDir = directoryURL
        } else {
            let support = try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            baseDir = (support ?? fm.temporaryDirectory)
                .appendingPathComponent("boringNotch", isDirectory: true)
                .appendingPathComponent("Scratchpad", isDirectory: true)
        }

        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        fileURL = baseDir.appendingPathComponent("items.json")

        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [ScratchpadItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let items = try? decoder.decode([ScratchpadItem].self, from: data) {
            return items
        }

        // Fallback: parse array items individually to recover partially valid entries
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }

        var validItems: [ScratchpadItem] = []
        for jsonItem in jsonArray {
            if let itemData = try? JSONSerialization.data(withJSONObject: jsonItem),
               let item = try? decoder.decode(ScratchpadItem.self, from: itemData) {
                validItems.append(item)
            }
        }
        return validItems
    }

    func save(_ items: [ScratchpadItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save scratchpad items: \(error.localizedDescription)")
        }
    }
}
