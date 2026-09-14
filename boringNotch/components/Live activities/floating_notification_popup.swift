//
//  floating_notification_popup.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Notification item model defining an alert's visual payload
struct FloatingNotificationItem: Identifiable, Equatable {
    let id: UUID = UUID()
    var iconName: String
    var iconColor: Color = .white
    var iconBackground: Color = Color.white.opacity(0.12)
    var title: String
    var message: String
    var trailingText: String? = nil
    var duration: TimeInterval = 4.0
}

/// Content view for strong alert notifications to be hosted inside FloatingNotificationContainer
struct FloatingNotificationPopup: View {
    let item: FloatingNotificationItem
    var isContentVisible: Bool = true
    var onClose: (() -> Void)? = nil

    private static let POPUP_WIDTH: CGFloat = 280
    private static let POPUP_HEIGHT: CGFloat = 46

    var body: some View {
        HStack(spacing: 12) {
            // Leading Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.iconBackground)
                    .frame(width: 30, height: 30)

                Image(systemName: item.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.iconColor)
            }

            // Notification Texts
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(white: 0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Optional Trailing Badge or Close Button
            if let trailing = item.trailingText {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.50))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.POPUP_WIDTH, height: Self.POPUP_HEIGHT)
        .opacity(isContentVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.18), value: isContentVisible)
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
