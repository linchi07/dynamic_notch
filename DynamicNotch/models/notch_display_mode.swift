//
//  notch_display_mode.swift
//  boringNotch
//
//  Created on 2026-09-15.
//

import AppKit
import Foundation
import SwiftUI

/// Visual content rendered in one active wing.
enum NotchActivityVisual: Equatable {
    case system(name: String)
    case customImage(image: NSImage)
    case colorDot(color: Color)
    case audioVisualizer
}

/// One side of a live activity. Active wings intentionally render only compact
/// visuals so every activity uses the same fixed notch length.
struct NotchActivityItem: Equatable {
    var visual: NotchActivityVisual
    var tintColor: Color
    var accessibilityLabel: String
    var isPulsing: Bool
    var heroId: String?

    init(
        visual: NotchActivityVisual,
        tintColor: Color = .white,
        accessibilityLabel: String = "",
        isPulsing: Bool = false,
        heroId: String? = nil
    ) {
        self.visual = visual
        self.tintColor = tintColor
        self.accessibilityLabel = accessibilityLabel
        self.isPulsing = isPulsing
        self.heroId = heroId
    }
}

/// A live activity may own both sides of the notch. When two activities are
/// active, the first resolves to the leading side and the second to trailing.
struct NotchLiveActivity: Identifiable, Equatable {
    let id: String
    var leading: NotchActivityItem?
    var trailing: NotchActivityItem?

    init(
        id: String = UUID().uuidString,
        leading: NotchActivityItem? = nil,
        trailing: NotchActivityItem? = nil
    ) {
        self.id = id
        self.leading = leading
        self.trailing = trailing
    }
}

/// The payload for the active notch state. At most two activities are shown.
struct NotchActiveState: Equatable {
    private(set) var activities: [NotchLiveActivity]

    init(activities: [NotchLiveActivity]) {
        self.activities = Array(activities.prefix(2))
    }

    init(activity: NotchLiveActivity) {
        self.init(activities: [activity])
    }

    var leadingItem: NotchActivityItem? {
        guard let first = activities.first else { return nil }
        return first.leading ?? first.trailing
    }

    var trailingItem: NotchActivityItem? {
        guard !activities.isEmpty else { return nil }
        if activities.count == 1 {
            return activities[0].trailing ?? activities[0].leading
        }
        return activities[1].trailing ?? activities[1].leading
    }
}

/// The three mutually exclusive notch presentation states. Volume, brightness,
/// keyboard backlight, and microphone HUDs remain independent transient UI.
enum NotchDisplayMode: Equatable {
    case idle
    case active(NotchActiveState)
    case notification(FloatingNotificationItem)
}

/// Notification -> active -> optional completion notification lifecycle.
struct NotchComboActivity: Identifiable, Equatable {
    let id: UUID
    var initialNotification: FloatingNotificationItem
    var initialNotifyDuration: TimeInterval
    var activeState: NotchActiveState
    var completionNotification: FloatingNotificationItem?

    init(
        id: UUID = UUID(),
        initialNotification: FloatingNotificationItem,
        initialNotifyDuration: TimeInterval = 2.0,
        activeState: NotchActiveState,
        completionNotification: FloatingNotificationItem? = nil
    ) {
        self.id = id
        self.initialNotification = initialNotification
        self.initialNotifyDuration = initialNotifyDuration
        self.activeState = activeState
        self.completionNotification = completionNotification
    }
}

/// Geometry shared by every active presentation, including music and developer
/// previews. The physical notch is never padded; only the two outer edges are.
enum NotchLayoutMetrics {
    static let minimumVisualSize: CGFloat = 16

    static func visualSize(for notchHeight: CGFloat) -> CGFloat {
        max(minimumVisualSize, notchHeight - 12)
    }

    static func wingWidth(for notchHeight: CGFloat, outerPadding: CGFloat) -> CGFloat {
        visualSize(for: notchHeight) + outerPadding
    }

    static func activeWidth(
        physicalNotchWidth: CGFloat,
        notchHeight: CGFloat,
        outerPadding: CGFloat
    ) -> CGFloat {
        physicalNotchWidth + 2 * wingWidth(for: notchHeight, outerPadding: outerPadding)
    }
}
