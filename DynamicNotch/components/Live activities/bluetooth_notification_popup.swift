//
//  bluetooth_notification_popup.swift
//  DynamicNotch
//
//  Created on 2026-09-24.
//

import SwiftUI

/// Specialized notification content view for Bluetooth and AirPods connection events.
/// Designed to mirror the iOS Dynamic Island accessory connection aesthetic.
struct BluetoothNotificationPopup: View {
    let payload: BluetoothDeviceNotificationPayload
    var isContentVisible: Bool = true
    var onClose: (() -> Void)? = nil

    private static let POPUP_WIDTH: CGFloat = 246
    private static let POPUP_HEIGHT: CGFloat = 30
    private static let CORNER_RADIUS: CGFloat = 15

    var body: some View {
        ZStack {
            // Background capsule with subtle Apple-style border
            RoundedRectangle(cornerRadius: Self.CORNER_RADIUS, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.CORNER_RADIUS, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )

            // Content horizontal layout
            HStack(spacing: 8) {
                // Leading: AirPods / Device Icon
                leadingDeviceIcon

                // Middle: Device name and connection status
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(payload.deviceName)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("已连接")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color(white: 0.65))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // Trailing: Battery gauge or Success checkmark
                trailingAccessory
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
    private var leadingDeviceIcon: some View {
        if let customImage = payload.customImage {
            // 3D high-resolution render (AirPods / Beats)
            Image(nsImage: customImage)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
        } else {
            // Fallback SF Symbol with multi-layer / hierarchical rendering
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 22, height: 22)

                Image(systemName: payload.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if let level = payload.batteryLevel {
            // Battery pill with percentage
            HStack(spacing: 3.5) {
                Image(systemName: batterySymbol(for: level))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(batteryColor(for: level))

                Text("\(level)%")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(batteryColor(for: level))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        } else {
            // iOS-style connected checkmark indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.84, blue: 0.29))
        }
    }

    private func batterySymbol(for level: Int) -> String {
        if level <= 10 {
            return "battery.0percent"
        } else if level <= 25 {
            return "battery.25percent"
        } else if level <= 50 {
            return "battery.50percent"
        } else if level <= 75 {
            return "battery.75percent"
        } else {
            return "battery.100percent"
        }
    }

    private func batteryColor(for level: Int) -> Color {
        if level <= 20 {
            return Color.red
        } else {
            return Color(red: 0.20, green: 0.84, blue: 0.29)
        }
    }
}
