// Runs the production permission controller without changing macOS permissions:
// swiftc -parse-as-library DynamicNotch/XPCHelperClient/AccessibilityAuthorization.swift \
//   tests/accessibility_authorization_tests.swift -o /tmp/accessibility_authorization_tests
// /tmp/accessibility_authorization_tests

import AppKit

@main
struct AccessibilityAuthorizationTests {
    @MainActor
    static func main() async throws {
        var trusted = false
        var prompts = 0
        var settingsOpened = 0
        var changes: [Bool] = []
        let notifications = NotificationCenter()
        let authorization = AccessibilityAuthorization(
            checkTrust: { trusted },
            prompt: { prompts += 1 },
            openSettings: { settingsOpened += 1 },
            notifications: notifications
        )
        let observer = notifications.addObserver(
            forName: .accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { notification in
            changes.append(notification.userInfo?["granted"] as! Bool)
        }
        defer {
            authorization.stopMonitoring()
            notifications.removeObserver(observer)
        }

        // A login launch can initially be untrusted. Monitoring must never prompt.
        authorization.startMonitoring(every: 0.01)
        authorization.startMonitoring(every: 0.01)
        try await Task.sleep(for: .milliseconds(40))
        expect(!authorization.isAuthorized && prompts == 0 && settingsOpened == 0,
               "Startup must check silently")

        authorization.request()
        authorization.request()
        expect(prompts == 1 && settingsOpened == 1,
               "Repeated clicks must open settings without issuing another system prompt")

        // Users normally take longer than the old 0.5-second timeout to grant access.
        try await Task.sleep(for: .milliseconds(650))
        expect(!authorization.isAuthorized, "A request must not optimistically grant access")
        trusted = true
        try await waitFor { authorization.isAuthorized }
        expect(authorization.isAuthorized && changes == [true],
               "A delayed grant must be detected without another request")

        authorization.request()
        authorization.refresh()
        expect(prompts == 1 && settingsOpened == 1 && changes == [true],
               "Already authorized checks and clicks must not prompt or duplicate events")

        trusted = false
        try await waitFor { !authorization.isAuthorized }
        expect(!authorization.isAuthorized && changes == [true, false],
               "Revocation must be detected even after a successful grant")
        expect(prompts == 1, "Revocation must not trigger an automatic prompt")

        authorization.stopMonitoring()
        trusted = true
        try await Task.sleep(for: .milliseconds(40))
        expect(!authorization.isAuthorized, "Shutdown must cancel polling")

        authorization.startMonitoring(every: 10)
        try await waitFor { authorization.isAuthorized }
        trusted = false
        notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await waitFor { !authorization.isAuthorized }
        expect(!authorization.isAuthorized && changes.suffix(2) == [true, false],
               "Returning from System Settings must refresh before the next polling tick")

        let alreadyAuthorized = AccessibilityAuthorization(
            checkTrust: { true },
            prompt: { fatalError("An already authorized launch must not prompt") },
            openSettings: { fatalError("An already authorized launch must not open settings") }
        )
        expect(alreadyAuthorized.isAuthorized, "Relaunch must read the current OS permission")
        alreadyAuthorized.request()
        print("PASS: silent startup, repeated requests, delayed grant, revocation, activation, shutdown, relaunch")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    @MainActor
    private static func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Permission state did not update")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
