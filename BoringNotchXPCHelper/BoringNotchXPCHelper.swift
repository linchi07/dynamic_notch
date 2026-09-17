//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    private let windowQueue = DispatchQueue(label: "theboringteam.boringnotch.window-snap")
    private var capturedWindow: AXUIElement?
    private var capturedWindowInitialPosition: CGPoint?
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }

    // MARK: - Window snapping

    @objc func beginWindowDrag(
        _ processIdentifier: Int32,
        windowX: Double,
        windowY: Double,
        windowWidth: Double,
        windowHeight: Double,
        with reply: @escaping (Bool) -> Void
    ) {
        windowQueue.async { [weak self] in
            guard let self else {
                reply(false)
                return
            }
            self.capturedWindow = nil
            self.capturedWindowInitialPosition = nil

            let expectedFrame = CGRect(
                x: windowX,
                y: windowY,
                width: windowWidth,
                height: windowHeight
            )
            let matchedWindow = processIdentifier > 0
                ? self.window(for: pid_t(processIdentifier), matching: expectedFrame)
                : nil

            guard AXIsProcessTrusted(), let window = matchedWindow ?? self.focusedWindow() else {
                reply(false)
                return
            }

            var positionSettable = DarwinBoolean(false)
            var sizeSettable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable) == .success,
                  AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable) == .success,
                  positionSettable.boolValue,
                  sizeSettable.boolValue,
                  let position = self.pointAttribute(kAXPositionAttribute as CFString, from: window)
            else {
                reply(false)
                return
            }

            self.capturedWindow = window
            self.capturedWindowInitialPosition = position
            reply(true)
        }
    }

    @objc func capturedWindowHasMoved(with reply: @escaping (Bool) -> Void) {
        windowQueue.async { [weak self] in
            guard let self,
                  let window = self.capturedWindow,
                  let initialPosition = self.capturedWindowInitialPosition,
                  let currentPosition = self.pointAttribute(kAXPositionAttribute as CFString, from: window)
            else {
                reply(false)
                return
            }
            reply(hypot(currentPosition.x - initialPosition.x, currentPosition.y - initialPosition.y) >= 3)
        }
    }

    @objc func setCapturedWindowFrame(
        _ x: Double,
        y: Double,
        width: Double,
        height: Double,
        with reply: @escaping (Bool) -> Void
    ) {
        windowQueue.async { [weak self] in
            guard let self, let window = self.capturedWindow else {
                reply(false)
                return
            }
            defer {
                self.capturedWindow = nil
                self.capturedWindowInitialPosition = nil
            }

            var size = CGSize(width: width, height: height)
            var position = CGPoint(x: x, y: y)
            guard let sizeValue = AXValueCreate(.cgSize, &size),
                  let positionValue = AXValueCreate(.cgPoint, &position)
            else {
                reply(false)
                return
            }

            // Most apps behave more predictably when size is applied before position.
            let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
            reply(sizeResult == .success && positionResult == .success)
        }
    }

    @objc func cancelWindowDrag() {
        windowQueue.async { [weak self] in
            self?.capturedWindow = nil
            self?.capturedWindowInitialPosition = nil
        }
    }

    private func focusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var applicationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &applicationValue
        ) == .success,
        let applicationValue,
        CFGetTypeID(applicationValue) == AXUIElementGetTypeID()
        else { return nil }

        let application = unsafeDowncast(applicationValue, to: AXUIElement.self)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue,
        CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return nil }

        return unsafeDowncast(windowValue, to: AXUIElement.self)
    }

    private func window(for processIdentifier: pid_t, matching expectedFrame: CGRect) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
        let windows = windowsValue as? [AXUIElement]
        else { return nil }

        return windows.min { lhs, rhs in
            frameDistance(from: lhs, to: expectedFrame) < frameDistance(from: rhs, to: expectedFrame)
        }.flatMap { candidate in
            frameDistance(from: candidate, to: expectedFrame) <= 48 ? candidate : nil
        }
    }

    private func frameDistance(from window: AXUIElement, to expectedFrame: CGRect) -> CGFloat {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: window),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: window)
        else { return .greatestFiniteMagnitude }

        return abs(position.x - expectedFrame.minX)
            + abs(position.y - expectedFrame.minY)
            + abs(size.width - expectedFrame.width)
            + abs(size.height - expectedFrame.height)
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) else {
            return nil
        }
        return size
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        autoreleasepool {
            reply(Self.keyboardClient.isAvailable)
        }
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        autoreleasepool {
            reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
        }
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        autoreleasepool {
            reply(Self.keyboardClient.setBrightness(value))
        }
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        autoreleasepool {
            var brightness: Float = 0
            if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &brightness) {
                reply(true)
                return
            }

            guard let service = ioServiceFor(displayID: CGMainDisplayID()) else {
                reply(false)
                return
            }
            IOObjectRelease(service)
            reply(true)
        }
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        autoreleasepool {
            var brightness: Float = 0
            if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &brightness) {
                reply(NSNumber(value: brightness))
                return
            }
            if let service = ioServiceFor(displayID: CGMainDisplayID()) {
                defer { IOObjectRelease(service) }
                var level: Float = 0
                if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                    reply(NSNumber(value: level))
                    return
                }
            }
            reply(nil)
        }
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        autoreleasepool {
            let clamped = max(0, min(1, value))
            if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
                reply(true)
                return
            }
            if let service = ioServiceFor(displayID: CGMainDisplayID()) {
                defer { IOObjectRelease(service) }
                let succeeded = IODisplaySetFloatParameter(
                    service,
                    0,
                    kIODisplayBrightnessKey as CFString,
                    clamped
                ) == kIOReturnSuccess
                reply(succeeded)
                return
            }
            reply(false)
        }
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
