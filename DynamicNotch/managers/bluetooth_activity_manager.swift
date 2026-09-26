//
//  bluetooth_activity_manager.swift
//  DynamicNotch
//
//  Created on 2026-09-24.
//

import AppKit
import Defaults
import Foundation
import IOBluetooth

/// Manages and monitors Bluetooth connection events and resolves high-definition icons
final class BluetoothActivityManager: NSObject {
    static let shared = BluetoothActivityManager()

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var connectedDeviceAddresses: Set<String> = []
    private var recentAlertTimestamps: [String: Date] = [:]
    private var isWarmupPhase: Bool = true

    // System icon asset paths
    private static let AIRPODS_SYSTEM_ICON_PATH = "/System/Library/Frameworks/IOBluetoothUI.framework/Versions/A/Resources/AirPods.png"
    private static let BEATS_SOLO_SYSTEM_ICON_PATH = "/System/Library/Frameworks/IOBluetoothUI.framework/Versions/A/Resources/BeatsSolo3.png"
    private static let POWERBEATS_SYSTEM_ICON_PATH = "/System/Library/Frameworks/IOBluetoothUI.framework/Versions/A/Resources/Asset-B444-W.png"
    private static let POWERBEATS3_SYSTEM_ICON_PATH = "/System/Library/Frameworks/IOBluetoothUI.framework/Versions/A/Resources/Powerbeats3.png"

    private override init() {
        super.init()
    }

    /// Starts monitoring Bluetooth device connections
    func startMonitoring() {
        guard connectNotification == nil else { return }

        // Populate initial connected devices to avoid cold-start alert flood
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in paired where device.isConnected() {
                if let address = device.addressString {
                    connectedDeviceAddresses.insert(address)
                    watchDisconnect(for: device)
                }
            }
        }

        // Register for connect notifications
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(notification:device:))
        )

        // Warmup timer: ignore spurious reconnect triggers within first 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isWarmupPhase = false
        }
    }

    /// Stops monitoring Bluetooth events
    func stopMonitoring() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    // MARK: - Notification Callbacks

    @objc private func deviceDidConnect(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }

        watchDisconnect(for: device)

        // Ignore if already considered connected or during app initialization
        let wasConnected = connectedDeviceAddresses.contains(address)
        connectedDeviceAddresses.insert(address)

        if isWarmupPhase || wasConnected {
            return
        }

        // Debounce: prevent duplicate notifications within 5 seconds for the same device
        if let lastAlertDate = recentAlertTimestamps[address], Date().timeIntervalSince(lastAlertDate) < 5.0 {
            return
        }
        recentAlertTimestamps[address] = Date()

        guard Defaults[.SHOW_BLUETOOTH_NOTIFICATIONS] else { return }

        // Give the device 0.2s to establish battery and profile status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.triggerConnectionAlert(for: device)
        }
    }

    @objc private func deviceDidDisconnect(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        connectedDeviceAddresses.remove(address)
        disconnectNotifications.removeValue(forKey: address)?.unregister()
    }

    private func watchDisconnect(for device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        if let disconnectNote = device.register(forDisconnectNotification: self, selector: #selector(deviceDidDisconnect(notification:device:))) {
            disconnectNotifications[address] = disconnectNote
        }
    }

    // MARK: - Alert Dispatch

    private func triggerConnectionAlert(for device: IOBluetoothDevice) {
        let name = device.name ?? device.nameOrAddress ?? "蓝牙设备"
        let (deviceType, isAirPods, symbolName) = resolveDeviceType(for: device, name: name)

        guard shouldAlert(for: deviceType) else { return }

        let customImage = resolveHighDefIcon(deviceType: deviceType, symbolName: symbolName)
        let batteryLevel = resolveBatteryLevel(for: device)

        let payload = BluetoothDeviceNotificationPayload(
            deviceName: name,
            deviceType: deviceType,
            batteryLevel: batteryLevel,
            customImage: customImage,
            symbolName: symbolName,
            isAirPods: isAirPods
        )

        Task { @MainActor in
            BoringViewCoordinator.shared.postBluetoothNotification(payload: payload)
        }
    }

    /// Determines whether an alert should be triggered for the specified device type
    private func shouldAlert(for deviceType: BluetoothDeviceType) -> Bool {
        guard Defaults[.SHOW_BLUETOOTH_NOTIFICATIONS] else { return false }

        switch deviceType {
        case .airPods, .beats, .headphones, .speaker:
            return Defaults[.BLUETOOTH_ALERT_AUDIO_DEVICES]
        case .mouse:
            return Defaults[.BLUETOOTH_ALERT_MOUSE_DEVICES]
        case .keyboard:
            return Defaults[.BLUETOOTH_ALERT_KEYBOARD_DEVICES]
        case .gameController:
            return Defaults[.BLUETOOTH_ALERT_GAME_CONTROLLERS]
        case .watch, .phone, .pad, .generic:
            return Defaults[.BLUETOOTH_ALERT_OTHER_DEVICES]
        }
    }

    // MARK: - Device Classification & Icon Resolution

    private func resolveDeviceType(for device: IOBluetoothDevice, name: String) -> (BluetoothDeviceType, Bool, String) {
        let pid = getUInt16Property("productID", from: device)
        let vid = getUInt16Property("vendorID", from: device)
        let lowerName = name.lowercased()

        // 1. Apple Devices (VID 0x004C)
        let isApple = vid == 0x004C || getBoolProperty("isAppleDevice", from: device)

        if isApple {
            // Check AirPods Pro
            if [0x2013, 0x2019, 0x2024, 0x2027].contains(pid) || lowerName.contains("airpods pro") {
                return (.airPods(.pro), true, "airpodspro")
            }
            // Check AirPods Max
            if [0x200A, 0x200E].contains(pid) || lowerName.contains("airpods max") {
                return (.airPods(.max), true, "airpodsmax")
            }
            // Check AirPods 3 / 4
            if [0x2014].contains(pid) || lowerName.contains("airpods 3") || lowerName.contains("airpods (3") {
                return (.airPods(.gen3), true, "airpods.gen3")
            }
            if [0x201E, 0x202B].contains(pid) || lowerName.contains("airpods 4") || lowerName.contains("airpods (4") {
                return (.airPods(.gen4), true, "airpods.gen3")
            }
            // Check AirPods Classic (Gen 1/2)
            if [0x2002, 0x200F].contains(pid) || lowerName.contains("airpods") {
                return (.airPods(.classic), true, "airpods")
            }

            // Check Beats
            if pid == 0x2006 || lowerName.contains("solo") {
                return (.beats(.solo), false, "beats.headphones")
            }
            if pid == 0x2009 || lowerName.contains("studio") {
                return (.beats(.studio), false, "beats.headphones")
            }
            if pid == 0x200B || lowerName.contains("powerbeats pro") {
                return (.beats(.powerbeatsPro), false, "beats.powerbeatspro")
            }
            if pid == 0x2011 || lowerName.contains("fit pro") {
                return (.beats(.fitPro), false, "beats.fitpro")
            }
            if pid == 0x2010 || lowerName.contains("studio buds") {
                return (.beats(.studioBuds), false, "beats.studiobuds")
            }
            if lowerName.contains("beats") {
                return (.beats(.generic), false, "beats.headphones")
            }

            // Check Apple Watch / iPhone / iPad
            if lowerName.contains("watch") {
                return (.watch, false, "applewatch")
            }
            if lowerName.contains("iphone") {
                return (.phone, false, "iphone")
            }
            if lowerName.contains("ipad") {
                return (.pad, false, "ipad")
            }
        }

        // 2. Peripheral classification based on device properties and classes
        let isGamePad = getBoolProperty("isGameController", from: device)
            || getBoolProperty("isXboxGameController", from: device)
            || getBoolProperty("isSonyGameController", from: device)
            || getBoolProperty("isNintendoGameController", from: device)
            || lowerName.contains("controller") || lowerName.contains("xbox")
            || lowerName.contains("dualsense") || lowerName.contains("dualshock")
            || lowerName.contains("joy-con") || lowerName.contains("gamepad")
            || (device.deviceClassMajor == 5 && (device.deviceClassMinor == 4 || device.deviceClassMinor == 8))
        if isGamePad {
            return (.gameController, false, "gamecontroller")
        }

        let isPointer = getBoolProperty("isPointingDevice", from: device)
            || getBoolProperty("isLowEnergyPointer", from: device)
            || lowerName.contains("mouse") || lowerName.contains("trackpad") || lowerName.contains("touchpad")
            || lowerName.contains("pebble") || lowerName.contains("mx master") || lowerName.contains("anywhere")
            || (device.deviceClassMajor == 5 && (device.deviceClassMinor == 32 || device.deviceClassMinor == 128 || (device.deviceClassMinor & 0x80) != 0))
        if isPointer {
            return (.mouse, false, "computermouse")
        }

        let isKeybd = getBoolProperty("isKeyboardDevice", from: device)
            || getBoolProperty("isLowEnergyKeyboard", from: device)
            || lowerName.contains("keyboard") || lowerName.contains("keychron") || lowerName.contains("nuphy")
            || lowerName.contains("filco") || lowerName.contains("hhkb")
            || (device.deviceClassMajor == 5 && (device.deviceClassMinor == 16 || device.deviceClassMinor == 64 || (device.deviceClassMinor & 0x40) != 0))
        if isKeybd {
            return (.keyboard, false, "keyboard")
        }

        // 3. Audio Devices (Headphones vs Speaker)
        let isAudio = device.deviceClassMajor == 4
            || getBoolProperty("isAudioSink", from: device)
            || getBoolProperty("isHeadsetDevice", from: device)
            || getBoolProperty("isAdvancedAppleAudioDevice", from: device)
            || lowerName.contains("headphone") || lowerName.contains("earphone") || lowerName.contains("headset")
            || lowerName.contains("earbuds") || lowerName.contains("buds") || lowerName.contains("soundcore")
            || lowerName.contains("qc35") || lowerName.contains("wh-1000") || lowerName.contains("bose")
            || lowerName.contains("speaker") || lowerName.contains("soundlink")

        if isAudio {
            if lowerName.contains("speaker") || lowerName.contains("soundlink") || lowerName.contains("soundcore") {
                return (.speaker, false, "speaker.wave.2")
            }
            return (.headphones, false, "headphones")
        }

        return (.generic, false, "antenna.radiowaves.left.and.right")
    }

    /// Resolves high-definition 3D rendered icons for AirPods and Beats accessories
    private func resolveHighDefIcon(deviceType: BluetoothDeviceType, symbolName: String) -> NSImage? {
        switch deviceType {
        case .airPods(let model):
            switch model {
            case .classic:
                // Use system official 3D AirPods render if available
                if let img = NSImage(contentsOfFile: Self.AIRPODS_SYSTEM_ICON_PATH) {
                    return img
                }
            case .pro, .gen3, .gen4, .max:
                // Check if app bundle has custom asset
                if let assetImage = NSImage(named: symbolName) {
                    return assetImage
                }
                // If classic image exists as fallback
                if let fallback = NSImage(contentsOfFile: Self.AIRPODS_SYSTEM_ICON_PATH) {
                    return fallback
                }
            }

        case .beats(let model):
            switch model {
            case .solo, .studio, .generic:
                if let img = NSImage(contentsOfFile: Self.BEATS_SOLO_SYSTEM_ICON_PATH) {
                    return img
                }
            case .powerbeatsPro:
                if let img = NSImage(contentsOfFile: Self.POWERBEATS_SYSTEM_ICON_PATH) {
                    return img
                }
            case .studioBuds, .fitPro:
                if let img = NSImage(contentsOfFile: Self.POWERBEATS3_SYSTEM_ICON_PATH) {
                    return img
                }
            }

        default:
            break
        }

        return nil
    }

    /// Extracts battery level percentage (0-100) if reported by the device
    private func resolveBatteryLevel(for device: IOBluetoothDevice) -> Int? {
        let single = getUInt8Property("batteryPercentSingle", from: device)
        if single > 0 && single <= 100 {
            return Int(single)
        }

        let combined = getUInt8Property("batteryPercentCombined", from: device)
        if combined > 0 && combined <= 100 {
            return Int(combined)
        }

        let left = getUInt8Property("batteryPercentLeft", from: device)
        if left > 0 && left <= 100 {
            return Int(left)
        }

        let right = getUInt8Property("batteryPercentRight", from: device)
        if right > 0 && right <= 100 {
            return Int(right)
        }

        return nil
    }

    // MARK: - Dynamic Property Invocation Helpers

    private func getUInt16Property(_ selectorName: String, from object: AnyObject) -> UInt16 {
        let sel = NSSelectorFromString(selectorName)
        guard object.responds(to: sel) else { return 0 }
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt16
        let fn = unsafeBitCast(object.method(for: sel), to: Fn.self)
        return fn(object, sel)
    }

    private func getUInt8Property(_ selectorName: String, from object: AnyObject) -> UInt8 {
        let sel = NSSelectorFromString(selectorName)
        guard object.responds(to: sel) else { return 0 }
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt8
        let fn = unsafeBitCast(object.method(for: sel), to: Fn.self)
        return fn(object, sel)
    }

    private func getBoolProperty(_ selectorName: String, from object: AnyObject) -> Bool {
        let sel = NSSelectorFromString(selectorName)
        guard object.responds(to: sel) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        let fn = unsafeBitCast(object.method(for: sel), to: Fn.self)
        return fn(object, sel)
    }
}
