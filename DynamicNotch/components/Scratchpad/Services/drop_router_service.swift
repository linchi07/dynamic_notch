//
//  drop_router_service.swift
//  boringNotch
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DropRouterService {
    static let shared = DropRouterService()

    private init() {}

    /// Checks if the current global drag pasteboard represents plain text content rather than files.
    func isDraggingPlainText() -> Bool {
        let pboard = NSPasteboard(name: .drag)
        guard let types = pboard.types else { return false }

        let hasFileURL = types.contains(.fileURL) ||
            types.contains(NSPasteboard.PasteboardType("public.file-url"))

        let hasText = types.contains(.string) ||
            types.contains(NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier)) ||
            types.contains(NSPasteboard.PasteboardType("public.utf8-plain-text"))

        // If there are files or file URLs, it should route to Shelf
        if hasFileURL {
            return false
        }

        return hasText
    }

    /// Processes incoming dropped providers, separating plain text from file/URL items.
    func handleDrop(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }

        Task { @MainActor in
            var fileURLs: [URL] = []
            var linkURLs: [URL] = []
            var plainTextItems: [String] = []
            var otherProviders: [NSItemProvider] = []

            for provider in providers {
                // First check if it's a file
                if let fileURL = await provider.extractFileURL() {
                    fileURLs.append(fileURL)
                    continue
                }

                // Next check if it's a pure URL link (not text)
                if let url = await provider.extractURL() {
                    if url.isFileURL {
                        fileURLs.append(url)
                    } else {
                        linkURLs.append(url)
                    }
                    continue
                }

                // Check if it's text content (e.g. dragged from a browser or text editor)
                if let text = await provider.extractText() {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        plainTextItems.append(text)
                        continue
                    }
                }

                // Fallback for raw data or other items
                otherProviders.append(provider)
            }

            // Route plain text items to scratchpad
            if !plainTextItems.isEmpty {
                for text in plainTextItems {
                    ScratchpadViewModel.shared.addItem(content: text)
                }
                withAnimation(.smooth(duration: 0.28)) {
                    BoringViewCoordinator.shared.currentView = .scratchpad
                }
            }

            // Route files and links to shelf
            if !fileURLs.isEmpty {
                ShelfStateViewModel.shared.add(urls: fileURLs)
            }
            if !linkURLs.isEmpty {
                ShelfStateViewModel.shared.add(links: linkURLs)
            }
            if !otherProviders.isEmpty {
                ShelfStateViewModel.shared.load(otherProviders)
            }

            if !fileURLs.isEmpty || !linkURLs.isEmpty || !otherProviders.isEmpty {
                if plainTextItems.isEmpty {
                    withAnimation(.smooth(duration: 0.28)) {
                        BoringViewCoordinator.shared.currentView = .shelf
                    }
                }
            }
        }
    }
}
