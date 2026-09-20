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
            var plainTextItems: [String] = []
            var shelfProviders: [NSItemProvider] = []

            for provider in providers {
                // First check if it's a file
                if let fileURL = await provider.extractFileURL() {
                    shelfProviders.append(provider)
                    continue
                }

                // Next check if it's a pure URL link (not text)
                if let url = await provider.extractURL(), !url.isFileURL {
                    shelfProviders.append(provider)
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
                shelfProviders.append(provider)
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

            // Route files/links to shelf
            if !shelfProviders.isEmpty {
                ShelfStateViewModel.shared.load(shelfProviders)
                if plainTextItems.isEmpty {
                    withAnimation(.smooth(duration: 0.28)) {
                        BoringViewCoordinator.shared.currentView = .shelf
                    }
                }
            }
        }
    }
}
