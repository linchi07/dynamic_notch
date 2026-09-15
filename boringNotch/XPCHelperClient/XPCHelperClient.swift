import Foundation
import Cocoa
@preconcurrency import AsyncXPCConnection

final class XPCHelperClient: NSObject, @unchecked Sendable {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "theboringteam.boringnotch.dev.BoringNotchXPCHelper"
    
    private var remoteService: RemoteXPCService<BoringNotchXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var reconnectTask: Task<Void, Never>?
    private var recoveryBudgetResetTask: Task<Void, Never>?
    private var automaticReconnectAttempt = 0
    private let maximumAutomaticReconnectAttempts = 4
    private var isShuttingDown = false
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        reconnectTask?.cancel()
        recoveryBudgetResetTask?.cancel()
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        remoteService = nil
        connection?.invalidate()
        connection = nil
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService(
        resettingRecoveryBudget: Bool = true
    ) -> RemoteXPCService<BoringNotchXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }

        if resettingRecoveryBudget {
            reconnectTask?.cancel()
            reconnectTask = nil
            recoveryBudgetResetTask?.cancel()
            recoveryBudgetResetTask = nil
            automaticReconnectAttempt = 0
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self, weak conn] in
            Task { @MainActor in
                guard let conn else { return }
                self?.handleConnectionLoss(conn)
            }
        }
        
        conn.invalidationHandler = { [weak self, weak conn] in
            Task { @MainActor in
                guard let conn else { return }
                self?.handleConnectionLoss(conn)
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<BoringNotchXPCHelperProtocol>(
            connection: conn,
            remoteInterface: BoringNotchXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }

    @MainActor
    private func handleConnectionLoss(_ failedConnection: NSXPCConnection) {
        // A delayed callback from an old connection must never clear a newer one.
        guard connection === failedConnection else { return }

        failedConnection.interruptionHandler = nil
        failedConnection.invalidationHandler = nil
        recoveryBudgetResetTask?.cancel()
        recoveryBudgetResetTask = nil
        remoteService = nil
        connection = nil
        failedConnection.invalidate()

        if !isShuttingDown {
            scheduleReconnect()
        }
    }

    @MainActor
    private func scheduleReconnect() {
        guard reconnectTask == nil,
              automaticReconnectAttempt < maximumAutomaticReconnectAttempts,
              !isShuttingDown
        else {
            if automaticReconnectAttempt >= maximumAutomaticReconnectAttempts {
                NSLog("BoringNotchXPCHelper automatic recovery paused after %d attempts", automaticReconnectAttempt)
                // A settings-only permission poll must not reopen the circuit every
                // three seconds after automatic recovery has been exhausted.
                stopMonitoringAccessibilityAuthorization()
            }
            return
        }

        let attempt = automaticReconnectAttempt
        automaticReconnectAttempt += 1
        let delayMilliseconds = 500 * (1 << attempt)
        reconnectTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            guard let self, !self.isShuttingDown else { return }
            self.reconnectTask = nil

            let service = self.ensureRemoteService(resettingRecoveryBudget: false)
            guard let candidate = self.connection else { return }
            _ = service // Configures the remote interface before the probe.

            if await self.probeConnection(candidate) {
                self.markConnectionHealthy(candidate)
            } else {
                self.handleConnectionLoss(candidate)
            }
        }
    }

    /// Actually sends a lightweight request. Merely resuming NSXPCConnection does
    /// not prove that launchd successfully relaunched the service.
    @MainActor
    private func probeConnection(_ candidate: NSXPCConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            let reply = OneShotBoolReply(continuation: continuation)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                reply.resolve(false)
            }

            let proxy = candidate.remoteObjectProxyWithErrorHandler { _ in
                reply.resolve(false)
            }
            guard let service = proxy as? BoringNotchXPCHelperProtocol else {
                reply.resolve(false)
                return
            }
            service.isAccessibilityAuthorized { _ in
                reply.resolve(true)
            }
        }
    }

    @MainActor
    private func markConnectionHealthy(_ healthyConnection: NSXPCConnection? = nil) {
        if let healthyConnection, connection !== healthyConnection { return }
        guard automaticReconnectAttempt > 0,
              recoveryBudgetResetTask == nil,
              let stableConnection = connection
        else { return }

        // A service that launches and is killed again immediately is not healthy.
        // Reset the retry budget only after it has remained connected for 30s.
        recoveryBudgetResetTask = Task { @MainActor [weak self, weak stableConnection] in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            guard let self,
                  let stableConnection,
                  self.connection === stableConnection
            else { return }
            self.automaticReconnectAttempt = 0
            self.recoveryBudgetResetTask = nil
        }
    }

    nonisolated private func markConnectionUnhealthy() async {
        await MainActor.run {
            guard let connection = self.connection else { return }
            self.handleConnectionLoss(connection)
        }
    }

    @MainActor
    func shutdown() {
        isShuttingDown = true
        reconnectTask?.cancel()
        reconnectTask = nil
        recoveryBudgetResetTask?.cancel()
        recoveryBudgetResetTask = nil
        stopMonitoringAccessibilityAuthorization()

        guard let connection else {
            remoteService = nil
            return
        }
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        remoteService = nil
        self.connection = nil
        connection.invalidate()
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
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
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

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            do {
                try await service.withService { service in
                    service.requestAccessibilityAuthorization()
                }
                await MainActor.run { markConnectionHealthy() }
            } catch {
                await markConnectionUnhealthy()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                markConnectionHealthy()
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            await markConnectionUnhealthy()
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                markConnectionHealthy()
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            await markConnectionUnhealthy()
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
            await MainActor.run { markConnectionHealthy() }
            return result
        } catch {
            await markConnectionUnhealthy()
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            await MainActor.run { markConnectionHealthy() }
            return result?.floatValue
        } catch {
            await markConnectionUnhealthy()
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
            await MainActor.run { markConnectionHealthy() }
            return result
        } catch {
            await markConnectionUnhealthy()
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
            await MainActor.run { markConnectionHealthy() }
            return result
        } catch {
            await markConnectionUnhealthy()
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            await MainActor.run { markConnectionHealthy() }
            return result?.floatValue
        } catch {
            await markConnectionUnhealthy()
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
            await MainActor.run { markConnectionHealthy() }
            return result
        } catch {
            await markConnectionUnhealthy()
            return false
        }
    }
}

private final class OneShotBoolReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Bool) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
