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
    private typealias SLSMainConnectionIDFunc = @convention(c) () -> CGSConnectionID

    private var setAlphaFunc: SLSSetWindowAlphaFunc?
    private var connectionID: CGSConnectionID = 0
    private var hiddenWindowID: CGWindowID?
    private var restoreTask: Task<Void, Never>?

    private init() {
        if let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
            let getMainConn = dlsym(skylight, "SLSMainConnectionID") ?? dlsym(skylight, "CGSMainConnectionID")
            let setAlpha = dlsym(skylight, "SLSSetWindowAlpha") ?? dlsym(skylight, "CGSSetWindowAlpha")
            if let getMainConn, let setAlpha {
                let connFunc = unsafeBitCast(getMainConn, to: SLSMainConnectionIDFunc.self)
                self.connectionID = connFunc()
                self.setAlphaFunc = unsafeBitCast(setAlpha, to: SLSSetWindowAlphaFunc.self)
            }
        }
    }

    /// Hides the original target window (alpha = 0.0) with an absolute fail-safe restore timeout.
    func hideWindow(_ windowID: CGWindowID, fallbackTimeoutMs: Int = 400) {
        restore()
        guard Defaults[.hideOriginalWindowDuringSnap],
              let setAlphaFunc,
              connectionID != 0 else { return }

        hiddenWindowID = windowID
        _ = setAlphaFunc(connectionID, windowID, 0.0)

        // Fail-safe guarantee: restore visibility automatically if animation is interrupted
        restoreTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(fallbackTimeoutMs))
            self.restore()
        }
    }

    /// Restores the original target window to full opacity.
    func restore() {
        restoreTask?.cancel()
        restoreTask = nil
        guard let windowID = hiddenWindowID,
              let setAlphaFunc,
              connectionID != 0 else { return }
        _ = setAlphaFunc(connectionID, windowID, 1.0)
        hiddenWindowID = nil
    }
}

@MainActor
final class WindowSnapGhostViewModel: ObservableObject {
    @Published var currentRect: CGRect
    @Published var targetRect: CGRect
    @Published var opacity: Double = 0.0

    let icon: NSImage?
    let title: String?
    let onFadeOutStart: () -> Void
    let onCompletion: () -> Void

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

    func updateTarget(_ newTargetRect: CGRect) {
        guard abs(targetRect.width - newTargetRect.width) > 1 ||
              abs(targetRect.height - newTargetRect.height) > 1 ||
              abs(targetRect.origin.x - newTargetRect.origin.x) > 1 ||
              abs(targetRect.origin.y - newTargetRect.origin.y) > 1 else { return }

        self.targetRect = newTargetRect
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0)) {
            self.currentRect = newTargetRect
        }
    }
}

@MainActor
final class WindowSnapGhostAnimator {
    static let shared = WindowSnapGhostAnimator()

    private var activePanel: NSPanel?
    private var activeViewModel: WindowSnapGhostViewModel?
    private var activeScreen: NSScreen?

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

        if let windowID {
            let delayMs = Int(Defaults[.windowSnapAnimationStartDelayMs])
            // Generous fallback margin (delay + 800ms) to ensure window never unhides prematurely
            WindowAlphaController.shared.hideWindow(windowID, fallbackTimeoutMs: delayMs + 800)
        }

        let app = NSRunningApplication(processIdentifier: processIdentifier)
        let appIcon = app?.icon
        let appName = app?.localizedName

        let startLocal = appKitToLocalSwiftUI(startFrame, in: screen)
        let targetLocal = appKitToLocalSwiftUI(targetFrame, in: screen)

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
            onFadeOutStart: {
                // Cross-fade交接：在替身开始淡出的瞬间解除原窗口隐藏，实现平滑显形
                WindowAlphaController.shared.restore()
            },
            onCompletion: { [weak self] in
                self?.dismiss()
            }
        )

        panel.contentView = NSHostingView(rootView: WindowSnapGhostCanvasView(viewModel: viewModel))
        panel.orderFrontRegardless()
        activePanel = panel
        activeViewModel = viewModel
        activeScreen = screen
    }

    /// Dynamically retargets the flying proxy window to the actual clamped frame accepted by the target application.
    func updateTarget(_ actualAppKitFrame: CGRect, on screen: NSScreen) {
        guard let activeViewModel else { return }
        let currentScreen = activeScreen ?? screen
        let actualLocal = appKitToLocalSwiftUI(actualAppKitFrame, in: currentScreen)
        activeViewModel.updateTarget(actualLocal)
    }

    func dismiss() {
        WindowAlphaController.shared.restore()
        if let panel = activePanel {
            panel.orderOut(nil)
            activePanel = nil
        }
        activeViewModel = nil
        activeScreen = nil
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

            withAnimation(.easeOut(duration: 0.08)) {
                viewModel.opacity = 1.0
            }

            if delaySeconds > 0 {
                withAnimation(
                    .interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0)
                    .delay(delaySeconds)
                ) {
                    viewModel.currentRect = viewModel.targetRect
                }
            } else {
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0)) {
                    viewModel.currentRect = viewModel.targetRect
                }
            }

            Task {
                let totalWaitMs = Int(delayMs) + 270
                try? await Task.sleep(for: .milliseconds(totalWaitMs))

                // 到达终点后，在淡出开始的瞬间解除原窗口隐藏
                viewModel.onFadeOutStart()

                withAnimation(.easeOut(duration: 0.12)) {
                    viewModel.opacity = 0.0
                }
                try? await Task.sleep(for: .milliseconds(125))
                viewModel.onCompletion()
            }
        }
    }
}
