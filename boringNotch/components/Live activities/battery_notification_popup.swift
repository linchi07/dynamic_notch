//
//  battery_notification_popup.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Right accessory visual style based on battery and power connection state
enum BatteryRightIconStyle {
    case chargingPulsing       // 正在充电: bolt.fill with clean breathing opacity animation (no blur/glow)
    case fullyCharged          // 充满电: checkmark.circle.fill clean solid green (no blur/glow)
    case pluggedInNotCharging  // 已连接电源未充电: powerplug.fill clean solid icon (no blur/glow)
    case lowBatteryButton      // 20%低电量警报: compact "开启" low power button
    case lowPowerMode          // 低电量模式启用: leaf.fill clean solid yellow (no blur/glow)
}

/// Specialized notification content view for battery charging and power mode status.
/// Fixed 30px height, single-line text layout, uneven rounded fill, and clean content without glow.
struct BatteryNotificationPopup: View {
    let payload: BatteryNotificationPayload
    var isContentVisible: Bool = true
    var onEnableLowPowerMode: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    private static let POPUP_WIDTH: CGFloat = 246
    private static let POPUP_HEIGHT: CGFloat = 30
    private static let CORNER_RADIUS: CGFloat = 10

    @State private var isPulsing: Bool = false

    private var themeColor: Color {
        switch payload.theme {
        case .green:
            return Color(red: 0.20, green: 0.84, blue: 0.29)
        case .red:
            return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .yellow:
            return Color(red: 1.0, green: 0.80, blue: 0.0)
        }
    }

    /// Single-line status text displaying authoritative macOS battery estimates when charging
    private var singleLineStatusText: String {
        let percent = "\(Int(payload.level))%"
        if payload.isLowBatteryAlert && !payload.isInLowPowerMode {
            return "电量不足 \(percent)"
        } else if payload.isInLowPowerMode {
            return "低电量模式 \(percent)"
        } else if payload.isCharging {
            if payload.timeToFullCharge > 0 && payload.timeToFullCharge < 1000 {
                let estimateText = formatTimeToFull(payload.timeToFullCharge)
                return "正在充电 \(percent) · \(estimateText)"
            } else {
                return "正在充电 \(percent)"
            }
        } else if payload.isPluggedIn {
            if payload.level >= 99 {
                return "已充满 100%"
            } else {
                return "已连接电源 \(percent)"
            }
        } else {
            return "电池 \(percent)"
        }
    }

    /// Formats minutes into authoritative human-readable duration
    private func formatTimeToFull(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)分钟充满"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)小时充满"
            } else {
                return "\(hours)小时\(mins)分充满"
            }
        }
    }

    private var rightIconStyle: BatteryRightIconStyle {
        if payload.isLowBatteryAlert && !payload.isInLowPowerMode {
            return .lowBatteryButton
        } else if payload.isCharging {
            return .chargingPulsing
        } else if payload.isPluggedIn {
            if payload.level >= 99 {
                return .fullyCharged
            } else {
                return .pluggedInNotCharging
            }
        } else if payload.isInLowPowerMode {
            return .lowPowerMode
        } else {
            return .chargingPulsing
        }
    }

    var body: some View {
        ZStack {
            // Background: Solid deep black base with battery percentage fill
            // Fill has rounded corners on leading side and straight flat edge on trailing side for precise scale clipping
            GeometryReader { geometry in
                let clampedLevel = max(0, min(100, CGFloat(payload.level)))
                let fillWidth = geometry.size.width * (clampedLevel / 100.0)

                ZStack(alignment: .leading) {
                    Color.black

                    // Leading-rounded, trailing-flat fill layer with pure solid color
                    UnevenRoundedRectangle(
                        topLeadingRadius: Self.CORNER_RADIUS,
                        bottomLeadingRadius: Self.CORNER_RADIUS,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(themeColor.opacity(0.35))
                    .frame(width: fillWidth)

                    // Crisp demarcation line at fill edge without glow
                    if fillWidth > 2 && fillWidth < geometry.size.width - 2 {
                        Rectangle()
                            .fill(themeColor.opacity(0.70))
                            .frame(width: 1.0)
                            .offset(x: fillWidth - 1.0)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.CORNER_RADIUS, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.CORNER_RADIUS, style: .continuous)
                    .strokeBorder(themeColor.opacity(0.18), lineWidth: 0.8)
            )

            // Foreground Content: Single-line horizontal layout (pure content without glow)
            HStack(spacing: 8) {
                // Leading: Status text + percentage + authoritative time
                Text(singleLineStatusText)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Trailing: Clean accessory depending on specific state
                accessoryView
            }
            .padding(.horizontal, 10)
            .opacity(isContentVisible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.16), value: isContentVisible)
        }
        .frame(width: Self.POPUP_WIDTH, height: Self.POPUP_HEIGHT)
        .contentShape(Rectangle())
        .onTapGesture {
            onClose?()
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch rightIconStyle {
        case .chargingPulsing:
            // 正在充电: Clean bolt.fill with rhythmic opacity breathing (strictly no blur/glow)
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(themeColor)
                .opacity(isPulsing ? 1.0 : 0.40)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }

        case .fullyCharged:
            // 充满电: Clean checkmark.circle.fill in solid Apple green (no glow)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.84, blue: 0.29))

        case .pluggedInNotCharging:
            // 已连接电源未充电: Clean powerplug.fill with solid appearance (no glow)
            Image(systemName: "powerplug.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))

        case .lowBatteryButton:
            // 20%低电量: Compact pill action button fitting cleanly within 30px (no glow)
            Button(action: {
                onEnableLowPowerMode?()
                onClose?()
            }) {
                HStack(spacing: 2.5) {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("开启")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(themeColor.opacity(0.35))
                        .overlay(Capsule().strokeBorder(themeColor.opacity(0.65), lineWidth: 0.7))
                )
            }
            .buttonStyle(.plain)

        case .lowPowerMode:
            // 低电量模式已开启: Clean solid leaf.fill in yellow (no glow)
            Image(systemName: "leaf.fill")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.0))
        }
    }
}
