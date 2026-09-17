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
    private struct MenuShortcut {
        let virtualKey: CGKeyCode
        let flags: CGEventFlags
        let rawModifiers: UInt64
        let character: String?
    }

    private struct ShortcutPreferenceLookup {
        let wasFound: Bool
        let shortcut: MenuShortcut?
    }

    private static let symbolicHotKeyIDByCommand: [Int: Int] = [
        0: 240, // Left
        1: 241, // Right
        2: 242, // Top
        3: 243, // Bottom
        4: 244, // Top Left
        5: 245, // Top Right
        6: 246, // Bottom Left
        7: 247, // Bottom Right
        8: 248, // Left & Right
        9: 249, // Right & Left
        10: 250, // Top & Bottom
        11: 251, // Bottom & Top
        12: 256, // Quarters
    ]

    private static let symbolicHotKeyDomain = "com.apple.symbolichotkeys" as CFString
    private static let symbolicHotKeyPreference = "AppleSymbolicHotKeys" as CFString

    private let windowQueue = DispatchQueue(label: "theboringteam.boringnotch.window-snap")
    private let usesAccessibilityMenuPress = false
    private var capturedWindow: AXUIElement?
    private var capturedWindowInitialPosition: CGPoint?
    private var capturedProcessIdentifier: pid_t?
    private var cachedLayoutShortcuts: [Int: MenuShortcut] = [:]
    private var inspectedLayoutCommands: Set<Int> = []
    
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
                self.capturedWindow = nil
                self.capturedWindowInitialPosition = nil
                self.capturedProcessIdentifier = nil
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

    /// Immediately posts the cached shortcut, then refreshes it from macOS's
    /// symbolic hotkey preferences. A changed shortcut is cached and posted once more.
    @objc func performNativeWindowLayout(_ command: Int, with reply: @escaping (Bool) -> Void) {
        windowQueue.async { [weak self] in
            guard let self,
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15,
                  let processIdentifier = self.capturedProcessIdentifier
            else {
                self?.clearCapturedWindow()
                reply(false)
                return
            }

            let cachedShortcut = self.optimisticShortcut(for: command)
            var posted = false
            if let cachedShortcut {
                self.logShortcut(cachedShortcut, title: "cached command \(command)")
                posted = self.postShortcut(cachedShortcut, to: processIdentifier)
            }

            let preferenceLookup = self.symbolicShortcutPreference(for: command)
            var menuItem: AXUIElement?
            var refreshedShortcut: MenuShortcut?

            if preferenceLookup.wasFound {
                self.inspectedLayoutCommands.insert(command)
                refreshedShortcut = preferenceLookup.shortcut
                if let refreshedShortcut {
                    self.cachedLayoutShortcuts[command] = refreshedShortcut
                } else {
                    self.cachedLayoutShortcuts.removeValue(forKey: command)
                }
            } else {
                // Keep the AX menu reader only as a compatibility fallback for
                // commands that are absent from AppleSymbolicHotKeys.
                menuItem = self.nativeWindowLayoutMenuItem(
                    for: command,
                    processIdentifier: processIdentifier
                )
                if let menuItem {
                    self.inspectedLayoutCommands.insert(command)
                    refreshedShortcut = self.menuShortcut(for: menuItem, command: command)
                    if let refreshedShortcut {
                        self.cachedLayoutShortcuts[command] = refreshedShortcut
                    } else {
                        self.cachedLayoutShortcuts.removeValue(forKey: command)
                    }
                }
            }

            // Retained as an experiment switch, but deliberately disabled: AXPress
            // can trigger a different/global relayout path in some applications.
            if self.usesAccessibilityMenuPress, menuItem == nil {
                menuItem = self.nativeWindowLayoutMenuItem(
                    for: command,
                    processIdentifier: processIdentifier
                )
            }
            if self.usesAccessibilityMenuPress, let menuItem {
                let result = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
                if result == .success || result == .cannotComplete {
                    self.clearCapturedWindow()
                    reply(true)
                    return
                }
            }

            if let refreshedShortcut,
               !self.shortcutsMatch(refreshedShortcut, cachedShortcut) {
                let title = menuItem.flatMap {
                    self.stringAttribute(kAXTitleAttribute as CFString, from: $0)
                } ?? "symbolic command \(command)"
                self.logShortcut(refreshedShortcut, title: title)
                posted = self.postShortcut(refreshedShortcut, to: processIdentifier) || posted
            }

            self.clearCapturedWindow()
            reply(posted)
        }
    }

    @objc func primeNativeWindowLayoutShortcuts(with reply: @escaping () -> Void) {
        windowQueue.async { [weak self] in
            guard let self,
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15
            else {
                reply()
                return
            }

            for command in Self.symbolicHotKeyIDByCommand.keys {
                let lookup = self.symbolicShortcutPreference(for: command)
                guard lookup.wasFound else { continue }
                self.inspectedLayoutCommands.insert(command)
                if let shortcut = lookup.shortcut {
                    self.cachedLayoutShortcuts[command] = shortcut
                } else {
                    self.cachedLayoutShortcuts.removeValue(forKey: command)
                }
            }
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

        let moveAndResizeTitles = [
            "Move & Resize",
            "移动与调整大小",
            "移動與調整大小",
        ]
        let commandTitles: [String]
        switch command {
        case 0:
            commandTitles = ["Left", "左侧", "左側"]
        case 1:
            commandTitles = ["Right", "右侧", "右側"]
        case 2:
            commandTitles = ["Top", "顶部", "頂部", "上方"]
        case 3:
            commandTitles = ["Bottom", "底部", "下方"]
        case 4:
            commandTitles = ["Top Left", "左上", "左上方", "左上角"]
        case 5:
            commandTitles = ["Top Right", "右上", "右上方", "右上角"]
        case 6:
            commandTitles = ["Bottom Left", "左下", "左下方", "左下角"]
        case 7:
            commandTitles = ["Bottom Right", "右下", "右下方", "右下角"]
        case 8:
            commandTitles = ["Left & Right", "左侧与右侧", "左側與右側"]
        case 9:
            commandTitles = ["Right & Left", "右侧与左侧", "右側與左側"]
        case 10:
            commandTitles = ["Top & Bottom", "顶部与底部", "頂部與底部", "上方與下方"]
        case 11:
            commandTitles = ["Bottom & Top", "底部与顶部", "底部與頂部", "下方與上方"]
        case 12:
            commandTitles = ["Quarters", "四等分", "四等份"]
        case 13:
            commandTitles = [
                "Left & Quarters",
                "左侧与四等分",
                "左側與四等分",
                "左侧与四等份",
                "左側與四等份",
            ]
        case 14:
            commandTitles = [
                "Right & Quarters",
                "右侧与四等分",
                "右側與四等分",
                "右侧与四等份",
                "右側與四等份",
            ]
        case 15:
            commandTitles = [
                "Top & Quarters",
                "顶部与四等分",
                "頂部與四等分",
                "上方與四等份",
            ]
        case 16:
            commandTitles = [
                "Bottom & Quarters",
                "底部与四等分",
                "底部與四等分",
                "下方與四等份",
            ]
        default:
            return nil
        }

        if let moveAndResize = findElement(
            in: menuBar,
            matchingAnyTitle: moveAndResizeTitles,
            maximumDepth: 4
        ),
        let commandItem = findElement(
            in: moveAndResize,
            matchingAnyTitle: commandTitles,
            maximumDepth: 3
        ) {
            return commandItem
        }

        // Compound layout titles are specific enough to safely locate globally
        // if an app flattens or lazily exposes the Window submenu.
        guard command >= 8 else { return nil }
        return findElement(
            in: menuBar,
            matchingAnyTitle: commandTitles,
            maximumDepth: 7
        )
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

    private func symbolicShortcutPreference(for command: Int) -> ShortcutPreferenceLookup {
        guard let symbolicHotKeyID = Self.symbolicHotKeyIDByCommand[command] else {
            return ShortcutPreferenceLookup(wasFound: false, shortcut: nil)
        }

        CFPreferencesAppSynchronize(Self.symbolicHotKeyDomain)
        guard let hotKeys = CFPreferencesCopyAppValue(
            Self.symbolicHotKeyPreference,
            Self.symbolicHotKeyDomain
        ) as? [String: Any],
        let entry = hotKeys[String(symbolicHotKeyID)] as? [String: Any]
        else {
            return ShortcutPreferenceLookup(wasFound: false, shortcut: nil)
        }

        let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
        guard enabled,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber],
              parameters.count >= 3
        else {
            return ShortcutPreferenceLookup(wasFound: true, shortcut: nil)
        }

        let characterCode = parameters[0].uint32Value
        let virtualKey = CGKeyCode(truncating: parameters[1])
        let storedFlags = CGEventFlags(rawValue: parameters[2].uint64Value)
        var logicalFlags = storedFlags

        // Fn is a physical key-layer transformation, not part of the logical
        // shortcut. The symbolic-hotkey plist includes it (and NumericPad for
        // some arrow entries) as event metadata, but posting those flags would
        // transform the already-resolved 123...126 arrow key codes again.
        logicalFlags.remove(.maskSecondaryFn)
        if (123...126).contains(Int(virtualKey)) {
            logicalFlags.remove(.maskNumericPad)
        }

        let character: String?
        if characterCode == UInt32(UInt16.max) {
            character = nil
        } else if let scalar = UnicodeScalar(characterCode) {
            character = String(scalar)
        } else {
            character = nil
        }

        let shortcut = MenuShortcut(
            virtualKey: virtualKey,
            flags: logicalFlags,
            rawModifiers: logicalFlags.rawValue,
            character: character
        )
        NSLog(
            "Loaded window symbolic hotkey %d for command %d: key=%d storedFlags=%llu logicalFlags=%llu",
            symbolicHotKeyID,
            command,
            virtualKey,
            storedFlags.rawValue,
            logicalFlags.rawValue
        )
        return ShortcutPreferenceLookup(wasFound: true, shortcut: shortcut)
    }

    private func menuShortcut(for menuItem: AXUIElement, command: Int) -> MenuShortcut? {
        var virtualKeyValue: CFTypeRef?
        var modifierValue: CFTypeRef?
        var characterValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            menuItem,
            kAXMenuItemCmdVirtualKeyAttribute as CFString,
            &virtualKeyValue
        ) == .success,
        let virtualKeyNumber = virtualKeyValue as? NSNumber,
        AXUIElementCopyAttributeValue(
            menuItem,
            kAXMenuItemCmdModifiersAttribute as CFString,
            &modifierValue
        ) == .success,
        let modifierNumber = modifierValue as? NSNumber
        else { return nil }

        _ = AXUIElementCopyAttributeValue(
            menuItem,
            kAXMenuItemCmdCharAttribute as CFString,
            &characterValue
        )

        let rawModifiers = modifierNumber.uint32Value
        var flags: CGEventFlags = []
        if rawModifiers & (1 << 0) != 0 { flags.insert(.maskShift) }
        if rawModifiers & (1 << 1) != 0 { flags.insert(.maskAlternate) }
        if rawModifiers & (1 << 2) != 0 { flags.insert(.maskControl) }
        if rawModifiers & (1 << 3) == 0 { flags.insert(.maskCommand) }

        let virtualKey = CGKeyCode(truncating: virtualKeyNumber)
        return MenuShortcut(
            virtualKey: virtualKey,
            flags: flags,
            rawModifiers: UInt64(rawModifiers),
            character: characterValue as? String
        )
    }

    private func optimisticShortcut(for command: Int) -> MenuShortcut? {
        if let cached = cachedLayoutShortcuts[command] {
            return cached
        }
        guard !inspectedLayoutCommands.contains(command) else { return nil }
        return defaultShortcut(for: command)
    }

    private func defaultShortcut(for command: Int) -> MenuShortcut? {
        let virtualKey: CGKeyCode
        switch command {
        case 0, 8, 13:
            virtualKey = 123 // Left Arrow
        case 1, 9, 14:
            virtualKey = 124 // Right Arrow
        case 3, 11, 16:
            virtualKey = 125 // Down Arrow
        case 2, 10, 15:
            virtualKey = 126 // Up Arrow
        default:
            return nil
        }

        var flags: CGEventFlags = [.maskControl]
        switch command {
        case 0...3:
            break
        case 8...11:
            flags.insert(.maskShift)
        case 13...16:
            flags.insert(.maskShift)
            flags.insert(.maskAlternate)
        default:
            return nil
        }

        return MenuShortcut(
            virtualKey: virtualKey,
            flags: flags,
            rawModifiers: flags.rawValue,
            character: nil
        )
    }

    private func shortcutsMatch(_ lhs: MenuShortcut?, _ rhs: MenuShortcut?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.virtualKey == rhs.virtualKey
                && lhs.flags.rawValue == rhs.flags.rawValue
        default:
            return false
        }
    }

    private func postShortcut(_ shortcut: MenuShortcut, to processIdentifier: pid_t) -> Bool {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: shortcut.virtualKey,
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: shortcut.virtualKey,
            keyDown: false
        ) else { return false }

        keyDown.flags = shortcut.flags
        keyUp.flags = shortcut.flags
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }

    private func logShortcut(_ shortcut: MenuShortcut, title: String) {
        NSLog(
            "Window layout menu item '%@': key=%@ modifiers=%@ character=%@",
            title,
            String(shortcut.virtualKey),
            String(shortcut.rawModifiers),
            shortcut.character ?? "none"
        )
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
