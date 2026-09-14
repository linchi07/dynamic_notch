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

    @State private var isDragging: Bool = false

    // Visual Constants (Compact iOS-style proportions)
    private static let CONTENT_WIDTH: CGFloat = 200
    private static let CONTENT_HEIGHT: CGFloat = 30
    private static let ICON_SIZE: CGFloat = 14

    var body: some View {
        let clampedValue = max(0, min(1, value))

        GeometryReader { geo in
            let totalWidth = geo.size.width
            let progressWidth = max(0, min(totalWidth, totalWidth * clampedValue))

            ZStack(alignment: .leading) {
                // 1. Base Layer (Unfilled): Light gray icon and label over the frosted background
                HStack(spacing: 8) {
                    leadingIcon(color: Color(white: 0.68), cutoutColor: Color(white: 0.20))
                    Spacer()
                    trailingLabel(color: Color(white: 0.68))
                }
                .padding(.horizontal, 10)
                .frame(width: totalWidth, height: Self.CONTENT_HEIGHT)

                // 2. Active Progress Fill: Pure white slider that fills 100% height from the left with zero margin
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: progressWidth, height: Self.CONTENT_HEIGHT)

                    // Foreground content over white fill (Dark gray for sharp readability)
                    HStack(spacing: 8) {
                        leadingIcon(color: Color(white: 0.16), cutoutColor: Color.white)
                        Spacer()
                        trailingLabel(color: Color(white: 0.16))
                    }
                    .padding(.horizontal, 10)
                    .frame(width: totalWidth, height: Self.CONTENT_HEIGHT)
                }
                .frame(width: progressWidth, height: Self.CONTENT_HEIGHT, alignment: .leading)
                .clipped()
                .animation(isDragging ? nil : FloatingPopupStyle.fluidSliderSpring, value: clampedValue)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let progress = max(0, min(1, gesture.location.x / totalWidth))
                        updateValue(progress)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(width: Self.CONTENT_WIDTH, height: Self.CONTENT_HEIGHT)
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
