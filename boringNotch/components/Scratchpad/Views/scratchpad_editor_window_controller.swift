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
    private let WINDOW_WIDTH: CGFloat = 480
    private let WINDOW_HEIGHT: CGFloat = 580

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

    /// Resolves the screen hosting the notch window to ensure the editor window never opens on the wrong display.
    private func resolveNotchScreen() -> NSScreen {
        if let builtInScreen = NSScreen.supportedBuiltInDisplay {
            return builtInScreen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// Shows the editor window for the given item, using a flight expansion animation from sourceScreenRect.
    func show(item: ScratchpadItem, from sourceScreenRect: NSRect? = nil) {
        currentItemId = item.id

        guard let window = window else { return }

        let editorView = ScratchpadEditorView(itemId: item.id) { [weak self] in
            self?.close()
        }
        window.contentView = NSHostingView(rootView: editorView)

        NSApp.setActivationPolicy(.regular)

        let targetScreen = resolveNotchScreen()
        let visibleFrame = targetScreen.visibleFrame

        let centerX = visibleFrame.midX - WINDOW_WIDTH / 2
        let centerY = visibleFrame.midY - WINDOW_HEIGHT / 2
        let targetFrame = NSRect(x: centerX, y: centerY, width: WINDOW_WIDTH, height: WINDOW_HEIGHT)

        if window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Determine starting frame for the flight animation
        let initialFrame: NSRect
        if let sourceRect = sourceScreenRect, sourceRect.width > 20 && sourceRect.height > 20 {
            initialFrame = sourceRect
        } else {
            // Default anchor: directly below the notch center
            let notchCenterX = targetScreen.frame.midX
            let notchBottomY = targetScreen.frame.maxY - 140
            initialFrame = NSRect(x: notchCenterX - 74, y: notchBottomY, width: 148, height: 82)
        }

        // Prepare initial animation state
        window.setFrame(initialFrame, display: false)
        window.alphaValue = 0.25
        window.orderFrontRegardless()

        // Perform smooth flight expansion animation to center of notch screen
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 1.0
        }

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
