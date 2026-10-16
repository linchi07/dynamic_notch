import AppKit
import ApplicationServices
import Combine

/// Permission belongs to the running app, independently of the user's HUD preference.
@MainActor
final class AccessibilityAuthorization: ObservableObject {
    static let shared = AccessibilityAuthorization()

    @Published private(set) var isAuthorized: Bool
    private let checkTrust: () -> Bool
    private let prompt: () -> Void
    private let openSettings: () -> Void
    private let notifications: NotificationCenter
    private var hasRequested = false
    private var monitoringTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    init(
        checkTrust: @escaping () -> Bool = { AXIsProcessTrusted() },
        prompt: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        openSettings: @escaping () -> Void = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        },
        notifications: NotificationCenter = .default
    ) {
        self.checkTrust = checkTrust
        self.prompt = prompt
        self.openSettings = openSettings
        self.notifications = notifications
        isAuthorized = checkTrust()
        NSLog("[Accessibility] Initial authorization=%@ bundle=%@ path=%@",
              String(isAuthorized), Bundle.main.bundleIdentifier ?? "unknown", Bundle.main.bundleURL.path)
    }

    deinit {
        monitoringTask?.cancel()
        if let activationObserver {
            notifications.removeObserver(activationObserver)
        }
    }

    @discardableResult
    func refresh() -> Bool {
        let authorized = checkTrust()
        if isAuthorized != authorized {
            isAuthorized = authorized
            NSLog("[Accessibility] Authorization changed to %@", String(authorized))
            notifications.post(
                name: .accessibilityAuthorizationChanged,
                object: self,
                userInfo: ["granted": authorized]
            )
        }
        return authorized
    }

    /// Called only by an explicit user action. The system prompt is asynchronous;
    /// its immediate result is never treated as the user's authorization decision.
    func request() {
        guard !refresh() else { return }
        startMonitoring()
        if hasRequested {
            openSettings()
        } else {
            hasRequested = true
            prompt()
        }
    }

    func startMonitoring(every interval: TimeInterval = 1) {
        guard monitoringTask == nil else { return }
        activationObserver = notifications.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        if let activationObserver {
            notifications.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
