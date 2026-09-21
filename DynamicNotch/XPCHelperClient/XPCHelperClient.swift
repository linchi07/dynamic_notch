import Foundation
import Cocoa

final class XPCHelperClient: NSObject, @unchecked Sendable {
    nonisolated static let shared = XPCHelperClient()
    
    private let helper = DynamicNotchXPCHelper()
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        stopMonitoringAccessibilityAuthorization()
    }
    
    @MainActor
    func shutdown() {
        stopMonitoringAccessibilityAuthorization()
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        helper.requestAccessibilityAuthorization()
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        let result: Bool = await withCheckedContinuation { continuation in
            helper.isAccessibilityAuthorized { authorized in
                continuation.resume(returning: authorized)
            }
        }
        await MainActor.run {
            notifyAuthorizationChange(result)
        }
        return result
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        let result: Bool = await withCheckedContinuation { continuation in
            helper.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                continuation.resume(returning: authorized)
            }
        }
        await MainActor.run {
            notifyAuthorizationChange(result)
        }
        return result
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

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
