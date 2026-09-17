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
    private static let MOVE_AND_RESIZE_TITLES: [String] = [
        "Move & Resize",
        "移动与调整大小",
        "移動與調整大小",
        "移動とサイズ変更",
        "Bewegen und skalieren",
        "Déplacer et redimensionner",
        "Mover y redimensionar",
    ]

    private let windowQueue = DispatchQueue(label: "theboringteam.boringnotch.window-snap")
    private var capturedWindow: AXUIElement?
    private var capturedWindowInitialPosition: CGPoint?
    private var capturedProcessIdentifier: pid_t?
    
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
            self.capturedProcessIdentifier = nil

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
            var resolvedProcessIdentifier = pid_t(processIdentifier)
            if resolvedProcessIdentifier <= 0 {
                _ = AXUIElementGetPid(window, &resolvedProcessIdentifier)
            }
            self.capturedProcessIdentifier = resolvedProcessIdentifier > 0
                ? resolvedProcessIdentifier
                : nil
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
                self.clearCapturedWindow()
            }

            let targetSize = CGSize(width: width, height: height)
            let targetPosition = CGPoint(x: x, y: y)

            let currentPosition = self.pointAttribute(kAXPositionAttribute as CFString, from: window)
            let currentSize = self.sizeAttribute(kAXSizeAttribute as CFString, from: window)

            // Smooth interpolation animation for direct frame updates
            if let currentPos = currentPosition, let currentSz = currentSize {
                let frameCount = 6
                for step in 1...frameCount {
                    let progress = Double(step) / Double(frameCount)
                    let ease = 1.0 - pow(1.0 - progress, 3.0)

                    let intermediateWidth = currentSz.width + (targetSize.width - currentSz.width) * ease
                    let intermediateHeight = currentSz.height + (targetSize.height - currentSz.height) * ease
                    let intermediateX = currentPos.x + (targetPosition.x - currentPos.x) * ease
                    let intermediateY = currentPos.y + (targetPosition.y - currentPos.y) * ease

                    var stepSize = CGSize(width: intermediateWidth, height: intermediateHeight)
                    var stepPos = CGPoint(x: intermediateX, y: intermediateY)

                    if let sizeVal = AXValueCreate(.cgSize, &stepSize) {
                        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
                    }
                    if let posVal = AXValueCreate(.cgPoint, &stepPos) {
                        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
                    }

                    if step < frameCount {
                        usleep(16000)
                    }
                }
                reply(true)
            } else {
                var size = targetSize
                var position = targetPosition
                guard let sizeValue = AXValueCreate(.cgSize, &size),
                      let positionValue = AXValueCreate(.cgPoint, &position)
                else {
                    reply(false)
                    return
                }

                let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
                let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
                reply(sizeResult == .success && positionResult == .success)
            }
        }
    }

    /// Triggers macOS 15 native window tiling via the application's Move & Resize menu item.
    /// This plays the system native spring/tiling animation without injecting keyboard shortcuts.
    @objc func performNativeWindowLayout(_ command: Int, with reply: @escaping (Bool) -> Void) {
        windowQueue.async { [weak self] in
            guard let self,
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15,
                  let processIdentifier = self.capturedProcessIdentifier
            else {
                reply(false)
                return
            }

            // Bring the captured window to the front if needed
            if let window = self.capturedWindow {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }

            guard let menuItem = self.nativeWindowLayoutMenuItem(
                for: command,
                processIdentifier: processIdentifier
            ) else {
                NSLog("nativeWindowLayoutMenuItem not found for command %d in pid %d", command, processIdentifier)
                reply(false)
                return
            }

            let result = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
            let isSuccessful = (result == .success || result == .cannotComplete)
            if isSuccessful {
                self.clearCapturedWindow()
            }
            reply(isSuccessful)
        }
    }

    /// Triggers macOS 15 native window tiling on a specific process. Used for multi-window arrangement (e.g. 1+2).
    @objc func performWindowLayoutForProcess(_ processIdentifier: Int32, command: Int, with reply: @escaping (Bool) -> Void) {
        windowQueue.async { [weak self] in
            guard let self,
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15,
                  processIdentifier > 0
            else {
                reply(false)
                return
            }

            let application = AXUIElementCreateApplication(pid_t(processIdentifier))
            if let window = self.topmostWindow(for: application) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }

            guard let menuItem = self.nativeWindowLayoutMenuItem(
                for: command,
                processIdentifier: pid_t(processIdentifier)
            ) else {
                NSLog("performWindowLayoutForProcess: menuItem not found for command %d in pid %d", command, processIdentifier)
                reply(false)
                return
            }

            let result = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
            reply(result == .success || result == .cannotComplete)
        }
    }

    @objc func primeNativeWindowLayoutShortcuts(with reply: @escaping () -> Void) {
        windowQueue.async {
            reply()
        }
    }

    @objc func cancelWindowDrag() {
        windowQueue.async { [weak self] in
            self?.clearCapturedWindow()
        }
    }

    private func clearCapturedWindow() {
        capturedWindow = nil
        capturedWindowInitialPosition = nil
        capturedProcessIdentifier = nil
    }

    private func topmostWindow(for application: AXUIElement) -> AXUIElement? {
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
           let focusedWindowValue,
           CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() {
            return unsafeDowncast(focusedWindowValue, to: AXUIElement.self)
        }
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement],
           let first = windows.first {
            return first
        }
        return nil
    }

    private func isActionableMenuItem(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              role == (kAXMenuItemRole as String)
        else { return false }

        var subroleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String,
           subrole == "AXSectionHeader" {
            return false
        }

        // Section headers are disabled (enabled == false). Real action items are enabled.
        var enabledValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledValue) == .success,
           let enabled = enabledValue as? NSNumber,
           !enabled.boolValue {
            return false
        }

        var actionsValue: CFArray?
        guard AXUIElementCopyActionNames(element, &actionsValue) == .success,
              let actions = actionsValue as? [String],
              actions.contains(kAXPressAction as String)
        else { return false }

        return true
    }

    private func moveAndResizeActionItems(in menuBar: AXUIElement) -> [AXUIElement] {
        guard let moveAndResize = findElement(
            in: menuBar,
            matchingAnyTitle: Self.MOVE_AND_RESIZE_TITLES,
            maximumDepth: 4
        ) else { return [] }

        var candidateContainers: [AXUIElement] = [moveAndResize]
        for child in children(of: moveAndResize) {
            candidateContainers.append(child)
        }

        for container in candidateContainers {
            let actionable = children(of: container).filter { isActionableMenuItem($0) }
            if actionable.count >= 8 {
                return actionable
            }
        }
        return []
    }

    private func nativeWindowLayoutMenuItem(
        for command: Int,
        processIdentifier: pid_t? = nil
    ) -> AXUIElement? {
        guard let processIdentifier = processIdentifier ?? capturedProcessIdentifier else {
            return nil
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBar = elementAttribute(kAXMenuBarAttribute as CFString, from: application) else {
            return nil
        }

        let actionItems = moveAndResizeActionItems(in: menuBar)
        let titles = commandTitles(for: command)

        // 1. Primary path: Match by localized title within actionable items.
        // In the filtered actionable list, titles like "四等分", "左侧", "左上" are globally UNIQUE
        // because the section header with the duplicate name was disabled and filtered out!
        if !titles.isEmpty {
            if let matched = actionItems.first(where: { item in
                guard let itemTitle = stringAttribute(kAXTitleAttribute as CFString, from: item) else { return false }
                return titles.contains(itemTitle)
            }) {
                return matched
            }
        }

        // 2. Secondary path: Index-based mapping in standard system template (0: Left ... 12: Quarters)
        if command >= 0 && command < actionItems.count {
            return actionItems[command]
        }
        if command == 12, let last = actionItems.last {
            return last
        }

        // 3. Fallback: Recursive search in menu bar
        if !titles.isEmpty {
            if let moveAndResize = findElement(
                in: menuBar,
                matchingAnyTitle: Self.MOVE_AND_RESIZE_TITLES,
                maximumDepth: 4
            ),
            let commandItem = findActionableElement(
                in: moveAndResize,
                matchingAnyTitle: titles,
                maximumDepth: 3
            ) {
                return commandItem
            }

            return findActionableElement(
                in: menuBar,
                matchingAnyTitle: titles,
                maximumDepth: 6
            )
        }

        return nil
    }

    private func findActionableElement(
        in root: AXUIElement,
        matchingAnyTitle titles: [String],
        maximumDepth: Int
    ) -> AXUIElement? {
        if let title = stringAttribute(kAXTitleAttribute as CFString, from: root),
           titles.contains(title),
           isActionableMenuItem(root) {
            return root
        }
        guard maximumDepth > 0 else { return nil }

        for child in children(of: root) {
            if let match = findActionableElement(
                in: child,
                matchingAnyTitle: titles,
                maximumDepth: maximumDepth - 1
            ) {
                return match
            }
        }
        return nil
    }

    private func commandTitles(for command: Int) -> [String] {
        switch command {
        case 0:
            return ["Left", "左侧", "左側", "左", "Links", "Gauche", "Izquierda"]
        case 1:
            return ["Right", "右侧", "右側", "右", "Rechts", "Droite", "Derecha"]
        case 2:
            return ["Top", "顶部", "頂部", "上方", "Oben", "Haut", "Arriba"]
        case 3:
            return ["Bottom", "底部", "下方", "Unten", "Bas", "Abajo"]
        case 4:
            return ["Top Left", "左上", "左上方", "左上角", "Oben links", "Haut gauche", "Superior izquierda"]
        case 5:
            return ["Top Right", "右上", "右上方", "右上角", "Oben rechts", "Haut droite", "Superior derecha"]
        case 6:
            return ["Bottom Left", "左下", "左下方", "左下角", "Unten links", "Bas gauche", "Inferior izquierda"]
        case 7:
            return ["Bottom Right", "右下", "右下方", "右下角", "Unten rechts", "Bas droite", "Inferior derecha"]
        case 8:
            return ["Left & Right", "左侧与右侧", "左側與右側"]
        case 9:
            return ["Right & Left", "右侧与左侧", "右側與左側"]
        case 10:
            return ["Top & Bottom", "顶部与底部", "頂部與底部", "上方與下方"]
        case 11:
            return ["Bottom & Top", "底部与顶部", "底部與頂部", "下方與上方"]
        case 12:
            return ["Quarters", "四等分", "四等份", "Viertel"]
        case 13:
            return ["Left & Quarters", "左侧与四等分", "左側與四等分", "左侧与四等份", "左側與四等份"]
        case 14:
            return ["Right & Quarters", "右侧与四等分", "右側與四等分", "右侧与四等份", "右側與四等份"]
        case 15:
            return ["Top & Quarters", "顶部与四等分", "頂部與四等分", "上方與四等份"]
        case 16:
            return ["Bottom & Quarters", "底部与四等分", "底部與四等分", "下方与四等份", "下方與四等份"]
        default:
            return []
        }
    }

    private func findElement(
        in root: AXUIElement,
        matchingAnyTitle titles: [String],
        maximumDepth: Int
    ) -> AXUIElement? {
        if let title = stringAttribute(kAXTitleAttribute as CFString, from: root),
           titles.contains(title) {
            return root
        }
        guard maximumDepth > 0 else { return nil }

        for child in children(of: root) {
            if let match = findElement(
                in: child,
                matchingAnyTitle: titles,
                maximumDepth: maximumDepth - 1
            ) {
                return match
            }
        }
        return nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success,
        let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private func elementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func focusedApplicationProcessIdentifier() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let application = elementAttribute(
            kAXFocusedApplicationAttribute as CFString,
            from: systemWide
        ) else { return nil }

        var processIdentifier = pid_t(0)
        guard AXUIElementGetPid(application, &processIdentifier) == .success,
              processIdentifier > 0
        else { return nil }
        return processIdentifier
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
