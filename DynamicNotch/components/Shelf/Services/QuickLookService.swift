//
//  QuickLookService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import Foundation
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Manages and resolves the exact screen coordinates of Shelf items to drive native zoom animations.
@MainActor
final class ShelfItemScreenPositionManager {
    static let shared = ShelfItemScreenPositionManager()

    private var registeredFrames: [UUID: NSRect] = [:]

    func register(id: UUID, screenFrame: NSRect) {
        guard screenFrame.width > 0 && screenFrame.height > 0 else { return }
        registeredFrames[id] = screenFrame
    }

    func unregister(id: UUID) {
        registeredFrames.removeValue(forKey: id)
    }

    /// Resolves the screen frame for a given item, falling back to a geometric calculation if untracked.
    func screenFrame(for item: ShelfItem) -> NSRect {
        if let frame = registeredFrames[item.id] {
            return frame
        }
        return calculateGeometricFrame(for: item)
    }

    /// Resolves the screen frame for the primary item in a list of URLs.
    func screenFrame(for urls: [URL]) -> NSRect {
        let items = ShelfStateViewModel.shared.items
        if let matchingItem = items.first(where: { item in
            urls.contains(where: { $0 == item.fileURL })
        }) {
            return screenFrame(for: matchingItem)
        }

        // Default notch area on the notch screen
        let screen = NSScreen.supportedBuiltInDisplay ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        return NSRect(
            x: screen.frame.midX - 41,
            y: screen.frame.maxY - 140,
            width: 82,
            height: 82
        )
    }

    /// Accurately computes the screen position based on the notch geometry and the item's index in the shelf.
    func calculateGeometricFrame(for item: ShelfItem) -> NSRect {
        let screen = NSScreen.supportedBuiltInDisplay ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let items = ShelfStateViewModel.shared.items
        let index = items.firstIndex(where: { $0.id == item.id }) ?? 0

        // Layout constants from ShelfView:
        // Container height: NOTCH_PANEL_CONTAINER_HEIGHT (~130pt)
        // FileShareView: width ~120pt, spacing: 12pt
        // Cards: width 82, spacing 8, padding 4
        let totalItemsCount = max(1, items.count)
        let totalCardsWidth = CGFloat(totalItemsCount) * 82.0 + CGFloat(totalItemsCount - 1) * 8.0
        let shelfContentWidth = 120.0 + 12.0 + totalCardsWidth + 8.0

        let shelfLeftX = screen.frame.midX - (shelfContentWidth / 2.0)
        let cardX = shelfLeftX + 120.0 + 12.0 + 4.0 + CGFloat(index) * (82.0 + 8.0)
        let cardY = screen.frame.maxY - 145.0

        return NSRect(x: cardX, y: cardY, width: 82, height: 82)
    }

    /// Retrieves the transition image for the preview item if available.
    func transitionImage(for urls: [URL]) -> NSImage? {
        let items = ShelfStateViewModel.shared.items
        if let matchingItem = items.first(where: { item in
            urls.contains(where: { $0 == item.fileURL })
        }) {
            return matchingItem.icon
        }
        return nil
    }
}

final class QuickLookHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class QuickLookHostController: NSWindowController, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookHostController()

    private var previewURLs: [URL] = []
    private var isControlling: Bool = false
    private weak var service: QuickLookService?

    private var currentSourceFrame: NSRect = .zero
    private var currentTransitionImage: NSImage?

    init() {
        let hostWindow = QuickLookHostWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.isOpaque = false
        hostWindow.backgroundColor = .clear
        hostWindow.alphaValue = 0.0
        hostWindow.ignoresMouseEvents = true
        hostWindow.collectionBehavior = [.canJoinAllSpaces, .transient]
        super.init(window: hostWindow)
        hostWindow.windowController = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(service: QuickLookService) {
        self.service = service
    }

    // MARK: - QLPreviewPanelController

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        isControlling = true
        panel.delegate = self
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        isControlling = false
        panel.delegate = nil
        panel.dataSource = nil
        window?.orderOut(nil)
        service?.handlePanelDidClose()
    }

    // MARK: - Panel Actions

    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.previewURLs = urls

        // 1. Calculate relative/absolute screen frame of the selected file in notch shelf
        let sourceRect = ShelfItemScreenPositionManager.shared.screenFrame(for: urls)
        self.currentSourceFrame = sourceRect
        self.currentTransitionImage = ShelfItemScreenPositionManager.shared.transitionImage(for: urls)

        // 2. Position host window at that exact location on the notch screen
        guard let window = self.window else { return }
        window.setFrame(sourceRect, display: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 3. Display panel - native window server zooms smoothly from sourceRect
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.updateController()
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    func updateURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.previewURLs = urls

        let sourceRect = ShelfItemScreenPositionManager.shared.screenFrame(for: urls)
        self.currentSourceFrame = sourceRect
        self.currentTransitionImage = ShelfItemScreenPositionManager.shared.transitionImage(for: urls)

        if let panel = QLPreviewPanel.shared(), panel.isVisible && isControlling {
            panel.reloadData()
            panel.currentPreviewItemIndex = 0
        }
    }

    func hide() {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            endPreviewPanelControl(panel)
        }
        window?.orderOut(nil)
    }

    var isPanelVisible: Bool {
        guard let panel = QLPreviewPanel.shared() else { return false }
        return panel.isVisible && isControlling
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        return currentSourceFrame
    }

    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        if let image = currentTransitionImage {
            return image
        }
        return nil
    }
}

@MainActor
final class QuickLookService: ObservableObject {
    static let shared = QuickLookService()

    @Published var urls: [URL] = []
    @Published var selectedURL: URL?
    @Published var isQuickLookOpen: Bool = false

    private var accessingURLs: [URL] = []
    private let hostController = QuickLookHostController.shared

    init() {
        hostController.bind(service: self)
    }

    func show(urls: [URL], selectFirst: Bool = true, slideshow: Bool = false) {
        guard !urls.isEmpty else { return }
        stopAccessingCurrentURLs()

        accessingURLs = urls.filter { url in
            if url.isFileURL {
                return url.startAccessingSecurityScopedResource()
            }
            return true
        }

        self.urls = accessingURLs
        self.isQuickLookOpen = true
        if selectFirst {
            self.selectedURL = accessingURLs.first
        }

        hostController.show(urls: accessingURLs)
    }

    func hide() {
        hostController.hide()
        stopAccessingCurrentURLs()
        selectedURL = nil
        urls.removeAll()
        isQuickLookOpen = false
    }

    func toggle(urls: [URL]) {
        if isQuickLookOpen || hostController.isPanelVisible {
            hide()
        } else {
            show(urls: urls, selectFirst: true)
        }
    }

    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen, !urls.isEmpty else { return }
        stopAccessingCurrentURLs()

        accessingURLs = urls.filter { url in
            if url.isFileURL {
                return url.startAccessingSecurityScopedResource()
            }
            return true
        }

        self.urls = accessingURLs
        self.selectedURL = accessingURLs.first
        hostController.updateURLs(accessingURLs)
    }

    func handlePanelDidClose() {
        stopAccessingCurrentURLs()
        selectedURL = nil
        urls.removeAll()
        isQuickLookOpen = false
    }

    private func stopAccessingCurrentURLs() {
        for url in accessingURLs where url.isFileURL {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
    }
}

@MainActor
final class ShelfKeyboardMonitor {
    static let shared = ShelfKeyboardMonitor()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let self = self, self.handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }

        guard BoringViewCoordinator.shared.currentView == .shelf else { return false }

        let selection = ShelfSelectionModel.shared
        guard !selection.selectedIDs.isEmpty else { return false }

        if !QuickLookService.shared.isQuickLookOpen {
            let mouseLoc = NSEvent.mouseLocation
            if let screen = NSScreen.supportedBuiltInDisplay ?? NSScreen.main {
                let notchArea = NSRect(
                    x: screen.frame.midX - 450,
                    y: screen.frame.maxY - 300,
                    width: 900,
                    height: 300
                )
                guard notchArea.contains(mouseLoc) else { return false }
            }
        }

        let selectedItems = selection.selectedItems(in: ShelfStateViewModel.shared.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }

        guard !urls.isEmpty else { return false }

        QuickLookService.shared.toggle(urls: urls)
        return true
    }
}

struct QuickLookPresenter: ViewModifier {
    @ObservedObject var service: QuickLookService

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func quickLookPresenter(using service: QuickLookService) -> some View {
        self.modifier(QuickLookPresenter(service: service))
    }
}
