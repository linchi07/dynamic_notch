//
//  window_snap_ghost_animator.swift
//  boringNotch
//

import Cocoa
import SwiftUI
import Defaults

@MainActor
final class WindowAlphaController {
    static let shared = WindowAlphaController()

    private typealias CGSConnectionID = Int32
    private typealias SLSSetWindowAlphaFunc = @convention(c) (CGSConnectionID, CGWindowID, Float) -> CGError
    private typealias SLSGetWindowAlphaFunc = @convention(c) (CGSConnectionID, CGWindowID, UnsafeMutablePointer<Float>) -> CGError
    private typealias SLSMainConnectionIDFunc = @convention(c) () -> CGSConnectionID

    private var setAlphaFunc: SLSSetWindowAlphaFunc?
    private var getAlphaFunc: SLSGetWindowAlphaFunc?
    private var connectionID: CGSConnectionID = 0
    private var hiddenWindowID: CGWindowID?
    private var restoreTask: Task<Void, Never>?

    private init() {
        if let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
            let getMainConn = dlsym(skylight, "SLSMainConnectionID") ?? dlsym(skylight, "CGSMainConnectionID")
            let setAlpha = dlsym(skylight, "SLSSetWindowAlpha") ?? dlsym(skylight, "CGSSetWindowAlpha")
            let getAlpha = dlsym(skylight, "SLSGetWindowAlpha") ?? dlsym(skylight, "CGSGetWindowAlpha")
            if let getMainConn, let setAlpha, let getAlpha {
                let connFunc = unsafeBitCast(getMainConn, to: SLSMainConnectionIDFunc.self)
                self.connectionID = connFunc()
                self.setAlphaFunc = unsafeBitCast(setAlpha, to: SLSSetWindowAlphaFunc.self)
                self.getAlphaFunc = unsafeBitCast(getAlpha, to: SLSGetWindowAlphaFunc.self)
            }
        }
    }

    /// Hides the original target window (alpha = 0.0) with an absolute fail-safe restore timeout.
    @discardableResult
    func hideWindow(_ windowID: CGWindowID, fallbackTimeoutMs: Int = 400) -> Bool {
        restore()
        guard let setAlphaFunc, let getAlphaFunc, connectionID != 0 else {
            NSLog("WindowSnap: SkyLight window alpha API is unavailable")
            return false
        }

        let result = setAlphaFunc(connectionID, windowID, 0.0)
        guard result == .success else {
            NSLog("WindowSnap: unable to hide window %u (CGError %d)", windowID, result.rawValue)
            return false
        }

        // SkyLight accepts requests for foreign windows from an ordinary
        // connection but silently ignores them. A success result therefore is
        // not evidence that the compositor applied the alpha. Fail closed when
        // the value cannot be read back, otherwise the proxy and real window
        // remain visible at the same time and produce a much worse flash.
        var appliedAlpha: Float = 1
        let readResult = getAlphaFunc(connectionID, windowID, &appliedAlpha)
        guard readResult == .success, appliedAlpha <= 0.01 else {
            NSLog(
                "WindowSnap: foreign window alpha was not applied for window %u (CGError %d, alpha %.3f)",
                windowID,
                readResult.rawValue,
                appliedAlpha
            )
            _ = setAlphaFunc(connectionID, windowID, 1.0)
            return false
        }
        hiddenWindowID = windowID

        // Fail-safe guarantee: restore visibility automatically if animation is interrupted
        restoreTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(fallbackTimeoutMs))
            self.restore()
        }
        return true
    }

    /// Restores the original target window to full opacity.
    func restore() {
        restoreTask?.cancel()
        restoreTask = nil
        guard let windowID = hiddenWindowID,
              let setAlphaFunc,
              connectionID != 0 else { return }
        let result = setAlphaFunc(connectionID, windowID, 1.0)
        if result != .success {
            NSLog("WindowSnap: unable to restore window %u alpha (CGError %d)", windowID, result.rawValue)
        }
        hiddenWindowID = nil
    }
}

@MainActor
final class WindowSnapGhostViewModel: ObservableObject {
    @Published var currentRect: CGRect
    @Published var targetRect: CGRect
    @Published var opacity: Double = 1.0

    let icon: NSImage?
    let title: String?
    let onFadeOutStart: () -> Void
    let onCompletion: () -> Void

    private let motionSettleDuration: TimeInterval = 0.32
    private var motionDeadline: TimeInterval = 0
    private var motionStarted = false
    private var placementCompleted = false
    private var handoffTask: Task<Void, Never>?

    init(
        icon: NSImage?,
        title: String?,
        startRect: CGRect,
        targetRect: CGRect,
        onFadeOutStart: @escaping () -> Void,
        onCompletion: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.startRect = startRect
        self.targetRect = targetRect
        self.currentRect = startRect
        self.onFadeOutStart = onFadeOutStart
        self.onCompletion = onCompletion
    }

    private let startRect: CGRect

    func beginMotion(delaySeconds: TimeInterval) {
        motionStarted = true
        motionDeadline = ProcessInfo.processInfo.systemUptime
            + max(0, delaySeconds)
            + motionSettleDuration

        if delaySeconds > 0 {
            withAnimation(
                .interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0)
                    .delay(delaySeconds)
            ) {
                currentRect = targetRect
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0)) {
                currentRect = targetRect
            }
        }
        scheduleHandoffIfReady()
    }

    func updateTarget(_ newTargetRect: CGRect) {
        guard abs(targetRect.width - newTargetRect.width) > 1 ||
              abs(targetRect.height - newTargetRect.height) > 1 ||
              abs(targetRect.origin.x - newTargetRect.origin.x) > 1 ||
              abs(targetRect.origin.y - newTargetRect.origin.y) > 1 else { return }

        self.targetRect = newTargetRect
        motionDeadline = ProcessInfo.processInfo.systemUptime + motionSettleDuration
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0)) {
            self.currentRect = newTargetRect
        }
        scheduleHandoffIfReady()
    }

    func markPlacementCompleted() {
        placementCompleted = true
        scheduleHandoffIfReady()
    }

    func cancel() {
        handoffTask?.cancel()
        handoffTask = nil
    }

    private func scheduleHandoffIfReady() {
        guard motionStarted, placementCompleted else { return }

        handoffTask?.cancel()
        let remaining = max(
            0,
            motionDeadline - ProcessInfo.processInfo.systemUptime
        )
        handoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard let self, !Task.isCancelled else { return }

            onFadeOutStart()
            withAnimation(.easeOut(duration: 0.12)) {
                opacity = 0.0
            }

            try? await Task.sleep(for: .milliseconds(125))
            guard !Task.isCancelled else { return }
            onCompletion()
        }
    }
}

@MainActor
final class WindowSnapGhostAnimator {
    static let shared = WindowSnapGhostAnimator()

    private var activePanel: NSPanel?
    private var activeViewModel: WindowSnapGhostViewModel?
    private var activeScreen: NSScreen?
    private var activeAnimationID: UUID?

    private init() {}

    /// Performs a frosted glass proxy window flight animation from `startFrame` to `targetFrame`.
    /// Frames are expressed in AppKit coordinates (where (0,0) is at bottom-left of the primary display).
    func animate(
        from startFrame: CGRect,
        to targetFrame: CGRect,
        on screen: NSScreen,
        processIdentifier: Int32,
        windowID: CGWindowID? = nil
    ) {
        guard Defaults[.enableWindowSnapGhostAnimation] else { return }

        dismiss()

        let app = NSRunningApplication(processIdentifier: processIdentifier)
        let appIcon = app?.icon
        let appName = app?.localizedName

        let startLocal = appKitToLocalSwiftUI(startFrame, in: screen)
        let targetLocal = appKitToLocalSwiftUI(targetFrame, in: screen)
        let animationID = UUID()

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating + 2
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let viewModel = WindowSnapGhostViewModel(
            icon: appIcon,
            title: appName,
            startRect: startLocal,
            targetRect: targetLocal,
            onFadeOutStart: { [weak self] in
                guard self?.activeAnimationID == animationID else { return }
                // Cross-fade交接：在替身开始淡出的瞬间解除原窗口隐藏，实现平滑显形
                WindowAlphaController.shared.restore()
            },
            onCompletion: { [weak self] in
                guard self?.activeAnimationID == animationID else { return }
                self?.dismiss()
            }
        )

        panel.contentView = NSHostingView(rootView: WindowSnapGhostCanvasView(viewModel: viewModel))
        panel.orderFrontRegardless()
        activePanel = panel
        activeViewModel = viewModel
        activeScreen = screen
        activeAnimationID = animationID

        // Commit the proxy's initial frame before the original window disappears.
        // The real resize remains a single XPC request; no per-frame AX traffic is introduced.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()

        if let windowID {
            let delayMs = Int(Defaults[.windowSnapAnimationStartDelayMs])
            // This is only a crash/hang fail-safe. Normal restoration is driven by
            // placement completion and the final proxy motion below.
            if !WindowAlphaController.shared.hideWindow(
                windowID,
                fallbackTimeoutMs: delayMs + 2_500
            ) {
                // Foreign-window alpha is best-effort. Keep the explicitly
                // experimental proxy animation running when WindowServer denies
                // it; the placement path minimizes visible AX intermediate states.
                NSLog("WindowSnap: continuing proxy animation without hiding window %u", windowID)
            }
        }
    }

    /// Dynamically retargets the flying proxy window to the actual clamped frame accepted by the target application.
    func updateTarget(_ actualAppKitFrame: CGRect, on screen: NSScreen) {
        guard let activeViewModel else { return }
        let currentScreen = activeScreen ?? screen
        let actualLocal = appKitToLocalSwiftUI(actualAppKitFrame, in: currentScreen)
        activeViewModel.updateTarget(actualLocal)
    }

    /// Allows the handoff only after the real window has accepted and settled on
    /// its final frame. The view model additionally waits for the latest proxy motion.
    func completePlacement(_ actualAppKitFrame: CGRect?, on screen: NSScreen) {
        if let actualAppKitFrame {
            updateTarget(actualAppKitFrame, on: screen)
        }
        activeViewModel?.markPlacementCompleted()
    }

    func placementFailed() {
        dismiss()
    }

    func dismiss() {
        WindowAlphaController.shared.restore()
        if let panel = activePanel {
            panel.orderOut(nil)
            activePanel = nil
        }
        activeViewModel?.cancel()
        activeViewModel = nil
        activeScreen = nil
        activeAnimationID = nil
    }

    private func appKitToLocalSwiftUI(_ rect: CGRect, in screen: NSScreen) -> CGRect {
        CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

private struct WindowSnapGhostCanvasView: View {
    @ObservedObject var viewModel: WindowSnapGhostViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.40),
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.20)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 24, x: 0, y: 12)

                VStack(spacing: 8) {
                    if let icon = viewModel.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }

                    if let title = viewModel.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(1)
                            .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 1)
                    }
                }
                .padding(16)
            }
            .frame(width: max(1, viewModel.currentRect.width), height: max(1, viewModel.currentRect.height))
            .position(x: viewModel.currentRect.midX, y: viewModel.currentRect.midY)
            .opacity(viewModel.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let delayMs = Defaults[.windowSnapAnimationStartDelayMs]
            let delaySeconds = max(0.0, delayMs) / 1000.0
            viewModel.beginMotion(delaySeconds: delaySeconds)
        }
    }
}
