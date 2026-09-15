//
//  floating_notification_popup.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Visual theme for battery notifications
enum BatteryNotificationTheme: Equatable {
    case green  // Normal charging (>20%)
    case red    // Low battery (<=20%)
    case yellow // Low power mode enabled
}

/// Payload specific to battery status notifications
struct BatteryNotificationPayload: Equatable {
    var level: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var isLowBatteryAlert: Bool = false
    var timeToFullCharge: Int = 0

    var theme: BatteryNotificationTheme {
        if isInLowPowerMode {
            return .yellow
        } else if level <= 20 {
            return .red
        } else {
            return .green
        }
    }
}

/// Notification payload variants
enum FloatingNotificationPayload: Equatable {
    case standard(
        title: String,
        message: String,
        trailingText: String?,
        iconName: String,
        iconColor: Color,
        iconBackground: Color
    )
    case battery(BatteryNotificationPayload)
}

/// Notification item model defining an alert's visual payload
struct FloatingNotificationItem: Identifiable, Equatable {
    let id: UUID = UUID()
    var payload: FloatingNotificationPayload
    var duration: TimeInterval = 2.0

    // Convenience initializer for standard notification
    init(
        iconName: String = "bell.fill",
        iconColor: Color = .white,
        iconBackground: Color = Color.white.opacity(0.12),
        title: String,
        message: String = "",
        trailingText: String? = nil,
        duration: TimeInterval = 2.0
    ) {
        self.payload = .standard(
            title: title,
            message: message,
            trailingText: trailingText,
            iconName: iconName,
            iconColor: iconColor,
            iconBackground: iconBackground
        )
        self.duration = duration
    }

    // Convenience initializer for battery notification
    init(battery: BatteryNotificationPayload, duration: TimeInterval = 2.0) {
        self.payload = .battery(battery)
        self.duration = duration
    }

    // Helper accessors for standard payload
    var title: String {
        switch payload {
        case .standard(let title, _, _, _, _, _):
            return title
        case .battery(let battery):
            if battery.isLowBatteryAlert && !battery.isInLowPowerMode {
                return "电量不足"
            } else if battery.isInLowPowerMode {
                return "低电量模式"
            } else if battery.isCharging {
                return "正在充电"
            } else if battery.isPluggedIn {
                return battery.level >= 99 ? "已充满" : "已连接电源"
            } else {
                return "电池"
            }
        }
    }

    var message: String {
        switch payload {
        case .standard(_, let message, _, _, _, _):
            return message
        case .battery(let battery):
            return "\(Int(battery.level))%"
        }
    }

    var iconName: String {
        switch payload {
        case .standard(_, _, _, let iconName, _, _):
            return iconName
        case .battery:
            return "bolt.fill"
        }
    }

    var iconColor: Color {
        switch payload {
        case .standard(_, _, _, _, let iconColor, _):
            return iconColor
        case .battery(let battery):
            switch battery.theme {
            case .green: return Color.green
            case .red: return Color.red
            case .yellow: return Color.yellow
            }
        }
    }

    var iconBackground: Color {
        switch payload {
        case .standard(_, _, _, _, _, let iconBackground):
            return iconBackground
        case .battery(let battery):
            switch battery.theme {
            case .green: return Color.green.opacity(0.15)
            case .red: return Color.red.opacity(0.15)
            case .yellow: return Color.yellow.opacity(0.15)
            }
        }
    }

    var trailingText: String? {
        switch payload {
        case .standard(_, _, let trailingText, _, _, _):
            return trailingText
        case .battery:
            return nil
        }
    }
}

/// Content view for standard single-line notifications
struct FloatingNotificationPopup: View {
    let item: FloatingNotificationItem
    var isContentVisible: Bool = true
    var onClose: (() -> Void)? = nil

    private static let POPUP_WIDTH: CGFloat = 224
    private static let POPUP_HEIGHT: CGFloat = 30

    var body: some View {
        HStack(spacing: 8) {
            // Leading Icon Badge (20x20)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(item.iconBackground)
                    .frame(width: 20, height: 20)

                Image(systemName: item.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.iconColor)
            }

            // Single-line notification text
            HStack(spacing: 5) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !item.message.isEmpty {
                    Text(item.message)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(white: 0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Optional Trailing Badge or Close Button
            if let trailing = item.trailingText {
                Text(trailing)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.50))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: Self.POPUP_WIDTH, height: Self.POPUP_HEIGHT)
        .opacity(isContentVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.16), value: isContentVisible)
        .contentShape(Rectangle())
        .onTapGesture {
            onClose?()
        }
    }
}

#Preview {
    struct FloatingNotificationPreview: View {
        @State private var isPresented: Bool = true
        let sample = FloatingNotificationItem(
            iconName: "bolt.fill",
            iconColor: .yellow,
            iconBackground: Color.yellow.opacity(0.18),
            title: "MagSafe Connected",
            message: "Battery at 85%",
            trailingText: "Now"
        )

        var body: some View {
            VStack(spacing: 30) {
                FloatingNotificationContainer(isPresented: $isPresented) { isContentVisible in
                    FloatingNotificationPopup(item: sample, isContentVisible: isContentVisible) {
                        isPresented = false
                    }
                }

                Button("Trigger Notification") {
                    isPresented.toggle()
                }
            }
            .padding(50)
            .background(Color.blue.opacity(0.4))
        }
    }

    return FloatingNotificationPreview()
}
