//
//  ThirdPartyMusicControllers.swift
//  DynamicNotch
//

import AppKit
import Combine
import Defaults
import Foundation

// MARK: - Discovered Media App Model

struct DiscoveredMediaApp: Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage?
    let isRunning: Bool
}

// MARK: - Media App Helper

enum MediaAppHelper {
    static let DEFAULT_FALLBACK_NAMES: [String: String] = [
        "com.apple.Music": "Apple Music",
        "com.spotify.client": "Spotify",
        "com.netease.163music": "网易云音乐",
        "com.tencent.QQMusicMac": "QQ音乐",
        "com.apple.podcasts": "播客",
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "com.colliderli.iina": "IINA"
    ]

    /// 获取应用的本地化展示名称
    static func displayName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") {
                return String(name.dropLast(4))
            }
            return name
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        return DEFAULT_FALLBACK_NAMES[bundleIdentifier] ?? bundleIdentifier
    }

    /// 获取应用的高清图标
    static func icon(for bundleIdentifier: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            return app.icon
        }
        return nil
    }

    /// 检查应用是否正在运行
    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// 动态注册检测到的媒体应用
    @MainActor
    static func registerDiscoveredApp(_ bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty else { return }
        var discovered = Defaults[.discoveredMediaAppBundleIDs]
        if !discovered.contains(bundleIdentifier) {
            discovered.append(bundleIdentifier)
            Defaults[.discoveredMediaAppBundleIDs] = discovered
        }
    }

    /// 检查指定的 bundleIdentifier 是否被用户允许显示频谱与灵动岛
    static func isAppEnabled(_ bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.isEmpty else { return true }
        let enabled = Defaults[.enabledMediaAppBundleIDs]
        return enabled.contains(bundleIdentifier)
    }

    /// 获取所有供设置界面展示的媒体应用列表
    static func getAllMediaApps() -> [DiscoveredMediaApp] {
        let discovered = Defaults[.discoveredMediaAppBundleIDs]
        var allIDs = Defaults.Keys.DEFAULT_KNOWN_MEDIA_APP_BUNDLE_IDS
        for id in discovered where !allIDs.contains(id) {
            allIDs.append(id)
        }

        return allIDs.map { bundleID in
            DiscoveredMediaApp(
                bundleIdentifier: bundleID,
                displayName: displayName(for: bundleID),
                icon: icon(for: bundleID),
                isRunning: isRunning(bundleIdentifier: bundleID)
            )
        }
    }
}

// MARK: - Legacy Compatibility Controllers

class QQMusicController: MediaControllerProtocol {
    @Published private var playbackState: PlaybackState = PlaybackState(bundleIdentifier: "com.tencent.QQMusicMac")
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }
    func isActive() -> Bool { MediaAppHelper.isRunning(bundleIdentifier: "com.tencent.QQMusicMac") }
    func play() async {}
    func pause() async {}
    func togglePlay() async {}
    func nextTrack() async {}
    func previousTrack() async {}
    func seek(to time: Double) async {}
    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async {}
    func setFavorite(_ favorite: Bool) async {}
    func updatePlaybackInfo() async {}
}

class NetEaseMusicController: MediaControllerProtocol {
    @Published private var playbackState: PlaybackState = PlaybackState(bundleIdentifier: "com.netease.163music")
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }
    func isActive() -> Bool { MediaAppHelper.isRunning(bundleIdentifier: "com.netease.163music") }
    func play() async {}
    func pause() async {}
    func togglePlay() async {}
    func nextTrack() async {}
    func previousTrack() async {}
    func seek(to time: Double) async {}
    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async {}
    func setFavorite(_ favorite: Bool) async {}
    func updatePlaybackInfo() async {}
}
