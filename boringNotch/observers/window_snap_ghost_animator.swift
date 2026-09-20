//
//  window_snap_ghost_animator.swift
//  boringNotch
//

import Cocoa
import SwiftUI
import Defaults

@MainActor
final class WindowSnapGhostAnimator {
    static let shared = WindowSnapGhostAnimator()

    private var activePanel: NSPanel?

    private init() {}

    /// Performs a frosted glass proxy window flight animation from `startFrame` to `targetFrame`.
    /// Frames are expressed in AppKit coordinates (where (0,0) is at bottom-left of the primary display).
    func animate(
        from startFrame: CGRect,
        to targetFrame: CGRect,
        on screen: NSScreen,
        processIdentifier: Int32
    ) {
        guard Defaults[.enableWindowSnapGhostAnimation] else { return }

        dismiss()

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

        let rootView = WindowSnapGhostCanvasView(
            icon: appIcon,
            title: appName,
            startRect: startLocal,
            targetRect: targetLocal
        ) { [weak self] in
            self?.dismiss()
        }

        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        activePanel = panel
    }

    func dismiss() {
        if let panel = activePanel {
            panel.orderOut(nil)
            activePanel = nil
        }
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
    let icon: NSImage?
    let title: String?
    let startRect: CGRect
    let targetRect: CGRect
    let onCompletion: () -> Void

    @State private var currentRect: CGRect
    @State private var opacity: Double = 0.0

    init(
        icon: NSImage?,
        title: String?,
        startRect: CGRect,
        targetRect: CGRect,
        onCompletion: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.startRect = startRect
        self.targetRect = targetRect
        self.onCompletion = onCompletion
        _currentRect = State(initialValue: startRect)
    }

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
                    if let icon {
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

                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(1)
                            .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 1)
                    }
                }
                .padding(16)
            }
            .frame(width: max(1, currentRect.width), height: max(1, currentRect.height))
            .position(x: currentRect.midX, y: currentRect.midY)
            .opacity(opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let delayMs = Defaults[.windowSnapAnimationStartDelayMs]
            let delaySeconds = max(0.0, delayMs) / 1000.0

            withAnimation(.easeOut(duration: 0.08)) {
                opacity = 1.0
            }

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

            Task {
                let totalWaitMs = Int(delayMs) + 270
                try? await Task.sleep(for: .milliseconds(totalWaitMs))
                withAnimation(.easeOut(duration: 0.09)) {
                    opacity = 0.0
                }
                try? await Task.sleep(for: .milliseconds(95))
                onCompletion()
            }
        }
    }
}
