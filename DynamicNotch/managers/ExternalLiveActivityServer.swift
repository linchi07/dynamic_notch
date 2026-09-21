import AppKit
import Darwin
import Foundation
import SwiftUI

/// Per-app decisions are keyed by the OS-resolved bundle identifier and bundle path,
/// never by an identifier supplied in a socket request.
@MainActor
final class ExternalActivityPermissions: ObservableObject {
    static let shared = ExternalActivityPermissions()
    @Published private(set) var decisions: [String: Bool] {
        didSet { UserDefaults.standard.set(decisions, forKey: "externalActivityPermissions") }
    }

    private init() {
        decisions = UserDefaults.standard.dictionary(forKey: "externalActivityPermissions") as? [String: Bool] ?? [:]
    }

    func isAllowed(_ identity: String) -> Bool { decisions[identity] == true }

    func setAllowed(_ allowed: Bool, for identity: String) {
        decisions[identity] = allowed
        if !allowed { ExternalLiveActivityServer.shared.revoke(identity) }
    }

    func requestAccess(for identity: String, appName: String) -> Bool {
        if let decision = decisions[identity] { return decision }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow \(appName) to use DynamicNotch Live Activities?"
        alert.informativeText = "This app can display activities and alerts in the notch.\n\n\(identity)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        let allowed = alert.runModal() == .alertFirstButtonReturn
        setAllowed(allowed, for: identity)
        return allowed
    }
}

/// Newline-delimited JSON over a user-private Unix domain socket. A connection
/// owns only its own activity IDs; EOF (including a crashed client) ends them.
final class ExternalLiveActivityServer: @unchecked Sendable {
    static let shared = ExternalLiveActivityServer()
    private let lock = NSLock()
    private var ownedActivities: [Int32: (identity: String, prefix: String, ids: Set<String>)] = [:]
    private var listenFD: Int32 = -1

    let socketPath: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DynamicNotch/live-activity.sock").path

    private init() {}

    func start() {
        guard listenFD < 0 else { return }
        let directory = (socketPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { return }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(fd); return }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        if !didBind {
            guard errno == EADDRINUSE else { Darwin.close(fd); return }
            // Remove only a stale socket. A live server must keep its endpoint.
            let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            let isLive = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
            Darwin.close(probe)
            guard !isLive else { Darwin.close(fd); return }
            Darwin.unlink(socketPath)
            let rebound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
                }
            }
            guard rebound else { Darwin.close(fd); return }
        }
        Darwin.chmod(socketPath, 0o600)
        guard Darwin.listen(fd, 8) == 0 else { Darwin.close(fd); return }
        listenFD = fd
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                let client = Darwin.accept(fd, nil, nil)
                if client < 0 { break }
                var noSIGPIPE: Int32 = 1
                _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSIGPIPE,
                               socklen_t(MemoryLayout<Int32>.size))
                DispatchQueue.global(qos: .utility).async { [self] in handle(client) }
            }
        }
    }

    func revoke(_ identity: String) {
        lock.lock()
        let ids = ownedActivities.values.filter { $0.identity == identity }.flatMap(\.ids)
        lock.unlock()
        Task { @MainActor in ids.forEach { LiveActivityManager.shared.end($0) } }
    }

    private func handle(_ fd: Int32) {
        defer {
            lock.lock()
            let ids = ownedActivities.removeValue(forKey: fd)?.ids ?? []
            lock.unlock()
            Task { @MainActor in ids.forEach { LiveActivityManager.shared.end($0) } }
            Darwin.close(fd)
        }

        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { return }
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleURL = app.bundleURL,
              let bundleID = app.bundleIdentifier else { return }
        let identity = "\(bundleID)|\(bundleURL.path)"
        let name = app.localizedName ?? bundleID
        lock.lock()
        let prefix = "external.\(UUID().uuidString)."
        ownedActivities[fd] = (identity, prefix, [])
        lock.unlock()

        var buffer: [UInt8] = []
        var byte: UInt8 = 0
        while Darwin.read(fd, &byte, 1) == 1 {
            if byte == 10 {
                guard let request = try? JSONDecoder().decode(ExternalActivityRequest.self, from: Data(buffer)) else {
                    reply(fd, ok: false, message: "invalid JSON")
                    buffer.removeAll(keepingCapacity: true)
                    continue
                }
                buffer.removeAll(keepingCapacity: true)
                let semaphore = DispatchSemaphore(value: 0)
                Task { @MainActor in
                    let allowed = ExternalActivityPermissions.shared.requestAccess(for: identity, appName: name)
                    if allowed { self.apply(request, fd: fd, prefix: prefix) }
                    self.reply(fd, ok: allowed, message: allowed ? "ok" : "permission denied")
                    semaphore.signal()
                }
                semaphore.wait()
            } else {
                guard buffer.count < 65_536 else { reply(fd, ok: false, message: "request too large"); return }
                buffer.append(byte)
            }
        }
    }

    @MainActor
    private func apply(_ request: ExternalActivityRequest, fd: Int32, prefix: String) {
        guard let id = request.id, !id.isEmpty, id.count <= 100 else {
            if request.action == "alert.post" {
                LiveActivityManager.shared.postAlert(FloatingNotificationItem(
                    iconName: request.icon ?? "bell.fill", title: request.title ?? "Alert",
                    message: request.message ?? "", duration: min(max(request.duration ?? 2, 0.5), 10)
                ))
            }
            return
        }
        let key = prefix + id
        switch request.action {
        case "activity.upsert":
            let lead = NotchActivityItem(visual: .system(name: request.icon ?? "app.fill"),
                                         accessibilityLabel: request.title ?? "Live Activity")
            let trail = NotchActivityItem(
                visual: request.progress.map { .progress($0) } ?? .system(name: request.statusIcon ?? "circle.fill"),
                accessibilityLabel: request.message ?? "Active"
            )
            LiveActivityManager.shared.register(NotchLiveActivity(id: key, leading: lead, trailing: trail,
                                                                    minimalPresentation: lead))
            lock.lock()
            ownedActivities[fd]?.ids.insert(key)
            lock.unlock()
        case "activity.end":
            lock.lock()
            let isOwned = ownedActivities[fd]?.ids.contains(key) == true
            lock.unlock()
            guard isOwned else { return }
            LiveActivityManager.shared.end(key)
            lock.lock()
            ownedActivities[fd]?.ids.remove(key)
            lock.unlock()
        case "alert.post":
            LiveActivityManager.shared.postAlert(FloatingNotificationItem(
                iconName: request.icon ?? "bell.fill", title: request.title ?? "Alert",
                message: request.message ?? "", category: request.activityID == nil ? .systemAlert : .activityUpdate,
                activityId: request.activityID.map { prefix + $0 },
                duration: min(max(request.duration ?? 2, 0.5), 10)
            ))
        default: break
        }
    }

    private func reply(_ fd: Int32, ok: Bool, message: String) {
        let response = "{\"ok\":\(ok),\"message\":\"\(message)\"}\n"
        _ = response.withCString { Darwin.write(fd, $0, strlen($0)) }
    }
}

private struct ExternalActivityRequest: Decodable {
    let action: String
    let id: String?
    let icon: String?
    let statusIcon: String?
    let title: String?
    let message: String?
    let progress: Double?
    let duration: Double?
    let activityID: String?
}
