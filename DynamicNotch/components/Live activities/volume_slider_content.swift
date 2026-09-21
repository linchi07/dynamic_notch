//
//  volume_slider_content.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI
import Defaults

/// Standalone volume and brightness slider content.
/// Can be embedded into FloatingPopupContainer or any other presentation host.
struct VolumeSliderContent: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String

    // Visual Constants (Compact iOS-style proportions)
    private static let CONTENT_WIDTH: CGFloat = 200
    private static let EXPANDED_HEIGHT: CGFloat = 30
    private static let NARROWED_HEIGHT: CGFloat = 8
    private static let DRAG_NORMAL_WIDTH: CGFloat = 208
    private static let DRAG_NORMAL_HEIGHT: CGFloat = 34
    private static let DRAG_BOUNDARY_WIDTH: CGFloat = 212
    private static let DRAG_BOUNDARY_HEIGHT: CGFloat = 36
    private static let ICON_SIZE: CGFloat = 14

    // Interactive states
    @State private var isDragging: Bool = false
    @State private var isDraggingAtBoundary: Bool = false
    @State private var isRapidAdjusting: Bool = false
    @State private var isHoldingAtBoundary: Bool = false
    @State private var lastValueChangeTime: TimeInterval = 0
    @State private var rapidResetTask: Task<Void, Never>?
    @State private var boundaryReleaseTask: Task<Void, Never>?
    @State private var hasTriggeredDragHaptic: Bool = false

    // Effective width: 208 for normal drag, 212 at a boundary, 200 at rest.
    private var effectiveWidth: CGFloat {
        if isDragging {
            return isDraggingAtBoundary ? Self.DRAG_BOUNDARY_WIDTH : Self.DRAG_NORMAL_WIDTH
        }
        if isHoldingAtBoundary {
            return Self.CONTENT_WIDTH + 12.0
        }
        return Self.CONTENT_WIDTH
    }

    // Base height according to acceleration or dragging mode
    private var baseHeight: CGFloat {
        if isDragging {
            return isDraggingAtBoundary ? Self.DRAG_BOUNDARY_HEIGHT : Self.DRAG_NORMAL_HEIGHT
        }
        if isRapidAdjusting {
            return Self.NARROWED_HEIGHT
        }
        return Self.EXPANDED_HEIGHT
    }

    // Boundary holds compress the already-narrow 8pt bar a little further.
    private var effectiveHeight: CGFloat {
        if isDragging {
            return isDraggingAtBoundary ? Self.DRAG_BOUNDARY_HEIGHT : Self.DRAG_NORMAL_HEIGHT
        }
        if isHoldingAtBoundary {
            return baseHeight * 0.78
        }
        return baseHeight
    }

    var body: some View {
        let clampedValue = max(0, min(1, value))
        let liveWidth = effectiveWidth
        let liveHeight = effectiveHeight

        ZStack(alignment: .leading) {
            // 1. Base Layer (Unfilled): Light gray icon and label over the frosted background
            HStack(spacing: 8) {
                leadingIcon(color: Color(white: 0.68), cutoutColor: Color(white: 0.20))
                Spacer()
                trailingLabel(color: Color(white: 0.68))
            }
            .padding(.horizontal, 10)
            .frame(width: liveWidth, height: liveHeight)
            .opacity(isRapidAdjusting && !isDragging ? 0.0 : 1.0)
            .animation(.easeInOut(duration: 0.16), value: isRapidAdjusting)

            // 2. Active Progress Fill: Pure white slider that fills from the left
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: liveWidth, height: liveHeight)

                // Foreground content over white fill (Dark gray for sharp readability)
                HStack(spacing: 8) {
                    leadingIcon(color: Color(white: 0.16), cutoutColor: Color.white)
                    Spacer()
                    trailingLabel(color: Color(white: 0.16))
                }
                .padding(.horizontal, 10)
                .frame(width: liveWidth, height: liveHeight)
                .opacity(isRapidAdjusting && !isDragging ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.16), value: isRapidAdjusting)
            }
            // Scale a full-size mask instead of animating several independent
            // widths. At 100% this covers the base exactly, and when the whole
            // HUD moves vertically the fill and its shell remain one surface.
            .mask(alignment: .leading) {
                Rectangle()
                    .frame(width: liveWidth, height: liveHeight)
                    .scaleEffect(x: clampedValue, anchor: .leading)
            }
            .animation(isDragging ? nil : FloatingPopupStyle.fluidSliderSpring, value: clampedValue)
        }
        .frame(width: liveWidth, height: liveHeight)
        .compositingGroup()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    handleDragChanged(gesture: gesture, totalWidth: liveWidth)
                }
                .onEnded { _ in
                    handleDragEnded()
                }
        )
        .animation(FloatingPopupStyle.fluidSliderSpring, value: isRapidAdjusting)
        .animation(isHoldingAtBoundary ? FloatingPopupStyle.bounceSpring : FloatingPopupStyle.strongBounceSpring, value: isHoldingAtBoundary)
        .animation(isDragging ? .interactiveSpring(response: 0.25, dampingFraction: 0.78) : FloatingPopupStyle.strongBounceSpring, value: isDragging)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.78), value: isDraggingAtBoundary)
        .onChange(of: value) {
            handleValueChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchBoundaryHit)) { _ in
            handleBoundaryHit()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchMediaKeyDidRelease)) { _ in
            handleKeyRelease()
        }
    }

    private func handleValueChange() {
        guard !isDragging else { return }

        let now = Date().timeIntervalSince1970
        let timeDelta = now - lastValueChangeTime
        lastValueChangeTime = now

        // Acceleration detection: rapid consecutive keystrokes or holding (< 340ms)
        if timeDelta < 0.34 {
            withAnimation(FloatingPopupStyle.fluidSliderSpring) {
                isRapidAdjusting = true
            }
        }

        // If not holding at boundary, schedule delayed expand
        if !isHoldingAtBoundary {
            scheduleRapidReset(delayMs: 750)
        }
    }

    private func handleBoundaryHit() {
        guard !isDragging else { return }

        if !isHoldingAtBoundary {
            withAnimation(FloatingPopupStyle.bounceSpring) {
                isHoldingAtBoundary = true
            }
            triggerHapticFeedback()
        }

        if !isRapidAdjusting {
            withAnimation(FloatingPopupStyle.fluidSliderSpring) {
                isRapidAdjusting = true
            }
        }

        rapidResetTask?.cancel()

        // Safety watchdog: only auto-release after 4.0 seconds in case key release notification was dropped
        boundaryReleaseTask?.cancel()
        boundaryReleaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            releaseBoundaryHold()
        }
    }

    private func handleKeyRelease() {
        boundaryReleaseTask?.cancel()
        if isHoldingAtBoundary {
            releaseBoundaryHold()
        }
        scheduleRapidReset(delayMs: 750)
    }

    private func releaseBoundaryHold() {
        withAnimation(FloatingPopupStyle.strongBounceSpring) {
            isHoldingAtBoundary = false
        }
        triggerHapticFeedback()
    }

    private func scheduleRapidReset(delayMs: Int = 750) {
        rapidResetTask?.cancel()
        rapidResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                isRapidAdjusting = false
            }
        }
    }

    private func handleDragChanged(gesture: DragGesture.Value, totalWidth: CGFloat) {
        guard totalWidth > 0 else { return }
        let locX = gesture.location.x
        let progress = max(0, min(1, locX / totalWidth))
        updateValue(progress)

        // Hysteresis boundary detection (anti-shake):
        // Trigger secondary expansion (212*36) only at true limits (100% or 0%)
        // Pull back to normal expansion (208*34) only after moving inward into [0.05, 0.95]
        let nextAtBoundary: Bool
        if isDraggingAtBoundary {
            let pulledInward = progress < 0.95 && progress > 0.05
            nextAtBoundary = !pulledInward
        } else {
            nextAtBoundary = locX >= totalWidth || locX <= 0
        }

        if !isDragging {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.78)) {
                isDragging = true
                isDraggingAtBoundary = nextAtBoundary
            }
            isRapidAdjusting = false
            rapidResetTask?.cancel()
        } else if isDraggingAtBoundary != nextAtBoundary {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.78)) {
                isDraggingAtBoundary = nextAtBoundary
            }
        }

        if nextAtBoundary && !hasTriggeredDragHaptic {
            hasTriggeredDragHaptic = true
            triggerHapticFeedback()
        } else if !nextAtBoundary {
            hasTriggeredDragHaptic = false
        }
    }

    private func handleDragEnded() {
        withAnimation(FloatingPopupStyle.strongBounceSpring) {
            isDragging = false
            isDraggingAtBoundary = false
        }
        hasTriggeredDragHaptic = false
        triggerHapticFeedback()
        scheduleRapidReset(delayMs: 750)
    }

    private func triggerHapticFeedback() {
        guard Defaults[.enableHaptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    @ViewBuilder
    private func leadingIcon(color: Color, cutoutColor: Color) -> some View {
        Group {
            switch type {
            case .volume:
                if !icon.isEmpty {
                    Image(systemName: icon)
                } else {
                    SpeakerAnimatedIcon(value: value, color: color, cutoutColor: cutoutColor)
                }
            case .brightness:
                SunAnimatedIcon(value: value, color: color)
            case .backlight:
                Image(systemName: value > 0.5 ? "light.max" : "light.min")
            case .mic:
                Image(systemName: value.isZero ? "mic.slash.fill" : "mic.fill")
                    .contentTransition(.symbolEffect(.replace.byLayer))
            default:
                EmptyView()
            }
        }
        .font(.system(size: Self.ICON_SIZE, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 20, alignment: .center)
    }

    @ViewBuilder
    private func trailingLabel(color: Color) -> some View {
        Group {
            if type == .volume && value.isZero {
                Text("Muted")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            } else if type == .mic {
                Text(value.isZero ? "Muted" : "On")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            } else {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(color)
        .animation(isDragging ? nil : FloatingPopupStyle.fluidSliderSpring, value: value)
    }

    private func updateValue(_ newValue: CGFloat) {
        value = newValue
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newValue))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newValue))
        default:
            break
        }
        // Keep the HUD alive while user is interacting
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: type, value: newValue, icon: icon)
    }
}

/// Dynamic speaker icon with smooth wave level indicators and a drawn diagonal slash on mute
struct SpeakerAnimatedIcon: View {
    let value: CGFloat
    let color: Color
    let cutoutColor: Color

    var isMuted: Bool {
        value <= 0.001
    }

    var body: some View {
        ZStack {
            // 1. Speaker base with wave arcs
            Image(systemName: "speaker.wave.3.fill", variableValue: Double(max(0.08, value)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .opacity(isMuted ? 0.35 : 1.0)
                .scaleEffect(isMuted ? 0.92 : 1.0)

            // 2. Precise diagonal slash drawing (Trim from 0 to 1 without cross-fade haze)
            // Cutout underlay for clean razor incision
            SlashLineShape()
                .trim(from: 0, to: isMuted ? 1.0 : 0.0)
                .stroke(cutoutColor, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

            // Main foreground slash
            SlashLineShape()
                .trim(from: 0, to: isMuted ? 1.0 : 0.0)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .frame(width: 20, height: 20)
        .animation(.interpolatingSpring(mass: 0.85, stiffness: 135, damping: 14.5), value: isMuted)
        .animation(.interpolatingSpring(mass: 0.85, stiffness: 135, damping: 14.5), value: value)
    }
}

private struct SlashLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX + 2.5, y: rect.minY + 3.0)
        let end = CGPoint(x: rect.maxX - 2.0, y: rect.maxY - 3.0)
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

/// Dynamic sun icon where ray length expands as brightness increases
struct SunAnimatedIcon: View {
    let value: CGFloat
    let color: Color

    var body: some View {
        let clamped = max(0, min(1, value))
        // Ray length expands from 1.2pt to 4.2pt as brightness rises
        let rayLength: CGFloat = 1.2 + clamped * 3.0
        let innerRadius: CGFloat = 4.2 + clamped * 0.8
        let centerSize: CGFloat = 5.2 + clamped * 0.8

        ZStack {
            // Core sun sphere
            Circle()
                .fill(color)
                .frame(width: centerSize, height: centerSize)

            // 8 radiating rays that grow longer with brightness
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * (Double.pi / 4.0)
                let cosA = CGFloat(cos(angle))
                let sinA = CGFloat(sin(angle))

                let startX = cosA * innerRadius
                let startY = sinA * innerRadius
                let endX = cosA * (innerRadius + rayLength)
                let endY = sinA * (innerRadius + rayLength)

                Path { path in
                    path.move(to: CGPoint(x: 10 + startX, y: 10 + startY))
                    path.addLine(to: CGPoint(x: 10 + endX, y: 10 + endY))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        .frame(width: 20, height: 20)
        .animation(.interpolatingSpring(mass: 0.85, stiffness: 135, damping: 14.5), value: clamped)
    }
}

#Preview {
    struct VolumeSliderPreview: View {
        @State private var type: SneakContentType = .volume
        @State private var value: CGFloat = 0.65
        @State private var icon: String = ""

        var body: some View {
            VStack(spacing: 30) {
                FloatingPopupContainer {
                    VolumeSliderContent(type: $type, value: $value, icon: $icon)
                        .environmentObject(BoringViewModel())
                }

                HStack {
                    Button("Volume") { type = .volume }
                    Button("Brightness") { type = .brightness }
                    Button("Mute") { value = 0 }
                    Button("Full") { value = 1.0 }
                }
            }
            .padding(40)
            .background(Color.blue.opacity(0.3))
        }
    }

    return VolumeSliderPreview()
}
