//
//  NSScreen+UUID.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-21.
//

import AppKit
import CoreGraphics

extension NSScreen {
    private var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Used only to correlate fullscreen spaces with the one active display.
    /// Display selection and persistence no longer depend on this identifier.
    var displayUUID: String? {
        guard let displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)
        else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    var isBuiltInDisplay: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    var hasPhysicalNotch: Bool {
        isBuiltInDisplay && safeAreaInsets.top > 0
    }

    /// The only display on which Boring Notch is allowed to appear.
    /// A closed MacBook lid removes the panel from `NSScreen.screens`, so this
    /// also naturally disables the overlay in clamshell mode.
    static var supportedBuiltInDisplay: NSScreen? {
        screens.first(where: { $0.hasPhysicalNotch })
    }
}
