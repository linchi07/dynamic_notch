import Foundation
import Cocoa

final class XPCHelperClient: NSObject, @unchecked Sendable {
    nonisolated static let shared = XPCHelperClient()
    
    private let helper = DynamicNotchXPCHelper()
    
    @MainActor
    func shutdown() {
        AccessibilityAuthorization.shared.stopMonitoring()
    }
    
    // MARK: - Accessibility
    
    @MainActor
    func requestAccessibilityAuthorization() {
        AccessibilityAuthorization.shared.request()
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        await AccessibilityAuthorization.shared.refresh()
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        await MainActor.run {
            let authorization = AccessibilityAuthorization.shared
            if promptIfNeeded {
                authorization.request()
            }
            return authorization.refresh()
        }
    }

    // MARK: - Window snapping

    nonisolated func beginWindowDrag(
        processIdentifier: Int32,
        initialFrame: CGRect?
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.beginWindowDrag(
                processIdentifier,
                windowX: Double(initialFrame?.minX ?? 0),
                windowY: Double(initialFrame?.minY ?? 0),
                windowWidth: Double(initialFrame?.width ?? 0),
                windowHeight: Double(initialFrame?.height ?? 0)
            ) { captured in
                continuation.resume(returning: captured)
            }
        }
    }

    nonisolated func capturedWindowHasMoved() async -> Bool {
        await withCheckedContinuation { continuation in
            helper.capturedWindowHasMoved { moved in
                continuation.resume(returning: moved)
            }
        }
    }

    nonisolated func setCapturedWindowFrame(_ frame: CGRect, animated: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.setCapturedWindowFrame(
                Double(frame.origin.x),
                y: Double(frame.origin.y),
                width: Double(frame.width),
                height: Double(frame.height),
                animated: animated
            ) { success in
                continuation.resume(returning: success)
            }
        }
    }

    nonisolated func setWindowFrame(
        processIdentifier: Int32,
        initialFrame: CGRect,
        targetFrame: CGRect,
        animated: Bool
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.setWindowFrame(
                processIdentifier,
                windowX: Double(initialFrame.minX),
                windowY: Double(initialFrame.minY),
                windowWidth: Double(initialFrame.width),
                windowHeight: Double(initialFrame.height),
                targetX: Double(targetFrame.minX),
                targetY: Double(targetFrame.minY),
                targetWidth: Double(targetFrame.width),
                targetHeight: Double(targetFrame.height),
                animated: animated
            ) { success in
                continuation.resume(returning: success)
            }
        }
    }

    nonisolated func applyWindowFrame(
        processIdentifier: Int32,
        windowID: CGWindowID,
        targetFrame: CGRect,
        minimizeIntermediateFrames: Bool = false
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.applyWindowFrame(
                processIdentifier,
                windowID: UInt32(windowID),
                targetX: Double(targetFrame.minX),
                targetY: Double(targetFrame.minY),
                targetWidth: Double(targetFrame.width),
                targetHeight: Double(targetFrame.height),
                minimizeIntermediateFrames: minimizeIntermediateFrames
            ) { success in
                continuation.resume(returning: success)
            }
        }
    }

    nonisolated func performNativeWindowLayout(_ command: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.performNativeWindowLayout(command) { success in
                continuation.resume(returning: success)
            }
        }
    }

    nonisolated func performWindowLayoutForProcess(_ processIdentifier: Int32, command: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.performWindowLayoutForProcess(processIdentifier, command: command) { success in
                continuation.resume(returning: success)
            }
        }
    }

    nonisolated func performNativeWindowLayoutForWindow(
        processIdentifier: Int32,
        initialFrame: CGRect,
        command: Int
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.performNativeWindowLayoutForWindow(
                processIdentifier,
                windowX: Double(initialFrame.minX),
                windowY: Double(initialFrame.minY),
                windowWidth: Double(initialFrame.width),
                windowHeight: Double(initialFrame.height),
                command: command
            ) { success in
                continuation.resume(returning: success)
            }
        }
    }

    nonisolated func primeNativeWindowLayoutShortcuts() async {
        await withCheckedContinuation { continuation in
            helper.primeNativeWindowLayoutShortcuts {
                continuation.resume()
            }
        }
    }

    nonisolated func cancelWindowDrag() {
        helper.cancelWindowDrag()
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            helper.isKeyboardBrightnessAvailable { available in
                continuation.resume(returning: available)
            }
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        await withCheckedContinuation { continuation in
            helper.currentKeyboardBrightness { value in
                continuation.resume(returning: value?.floatValue)
            }
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.setKeyboardBrightness(value) { success in
                continuation.resume(returning: success)
            }
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            helper.isScreenBrightnessAvailable { available in
                continuation.resume(returning: available)
            }
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        await withCheckedContinuation { continuation in
            helper.currentScreenBrightness { value in
                continuation.resume(returning: value?.floatValue)
            }
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        await withCheckedContinuation { continuation in
            helper.setScreenBrightness(value) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
