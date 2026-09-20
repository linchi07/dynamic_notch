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
    func setCapturedWindowFrame(_ x: Double, y: Double, width: Double, height: Double, animated: Bool, with reply: @escaping (Bool) -> Void)
    func setWindowFrame(_ processIdentifier: Int32, windowX: Double, windowY: Double, windowWidth: Double, windowHeight: Double, targetX: Double, targetY: Double, targetWidth: Double, targetHeight: Double, animated: Bool, with reply: @escaping (Bool) -> Void)
    func applyWindowFrame(_ processIdentifier: Int32, windowID: UInt32, targetX: Double, targetY: Double, targetWidth: Double, targetHeight: Double, minimizeIntermediateFrames: Bool, with reply: @escaping (Bool) -> Void)
    func primeNativeWindowLayoutShortcuts(with reply: @escaping () -> Void)
    func performNativeWindowLayout(_ command: Int, with reply: @escaping (Bool) -> Void)
    func performWindowLayoutForProcess(_ processIdentifier: Int32, command: Int, with reply: @escaping (Bool) -> Void)
    func performNativeWindowLayoutForWindow(_ processIdentifier: Int32, windowX: Double, windowY: Double, windowWidth: Double, windowHeight: Double, command: Int, with reply: @escaping (Bool) -> Void)
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

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "theboringteam.boringnotch.BoringNotchXPCHelper")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? BoringNotchXPCHelperProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
*/
