//
//  bluetooth_manager_tests.swift
//  DynamicNotchTests
//
//  Created on 2026-09-24.
//

import AppKit
import Foundation

// MARK: - Mock / Standalone Logic Verification

enum AirPodsModel: String, Equatable {
    case classic = "AirPods"
    case pro = "AirPods Pro"
    case gen3 = "AirPods (3rd gen)"
    case gen4 = "AirPods 4"
    case max = "AirPods Max"
}

enum BeatsModel: String, Equatable {
    case solo = "Beats Solo"
    case studio = "Beats Studio"
    case studioBuds = "Beats Studio Buds"
    case fitPro = "Beats Fit Pro"
    case powerbeatsPro = "Powerbeats Pro"
    case generic = "Beats"
}

enum BluetoothDeviceType: Equatable {
    case airPods(AirPodsModel)
    case beats(BeatsModel)
    case headphones
    case speaker
    case mouse
    case keyboard
    case gameController
    case watch
    case phone
    case pad
    case generic
}

struct BluetoothDeviceNotificationPayload: Equatable {
    var deviceName: String
    var deviceType: BluetoothDeviceType
    var batteryLevel: Int?
    var customImage: NSImage?
    var symbolName: String
    var isAirPods: Bool

    static func == (lhs: BluetoothDeviceNotificationPayload, rhs: BluetoothDeviceNotificationPayload) -> Bool {
        lhs.deviceName == rhs.deviceName &&
        lhs.deviceType == rhs.deviceType &&
        lhs.batteryLevel == rhs.batteryLevel &&
        lhs.symbolName == rhs.symbolName &&
        lhs.isAirPods == rhs.isAirPods
    }
}

final class BluetoothLogicTestHelper {
    static let AIRPODS_SYSTEM_ICON_PATH = "/System/Library/Frameworks/IOBluetoothUI.framework/Versions/A/Resources/AirPods.png"

    static func classify(vid: UInt32, pid: UInt32, name: String, major: UInt32 = 0, minor: UInt32 = 0) -> (BluetoothDeviceType, Bool, String) {
        let lowerName = name.lowercased()
        let isApple = vid == 0x004C

        if isApple {
            if [0x2013, 0x2019, 0x2024, 0x2027].contains(pid) || lowerName.contains("airpods pro") {
                return (.airPods(.pro), true, "airpodspro")
            }
            if [0x200A, 0x200E].contains(pid) || lowerName.contains("airpods max") {
                return (.airPods(.max), true, "airpodsmax")
            }
            if [0x2014].contains(pid) || lowerName.contains("airpods 3") || lowerName.contains("airpods (3") {
                return (.airPods(.gen3), true, "airpods.gen3")
            }
            if [0x201E, 0x202B].contains(pid) || lowerName.contains("airpods 4") || lowerName.contains("airpods (4") {
                return (.airPods(.gen4), true, "airpods.gen3")
            }
            if [0x2002, 0x200F].contains(pid) || lowerName.contains("airpods") {
                return (.airPods(.classic), true, "airpods")
            }

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

        if lowerName.contains("controller") || lowerName.contains("xbox") || lowerName.contains("dualsense") {
            return (.gameController, false, "gamecontroller")
        }

        if lowerName.contains("mouse") || lowerName.contains("trackpad") || major == 5 && (minor == 32 || minor == 128) {
            return (.mouse, false, "computermouse")
        }

        if lowerName.contains("keyboard") || major == 5 && (minor == 16 || minor == 64) {
            return (.keyboard, false, "keyboard")
        }

        if major == 4 || lowerName.contains("headphone") || lowerName.contains("qc35") || lowerName.contains("wh-1000") || lowerName.contains("bose") {
            if lowerName.contains("speaker") || lowerName.contains("soundlink") {
                return (.speaker, false, "speaker.wave.2")
            }
            return (.headphones, false, "headphones")
        }

        return (.generic, false, "antenna.radiowaves.left.and.right")
    }

    static func resolveIcon(type: BluetoothDeviceType) -> NSImage? {
        if case .airPods(let model) = type, model == .classic {
            return NSImage(contentsOfFile: AIRPODS_SYSTEM_ICON_PATH)
        }
        return nil
    }
    static func shouldAlert(
        deviceType: BluetoothDeviceType,
        masterEnabled: Bool = true,
        audioEnabled: Bool = true,
        mouseEnabled: Bool = true,
        keyboardEnabled: Bool = true,
        controllersEnabled: Bool = true,
        otherEnabled: Bool = false
    ) -> Bool {
        guard masterEnabled else { return false }
        switch deviceType {
        case .airPods, .beats, .headphones, .speaker:
            return audioEnabled
        case .mouse:
            return mouseEnabled
        case .keyboard:
            return keyboardEnabled
        case .gameController:
            return controllersEnabled
        case .watch, .phone, .pad, .generic:
            return otherEnabled
        }
    }
}

// MARK: - Test Suite Runner

func runTests() {
    print("🚀 Starting Bluetooth Activity Manager Tests...")
    var passed = 0
    var failed = 0

    func assert(_ condition: Bool, _ message: String) {
        if condition {
            print("  ✅ PASS: \(message)")
            passed += 1
        } else {
            print("  ❌ FAIL: \(message)")
            failed += 1
        }
    }

    // Test 1: AirPods Classic by PID
    let (t1, isA1, s1) = BluetoothLogicTestHelper.classify(vid: 0x004C, pid: 0x2002, name: "lin的AirPods")
    assert(t1 == .airPods(.classic), "0x2002 should classify as AirPods classic")
    assert(isA1 == true, "0x2002 isAirPods should be true")
    assert(s1 == "airpods", "Symbol should be 'airpods'")

    // Test 2: AirPods Pro 2 by PID
    let (t2, isA2, s2) = BluetoothLogicTestHelper.classify(vid: 0x004C, pid: 0x2024, name: "AirPods Pro")
    assert(t2 == .airPods(.pro), "0x2024 should classify as AirPods Pro")
    assert(isA2 == true, "AirPods Pro isAirPods should be true")
    assert(s2 == "airpodspro", "Symbol should be 'airpodspro'")

    // Test 3: AirPods Max by PID & Name
    let (t3, isA3, s3) = BluetoothLogicTestHelper.classify(vid: 0x004C, pid: 0x200A, name: "Alexander's AirPods Max")
    assert(t3 == .airPods(.max), "0x200A should classify as AirPods Max")
    assert(isA3 == true, "AirPods Max isAirPods should be true")
    assert(s3 == "airpodsmax", "Symbol should be 'airpodsmax'")

    // Test 4: AirPods 3 by PID
    let (t4, isA4, s4) = BluetoothLogicTestHelper.classify(vid: 0x004C, pid: 0x2014, name: "AirPods 3")
    assert(t4 == .airPods(.gen3), "0x2014 should classify as AirPods 3")
    assert(isA4 == true, "AirPods 3 isAirPods should be true")
    assert(s4 == "airpods.gen3", "Symbol should be 'airpods.gen3'")

    // Test 5: AirPods 4 by Name
    let (t5, isA5, s5) = BluetoothLogicTestHelper.classify(vid: 0x004C, pid: 0x201E, name: "AirPods 4 with ANC")
    assert(t5 == .airPods(.gen4), "0x201E should classify as AirPods 4")
    assert(isA5 == true, "AirPods 4 isAirPods should be true")
    assert(s5 == "airpods.gen3", "Symbol should be 'airpods.gen3'")

    // Test 6: Third-party Headphones (Bose QC35 II)
    let (t6, isA6, s6) = BluetoothLogicTestHelper.classify(vid: 0x009E, pid: 0x4020, name: "Bose QC35 II", major: 4, minor: 6)
    assert(t6 == .headphones, "Bose QC35 II should classify as headphones")
    assert(isA6 == false, "Bose QC35 II is not AirPods")
    assert(s6 == "headphones", "Symbol should be 'headphones'")

    // Test 7: Mouse (MX Master 4 / Pebble)
    let (t7, isA7, s7) = BluetoothLogicTestHelper.classify(vid: 0x046D, pid: 0xB010, name: "Bluetooth Mouse M557", major: 5, minor: 32)
    assert(t7 == .mouse, "M557 should classify as mouse")
    assert(isA7 == false, "Mouse is not AirPods")
    assert(s7 == "computermouse", "Symbol should be 'computermouse'")

    // Test 8: Game Controller (Xbox Wireless Controller)
    let (t8, isA8, s8) = BluetoothLogicTestHelper.classify(vid: 0x045E, pid: 0x02FD, name: "Xbox Wireless Controller")
    assert(t8 == .gameController, "Xbox Controller should classify as game controller")
    assert(isA8 == false, "Game controller is not AirPods")
    assert(s8 == "gamecontroller", "Symbol should be 'gamecontroller'")

    // Test 9: Keyboard
    let (t9, isA9, s9) = BluetoothLogicTestHelper.classify(vid: 0, pid: 0, name: "Keychron K2 Pro", major: 5, minor: 16)
    assert(t9 == .keyboard, "Keychron K2 Pro should classify as keyboard")
    assert(isA9 == false, "Keyboard is not AirPods")
    assert(s9 == "keyboard", "Symbol should be 'keyboard'")

    // Test 10: Speaker
    let (t10, _, s10) = BluetoothLogicTestHelper.classify(vid: 0, pid: 0, name: "Bose SoundLink Flex", major: 4, minor: 5)
    assert(t10 == .speaker, "Bose SoundLink should classify as speaker")
    assert(s10 == "speaker.wave.2", "Speaker symbol should be speaker.wave.2")

    // Test 11: Category Filtering (shouldAlert)
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .airPods(.classic)) == true, "AirPods alert should be allowed by default")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .mouse) == true, "Mouse alert should be allowed by default")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .keyboard) == true, "Keyboard alert should be allowed by default")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .gameController) == true, "Game controller alert should be allowed by default")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .watch) == false, "Watch alert should be disabled by default")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .airPods(.classic), audioEnabled: false) == false, "Disabling audio filter should suppress AirPods")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .mouse, mouseEnabled: false) == false, "Disabling mouse filter should suppress mouse")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .watch, otherEnabled: true) == true, "Enabling other filter should allow watch")
    assert(BluetoothLogicTestHelper.shouldAlert(deviceType: .airPods(.classic), masterEnabled: false) == false, "Disabling master switch should suppress all")

    // Test 12: System AirPods 3D Image file resolution
    let icon = BluetoothLogicTestHelper.resolveIcon(type: .airPods(.classic))
    assert(icon != nil, "System AirPods.png 3D icon should be loadable from macOS resources")
    if let sz = icon?.size {
        assert(sz.width > 0 && sz.height > 0, "Icon dimensions valid: \(sz.width)x\(sz.height)")
    }

    // Test 13: Payload equality
    let p1 = BluetoothDeviceNotificationPayload(
        deviceName: "lin的AirPods",
        deviceType: .airPods(.classic),
        batteryLevel: 90,
        customImage: icon,
        symbolName: "airpods",
        isAirPods: true
    )
    let p2 = BluetoothDeviceNotificationPayload(
        deviceName: "lin的AirPods",
        deviceType: .airPods(.classic),
        batteryLevel: 90,
        customImage: icon,
        symbolName: "airpods",
        isAirPods: true
    )
    assert(p1 == p2, "Payloads with identical properties should be equal")

    print("\n🏁 Test Results: \(passed) passed, \(failed) failed")
    if failed > 0 {
        exit(1)
    }
}

runTests()
