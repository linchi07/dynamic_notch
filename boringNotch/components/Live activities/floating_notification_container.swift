//
//  floating_notification_container.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Physical lifecycle stages for notification pop-in ejection and retraction beneath the notch
enum NotificationEjectionPhase {
    case hidden             // Stage 0: Tucked behind notch
    case ejectedStage1      // Stage 1: Ejected downward from behind notch, initial stretch
    case fullyExpanded      // Stage 2: Full horizontal elongation & vertical expansion
    case retractingStage1   // Retract Stage 1: Content fades out, horizontal snap-in narrowing
    case retractedStage2    // Retract Stage 2: Slid upward back behind notch, fully vanished
}

/// Metrics and layout constants for floating notifications
private enum FloatingNotificationMetrics {
    static let HIDDEN_OFFSET_Y: CGFloat = -54
    static let CORNER_RADIUS: CGFloat = 14
}

/// Specialized floating container for strong notifications and alerts.
/// Features a distinctive two-stage pop-down ejection and two-stage upward retraction.
struct FloatingNotificationContainer<Content: View>: View {
    @Binding var isPresented: Bool
    var autoDismissAfter: TimeInterval? = 4.0
    var onFullExpand: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    let content: (Bool) -> Content

    @State private var phase: NotificationEjectionPhase = .hidden
    @State private var isContentVisible: Bool = false
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var ejectionTask: Task<Void, Never>?
    @State private var retractionTask: Task<Void, Never>?

    init(
        isPresented: Binding<Bool>,
        autoDismissAfter: TimeInterval? = 4.0,
        onFullExpand: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Bool) -> Content
    ) {
        self._isPresented = isPresented
        self.autoDismissAfter = autoDismissAfter
        self.onFullExpand = onFullExpand
        self.onDismiss = onDismiss
        self.content = content
    }

    // Dynamic scale and offset based on ejection and retraction phases
    private var phaseScaleX: CGFloat {
        switch phase {
        case .hidden, .retractedStage2:
            return 0.35
        case .ejectedStage1, .retractingStage1:
            return 0.65
        case .fullyExpanded:
            return 1.0
        }
    }

    private var phaseScaleY: CGFloat {
        switch phase {
        case .hidden:
            return 0.58
        case .ejectedStage1:
            return 0.88
        case .fullyExpanded:
            return 1.0
        case .retractingStage1:
            return 0.85
        case .retractedStage2:
            return 0.50
        }
    }

    private var phaseOffsetY: CGFloat {
        switch phase {
        case .hidden, .retractedStage2:
            return FloatingNotificationMetrics.HIDDEN_OFFSET_Y
        case .ejectedStage1, .fullyExpanded, .retractingStage1:
            return 0
        }
    }

    private var phaseOpacity: Double {
        switch phase {
        case .hidden, .retractedStage2:
            return 0.0
        case .ejectedStage1, .fullyExpanded, .retractingStage1:
            return 1.0
        }
    }

    var body: some View {
        content(isContentVisible)
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(0.88)
                    Color(white: 0.16)
                        .opacity(0.60)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: FloatingNotificationMetrics.CORNER_RADIUS, style: .continuous))
            // Ambient hover glow to pop out from wallpaper
            .shadow(color: Color.white.opacity(0.14), radius: 6, x: 0, y: 0)
            .shadow(color: Color.white.opacity(0.06), radius: 14, x: 0, y: 0)
            // Spatial drop shadow
            .shadow(color: Color.black.opacity(0.38), radius: 14, x: 0, y: 6)
            .scaleEffect(x: phaseScaleX, y: phaseScaleY, anchor: .top)
            .offset(y: phaseOffsetY)
            .opacity(phaseOpacity)
            .onAppear {
                if isPresented {
                    startTwoStageEjection()
                }
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    startTwoStageEjection()
                } else if phase == .fullyExpanded || phase == .ejectedStage1 {
                    startTwoStageRetraction()
                }
            }
    }

    // MARK: - Two-Stage Ejection Sequence
    private func startTwoStageEjection() {
        retractionTask?.cancel()
        autoDismissTask?.cancel()
        ejectionTask?.cancel()

        phase = .hidden
        isContentVisible = false

        // Stage 1: Eject downward from behind notch with initial stretch
        withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
            phase = .ejectedStage1
        }

        ejectionTask = Task { @MainActor in
            // Stage 2: Substantial horizontal elongation & vertical expansion
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, isPresented else { return }

            withAnimation(.interpolatingSpring(mass: 0.55, stiffness: 210, damping: 13)) {
                phase = .fullyExpanded
            }

            // Stage 3: After elongation settles, fade in inner content
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, isPresented else { return }

            withAnimation(.easeInOut(duration: 0.18)) {
                isContentVisible = true
            }
            onFullExpand?()

            // Optional auto dismiss countdown
            if let duration = autoDismissAfter {
                scheduleAutoDismiss(after: duration)
            }
        }
    }

    // MARK: - Two-Stage Retraction Sequence
    private func startTwoStageRetraction() {
        ejectionTask?.cancel()
        autoDismissTask?.cancel()
        retractionTask?.cancel()

        // Retraction Stage 1: Content fades out immediately while body narrows horizontally
        withAnimation(.easeInOut(duration: 0.12)) {
            isContentVisible = false
        }

        withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
            phase = .retractingStage1
        }

        retractionTask = Task { @MainActor in
            // Retraction Stage 2: Slide upward back behind notch into hiding
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
                phase = .retractedStage2
            }

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }

            phase = .hidden
            isPresented = false
            onDismiss?()
        }
    }

    private func scheduleAutoDismiss(after duration: TimeInterval) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            guard !Task.isCancelled, isPresented else { return }
            startTwoStageRetraction()
        }
    }
}
