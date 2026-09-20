//
//  ThirdPartyMusicControllers.swift
//  DynamicNotch
//

import AppKit
import Combine
import Foundation

// MARK: - QQ Music Controller

class QQMusicController: MediaControllerProtocol {
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.tencent.QQMusicMac",
        playbackRate: 1
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }
    
    private var isAppActive: Bool = false
    private var monitorTimer: AnyCancellable?
    
    init() {
        setupProcessObserver()
    }
    
    deinit {
        monitorTimer?.cancel()
    }
    
    private func setupProcessObserver() {
        monitorTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkAppStatus()
            }
        checkAppStatus()
    }
    
    private func checkAppStatus() {
        let running = isActive()
        if running != isAppActive {
            isAppActive = running
            if !running {
                playbackState.isPlaying = false
            }
        }
    }
    
    func isActive() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.QQMusicMac").isEmpty
    }
    
    func play() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }
    
    func pause() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }
    
    func togglePlay() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }
    
    func nextTrack() async {
        sendMediaKey(NX_KEYTYPE_NEXT)
    }
    
    func previousTrack() async {
        sendMediaKey(NX_KEYTYPE_PREVIOUS)
    }
    
    func seek(to time: Double) async {}
    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async {}
    func setFavorite(_ favorite: Bool) async {}
    func updatePlaybackInfo() async {}
    
    private func sendMediaKey(_ key: Int32) {
        func postKeyEvent(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        postKeyEvent(down: true)
        postKeyEvent(down: false)
    }
}

// MARK: - NetEase Music Controller

class NetEaseMusicController: MediaControllerProtocol {
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.netease.163music",
        playbackRate: 1
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    
    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }
    
    private var isAppActive: Bool = false
    private var monitorTimer: AnyCancellable?
    
    init() {
        setupProcessObserver()
    }
    
    deinit {
        monitorTimer?.cancel()
    }
    
    private func setupProcessObserver() {
        monitorTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkAppStatus()
            }
        checkAppStatus()
    }
    
    private func checkAppStatus() {
        let running = isActive()
        if running != isAppActive {
            isAppActive = running
            if !running {
                playbackState.isPlaying = false
            }
        }
    }
    
    func isActive() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.163music").isEmpty
    }
    
    func play() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }
    
    func pause() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }
    
    func togglePlay() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }
    
    func nextTrack() async {
        sendMediaKey(NX_KEYTYPE_NEXT)
    }
    
    func previousTrack() async {
        sendMediaKey(NX_KEYTYPE_PREVIOUS)
    }
    
    func seek(to time: Double) async {}
    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async {}
    func setFavorite(_ favorite: Bool) async {}
    func updatePlaybackInfo() async {}
    
    private func sendMediaKey(_ key: Int32) {
        func postKeyEvent(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        postKeyEvent(down: true)
        postKeyEvent(down: false)
    }
}
