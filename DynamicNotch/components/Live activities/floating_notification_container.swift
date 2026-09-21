//
//  floating_notification_container.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Physical lifecycle stages for notification pop-in ejection and retraction beneath the notch
enum NotificationEjectionPhase {
    case hidden             // Tucked behind notch
    case ejectedStage1      // Stage 1: Ejected downward from behind notch, initial stretch
    case fullyExpanded      // Stage 2: Full horizontal elongation & vertical expansion
    case narrowingStage1    // Retraction 1: Narrow down within the notch width before moving up
    case retractedStage2    // Retraction 2: Slid upward back behind notch, fully vanished
}

/// Metrics and layout constants for floating notifications
private enum FloatingNotificationMetrics {
    static let HIDDEN_OFFSET_Y: CGFloat = -45
    static let CORNER_RADIUS: CGFloat = 16
}

/// Specialized floating container for strong notifications and alerts.
/// Features two-stage pop-down ejection and synchronized two-step retraction (narrow within notch -> slide up).
struct FloatingNotificationContainer<Content: View>: View {
    @Binding var isPresented: Bool
    var autoDismissAfter: TimeInterval? = 2.0
    var updateTrigger: AnyHashable? = nil
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
        autoDismissAfter: TimeInterval? = 2.0,
        updateTrigger: AnyHashable? = nil,
        onFullExpand: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Bool) -> Content
    ) {
        self._isPresented = isPresented
        self.autoDismissAfter = autoDismissAfter
        self.updateTrigger = updateTrigger
        self.onFullExpand = onFullExpand
        self.onDismiss = onDismiss
        self.content = content
    }

    // Dynamic scale and offset based on ejection and retraction phases
    private var phaseScaleX: CGFloat {
        switch phase {
        case .hidden:
            return 0.35
        case .ejectedStage1:
            return 0.65
        case .fullyExpanded:
            return 1.0
        case .narrowingStage1, .retractedStage2:
            // Narrow down to 0.45 (approx 100pt), strictly within physical notch width (170-210pt)
            return 0.45
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
        case .narrowingStage1:
            return 0.85
        case .retractedStage2:
            return 0.50
        }
    }

    private var phaseOffsetY: CGFloat {
        switch phase {
        case .hidden, .retractedStage2:
            return FloatingNotificationMetrics.HIDDEN_OFFSET_Y
        case .ejectedStage1, .fullyExpanded, .narrowingStage1:
            // Remain at lower position while narrowing to avoid leaking outside notch boundaries
            return 0
        }
    }

    private var phaseOpacity: Double {
        switch phase {
        case .hidden, .retractedStage2:
            return 0.0
        case .ejectedStage1, .fullyExpanded, .narrowingStage1:
            return 1.0
        }
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(white: 0.08).opacity(0.96))
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(0.35)
                        .clipShape(Capsule())
                )

            content(isContentVisible)
                .clipShape(Capsule())
        }
        .fixedSize()
        .clipShape(Capsule())
        // Pure spatial depth shadows for clean layering without colored halo glow
        .shadow(color: Color.black.opacity(0.42), radius: 10, x: 0, y: 5)
        .shadow(color: Color.black.opacity(0.20), radius: 2, x: 0, y: 1)
        .scaleEffect(x: phaseScaleX, y: phaseScaleY, anchor: .top)
        .offset(y: phaseOffsetY)
        .opacity(phaseOpacity)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if value.translation.height < -8 {
                            self.isPresented = false
                        }
                    }
            )
            .onAppear {
                if isPresented {
                    startTwoStageEjection()
                }
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    startTwoStageEjection()
                } else if phase == .fullyExpanded || phase == .ejectedStage1 {
                    startRetractionSequence()
                }
            }
            .onChange(of: updateTrigger) { oldVal, newVal in
                guard oldVal != nil, oldVal != newVal else { return }
                if isPresented {
                    startTwoStageEjection()
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
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, isPresented else { return }

            withAnimation(.easeInOut(duration: 0.16)) {
                isContentVisible = true
            }
            onFullExpand?()

            // Optional auto dismiss countdown (defaults to 2.0s)
            if let duration = autoDismissAfter {
                scheduleAutoDismiss(after: duration)
            }
        }
    }

    // MARK: - Two-Step Retraction Sequence (Narrow within Notch -> Slide Up)
    private func startRetractionSequence() {
        ejectionTask?.cancel()
        autoDismissTask?.cancel()
        retractionTask?.cancel()

        // Content fades out immediately
        withAnimation(.easeInOut(duration: 0.08)) {
            isContentVisible = false
        }

        // Retract Step 1: Rapidly narrow down within the physical notch width
        withAnimation(.spring(response: 0.18, dampingFraction: 0.80)) {
            phase = .narrowingStage1
        }

        retractionTask = Task { @MainActor in
            // Wait for narrowing to settle within notch bounds
            try? await Task.sleep(for: .milliseconds(115))
            guard !Task.isCancelled else { return }

            // Retract Step 2: Slide vertically up behind notch in narrow form
            withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
                phase = .retractedStage2
            }

            try? await Task.sleep(for: .milliseconds(150))
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
            startRetractionSequence()
        }
    }
}
