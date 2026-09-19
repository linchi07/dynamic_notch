//
//  scratchpad_editor_window_controller.swift
//  boringNotch
//

import AppKit
import SwiftUI

@MainActor
final class ScratchpadEditorWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ScratchpadEditorWindowController()

    private var currentItemId: UUID?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.title = "Text Note"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("ScratchpadEditorWindow")
        window.delegate = self
    }

    func show(item: ScratchpadItem) {
        currentItemId = item.id

        guard let window = window else { return }

        let editorView = ScratchpadEditorView(itemId: item.id) { [weak self] in
            self?.close()
        }
        window.contentView = NSHostingView(rootView: editorView)

        NSApp.setActivationPolicy(.regular)

        if window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }

        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    override func close() {
        super.close()
        currentItemId = nil
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }

    func windowWillClose(_ notification: Notification) {
        currentItemId = nil
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }
}
