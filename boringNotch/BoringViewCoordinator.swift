//
//  BoringViewCoordinator.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

@MainActor
class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()

    @Published var currentView: NotchViews = .home
    @Published var helloAnimationRunning: Bool = false
    @Published var isNotificationPresented: Bool = false
    @Published var displayMode: NotchDisplayMode = .idle
    @Published var activeCombo: NotchComboActivity? = nil
    private var stateBeforeNotification: NotchDisplayMode = .idle
    private var comboTask: Task<Void, Never>?
    private var sneakPeekDispatch: DispatchWorkItem?
    private var hudEnableTask: Task<Void, Never>?

    private func setDisplayMode(_ mode: NotchDisplayMode) {
        withAnimation(.smooth(duration: 0.3)) {
            self.displayMode = mode
        }
    }

    func clearDisplayMode() {
        comboTask?.cancel()
        comboTask = nil
        isNotificationPresented = false
        stateBeforeNotification = .idle
        withAnimation(.smooth(duration: 0.3)) {
            self.displayMode = .idle
            self.activeCombo = nil
        }
    }

    func setActiveState(_ state: NotchActiveState) {
        comboTask?.cancel()
        comboTask = nil
        activeCombo = nil
        isNotificationPresented = false
        stateBeforeNotification = .idle
        setDisplayMode(.active(state))
    }

    var activeNotification: FloatingNotificationItem? {
        guard case .notification(let item) = displayMode else { return nil }
        return item
    }

    func postNotificationItem(_ item: FloatingNotificationItem) {
        switch displayMode {
        case .notification:
            break // Preserve the state from before the first notification.
        case .active:
            stateBeforeNotification = displayMode
        case .idle:
            stateBeforeNotification = .idle
        }

        withAnimation(.smooth(duration: 0.24)) {
            displayMode = .notification(item)
        }
        self.isNotificationPresented = true
    }

    func startComboActivity(_ combo: NotchComboActivity) {
        comboTask?.cancel()
        activeCombo = combo
        postNotificationItem(combo.initialNotification)

        comboTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(combo.initialNotifyDuration))
            guard !Task.isCancelled else { return }

            self.dismissNotification()

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            withAnimation(.smooth(duration: 0.32)) {
                self.displayMode = .active(combo.activeState)
            }
        }
    }

    func finishComboActivity(completionNotification: FloatingNotificationItem? = nil) {
        comboTask?.cancel()
        let notification = completionNotification ?? activeCombo?.completionNotification
        withAnimation(.smooth(duration: 0.28)) {
            self.displayMode = .idle
        }

        if let completion = notification {
            comboTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                self.postNotificationItem(completion)
                self.activeCombo = nil
            }
        } else {
            self.activeCombo = nil
        }
    }

    func postNotification(
        title: String,
        message: String = "",
        iconName: String = "bell.fill",
        iconColor: Color = .white,
        iconBackground: Color = Color.white.opacity(0.12),
        trailingText: String? = nil,
        duration: TimeInterval = 2.0
    ) {
        let item = FloatingNotificationItem(
            iconName: iconName,
            iconColor: iconColor,
            iconBackground: iconBackground,
            title: title,
            message: message,
            trailingText: trailingText,
            duration: duration
        )
        postNotificationItem(item)
    }

    func postBatteryNotification(
        level: Float,
        isPluggedIn: Bool,
        isCharging: Bool,
        isInLowPowerMode: Bool,
        isLowBatteryAlert: Bool = false,
        timeToFullCharge: Int = 0,
        duration: TimeInterval = 2.0
    ) {
        let payload = BatteryNotificationPayload(
            level: level,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            isInLowPowerMode: isInLowPowerMode,
            isLowBatteryAlert: isLowBatteryAlert,
            timeToFullCharge: timeToFullCharge
        )
        postNotificationItem(FloatingNotificationItem(battery: payload, duration: duration))
    }

    func dismissNotification() {
        self.isNotificationPresented = false
    }

    func notificationDidDismiss() {
        guard case .notification = displayMode else { return }
        withAnimation(.smooth(duration: 0.24)) {
            displayMode = stateBeforeNotification
        }
        stateBeforeNotification = .idle
    }

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @Default(.hudReplacement) var hudReplacement: Bool
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?

    private init() {
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.hudReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        // Observe changes to hudReplacement
        hudReplacementCancellable = Defaults.publisher(.hudReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                            } else {
                                Defaults[.hudReplacement] = false
                            }
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            if Defaults[.hudReplacement] {
                let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if !authorized {
                    Defaults[.hudReplacement] = false
                } else {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            print("Decoded: \(decodedData), Parsed value: \(value)")

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            print("Failed to decode JSON data")
        }
    }

    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval = 1.5, value: CGFloat = 0,
        icon: String = ""
    ) {
        sneakPeekDuration = duration
        if type != .music {
            // close()
            if !Defaults[.hudReplacement] {
                return
            }
        }
        Task { @MainActor in
            withAnimation(.smooth) {
                self.sneakPeek.show = status
                self.sneakPeek.type = type
                self.sneakPeek.value = value
                self.sneakPeek.icon = icon
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.toggleSneakPeek(status: false, type: .music)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    func showEmpty() {
        currentView = .home
    }
}
