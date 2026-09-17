//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    func beginWindowDrag(_ processIdentifier: Int32, windowX: Double, windowY: Double, windowWidth: Double, windowHeight: Double, with reply: @escaping (Bool) -> Void)
    func capturedWindowHasMoved(with reply: @escaping (Bool) -> Void)
    func setCapturedWindowFrame(_ x: Double, y: Double, width: Double, height: Double, with reply: @escaping (Bool) -> Void)
    func primeNativeWindowLayoutShortcuts(with reply: @escaping () -> Void)
    func performNativeWindowLayout(_ command: Int, with reply: @escaping (Bool) -> Void)
    func cancelWindowDrag()
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
}
