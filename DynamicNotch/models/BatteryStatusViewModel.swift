import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    /// Initializes the view model with a given BoringViewModel instance
    /// - Parameter vm: The BoringViewModel instance
    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    private var previousLevel: Float = 100.0
    private var previousPluggedIn: Bool? = nil
    private var previousLowPowerMode: Bool? = nil
    private var hasAlertedLowBatteryForCurrentCycle: Bool = false

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? "Plugged In" : "Unplugged"
        }
        self.previousLevel = batteryInfo.currentCapacity
        self.previousPluggedIn = batteryInfo.isPluggedIn
        self.previousLowPowerMode = batteryInfo.isInLowPowerMode
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            let wasPluggedIn = self.previousPluggedIn ?? self.isPluggedIn
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? "Plugged In" : "Unplugged"
            }
            self.previousPluggedIn = isPluggedIn

            // Trigger notification when plugged into power source
            if isPluggedIn && !wasPluggedIn && Defaults[.showPowerStatusNotifications] {
                self.hasAlertedLowBatteryForCurrentCycle = false
                self.triggerBatteryNotification(isLowBatteryAlert: false)
            } else if !isPluggedIn && wasPluggedIn && Defaults[.showPowerStatusNotifications] {
                self.notifyImportanChangeStatus()
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            let oldLevel = self.previousLevel
            withAnimation {
                self.levelBattery = level
            }
            self.previousLevel = level

            // Reset low battery cycle if recharged past 25%
            if level > 25 {
                self.hasAlertedLowBatteryForCurrentCycle = false
            }

            // Trigger red warning notification when falling to or below 20% on battery
            if !self.isPluggedIn && level <= 20 && oldLevel > 20
                && !self.hasAlertedLowBatteryForCurrentCycle
                && Defaults[.showPowerStatusNotifications]
            {
                self.hasAlertedLowBatteryForCurrentCycle = true
                self.triggerBatteryNotification(isLowBatteryAlert: true)
            }

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            let wasEnabled = self.previousLowPowerMode ?? self.isInLowPowerMode
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
            }
            self.previousLowPowerMode = isEnabled

            // Trigger yellow notification when low power mode is enabled
            if isEnabled && !wasEnabled && Defaults[.showPowerStatusNotifications] {
                self.triggerBatteryNotification(isLowBatteryAlert: false)
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? "Charging battery"
                    : (self.levelBattery < self.maxCapacity ? "Not charging" : "Full charge")
            }

            if isCharging && self.isPluggedIn && self.previousPluggedIn == false
                && Defaults[.showPowerStatusNotifications]
            {
                self.triggerBatteryNotification(isLowBatteryAlert: false)
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }
    }

    /// Triggers the specialized battery notification popup
    func triggerBatteryNotification(isLowBatteryAlert: Bool = false, duration: TimeInterval = 2.0) {
        Task { @MainActor in
            coordinator.postBatteryNotification(
                level: self.levelBattery,
                isPluggedIn: self.isPluggedIn,
                isCharging: self.isCharging,
                isInLowPowerMode: self.isInLowPowerMode,
                isLowBatteryAlert: isLowBatteryAlert,
                timeToFullCharge: self.timeToFullCharge,
                duration: duration
            )
        }
    }

    /// Enables macOS Low Power Mode or opens battery settings
    func enableLowPowerMode() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let fallbackUrl = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            NSWorkspace.shared.open(fallbackUrl)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-a", "lowpowermode", "1"]
            try? process.run()
        }
    }

    /// Routes power disconnection through the same notification state as every
    /// other battery event.
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.triggerBatteryNotification(isLowBatteryAlert: false)
        }
    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }
}
