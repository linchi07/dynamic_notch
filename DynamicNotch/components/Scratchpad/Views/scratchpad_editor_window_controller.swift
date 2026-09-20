//
//  scratchpad_editor_window_controller.swift
//  boringNotch
//

import AppKit
import SwiftUI

/// A layer-only window silhouette used during the flight. The real editor is
/// already laid out at its final size and never participates in the resize.
private final class ScratchpadFlightView: NSView {
    private let headerLayer = CALayer()
    private let titleLineLayer = CALayer()
    private let bodyLineLayers = (0..<4).map { _ in CALayer() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.masksToBounds = true

        headerLayer.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        titleLineLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.30).cgColor
        titleLineLayer.cornerRadius = 2
        layer?.addSublayer(headerLayer)
        layer?.addSublayer(titleLineLayer)

        for bodyLineLayer in bodyLineLayers {
            bodyLineLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.13).cgColor
            bodyLineLayer.cornerRadius = 2
            layer?.addSublayer(bodyLineLayer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let scale = min(1, max(0.45, bounds.width / 480))
        let horizontalInset = 16 * scale
        let headerHeight = min(54 * scale, bounds.height * 0.36)
        headerLayer.frame = NSRect(
            x: 0,
            y: bounds.height - headerHeight,
            width: bounds.width,
            height: headerHeight
        )
        titleLineLayer.frame = NSRect(
            x: horizontalInset,
            y: bounds.height - headerHeight / 2 - 2,
            width: max(20, bounds.width * 0.42),
            height: max(2, 4 * scale)
        )

        for (index, bodyLineLayer) in bodyLineLayers.enumerated() {
            let lineY = bounds.height - headerHeight - CGFloat(index + 1) * 24 * scale
            bodyLineLayer.frame = NSRect(
                x: horizontalInset,
                y: max(horizontalInset, lineY),
                width: max(20, bounds.width * (index == 3 ? 0.48 : 0.72)),
                height: max(2, 4 * scale)
            )
        }
        CATransaction.commit()
    }
}

@MainActor
final class ScratchpadEditorWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ScratchpadEditorWindowController()

    private var currentItemId: UUID?
    private let WINDOW_WIDTH: CGFloat = 480
    private let WINDOW_HEIGHT: CGFloat = 580
    private var flightWindow: NSPanel?
    private var flightGeneration = UUID()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 440, height: 480)
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

    /// Shows the editor as an independent window. A lightweight proxy flies from
    /// the card while the real editor remains at its final size and fades in once.
    func show(
        item: ScratchpadItem,
        from sourceScreenRect: NSRect? = nil,
        onPresented: (() -> Void)? = nil
    ) {
        currentItemId = item.id

        guard let window = window else { return }

        let editorView = ScratchpadEditorView(itemId: item.id) { [weak self] in
            self?.close()
        }

        let targetScreen = resolveNotchScreen()
        let visibleFrame = targetScreen.visibleFrame

        let centerX = visibleFrame.midX - WINDOW_WIDTH / 2
        let centerY = visibleFrame.midY - WINDOW_HEIGHT / 2
        let targetFrame = NSRect(x: centerX, y: centerY, width: WINDOW_WIDTH, height: WINDOW_HEIGHT)

        if window.isVisible {
            window.contentView = NSHostingView(rootView: editorView)
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            onPresented?()
            return
        }

        let initialFrame: NSRect
        if let sourceScreenRect,
           sourceScreenRect.width > 20,
           sourceScreenRect.height > 20 {
            initialFrame = sourceScreenRect
        } else {
            let notchCenterX = targetScreen.frame.midX
            let notchBottomY = targetScreen.frame.maxY - 140
            initialFrame = NSRect(
                x: notchCenterX - 74,
                y: notchBottomY,
                width: 148,
                height: 82
            )
        }

        cancelFlight()
        flightGeneration = UUID()
        let generation = flightGeneration

        NSApp.setActivationPolicy(.regular)
        let hostingView = NSHostingView(rootView: editorView)
        hostingView.alphaValue = 0
        window.contentView = hostingView
        window.setFrame(targetFrame, display: false)
        window.alphaValue = 1

        let flightWindow = makeFlightWindow(frame: initialFrame)
        self.flightWindow = flightWindow
        flightWindow.alphaValue = 0.72
        flightWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.16,
                1.0,
                0.3,
                1.0
            )
            context.allowsImplicitAnimation = true
            flightWindow.animator().setFrame(targetFrame, display: true)
            flightWindow.animator().alphaValue = 1
        } completionHandler: { [weak self, weak window, weak flightWindow] in
            guard let self, let window, let flightWindow,
                  self.flightGeneration == generation
            else { return }

            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hostingView.animator().alphaValue = 1
                flightWindow.animator().alphaValue = 0
            } completionHandler: { [weak self, weak window, weak flightWindow] in
                guard let self, self.flightGeneration == generation else { return }
                flightWindow?.orderOut(nil)
                self.flightWindow = nil
                window?.makeKeyAndOrderFront(nil)
                onPresented?()
            }
        }
    }

    private func makeFlightWindow(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .mainMenu + 4
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = ScratchpadFlightView(frame: NSRect(origin: .zero, size: frame.size))
        return panel
    }

    private func cancelFlight() {
        flightGeneration = UUID()
        flightWindow?.orderOut(nil)
        flightWindow = nil
    }

    override func close() {
        cancelFlight()
        super.close()
        currentItemId = nil
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }

    func windowWillClose(_ notification: Notification) {
        cancelFlight()
        currentItemId = nil
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }
}
