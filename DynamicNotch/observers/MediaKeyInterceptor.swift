//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-23.
//

import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation

private let SYSTEM_DEFINED_EVENT_TYPE_RAW: UInt32 = 14
private let DEFAULT_STEP: Float = 1.0 / 16.0

final class EventTapThread: Thread {
    private(set) var runLoop: CFRunLoop?
    private let semaphore = DispatchSemaphore(value: 0)

    override func main() {
        name = "com.dynamicnotch.media-key-interceptor"
        qualityOfService = .userInteractive
        runLoop = CFRunLoopGetCurrent()

        // Keep the run loop alive even if sources are temporarily removed
        var context = CFRunLoopSourceContext()
        context.version = 0
        if let dummySource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
            CFRunLoopAddSource(runLoop, dummySource, .commonModes)
        }

        semaphore.signal()
        CFRunLoopRun()
    }

    func obtainRunLoop() -> CFRunLoop {
        if let runLoop {
            return runLoop
        }
        start()
        semaphore.wait()
        return runLoop!
    }

    func stop() {
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        cancel()
    }
}

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()
    
    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapThread: EventTapThread?
    private var audioPlayer: AVAudioPlayer?
    private var holdTimer: DispatchSourceTimer?
    private var activeHoldingKey: NXKeyType?
    private let stateLock = NSLock()
    
    private init() {}
    
    // MARK: - Accessibility (via XPC)
    
    func requestAccessibilityAuthorization() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }
    
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
    }
    
    // MARK: - Event Tap
    
    func start(promptIfNeeded: Bool = false) async {
        guard eventTap == nil else { return }
        
        // Ensure HUD replacement is enabled
        guard Defaults[.hudReplacement] else {
            stop()
            return
        }
        
        // Check accessibility authorization
        let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        if !authorized {
            if promptIfNeeded {
                let granted = await ensureAccessibilityAuthorization(promptIfNeeded: true)
                guard granted else { return }
            } else {
                return
            }
        }
        
        let mask = CGEventMask(1 << SYSTEM_DEFINED_EVENT_TYPE_RAW)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                autoreleasepool {
                    guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
                    let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                    return interceptor.handleTapCallback(type: type, cgEvent: cgEvent)
                }
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        guard let eventTap else { return }

        let thread = EventTapThread()
        let backgroundRunLoop = thread.obtainRunLoop()
        eventTapThread = thread

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(backgroundRunLoop, runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    func stop() {
        stopHoldTimer()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource, let eventTapThread, let backgroundRunLoop = eventTapThread.runLoop {
            CFRunLoopRemoveSource(backgroundRunLoop, runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTapThread?.stop()
        eventTapThread = nil
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - Event Callback & Handling

    fileprivate func handleTapCallback(type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // Automatically recover and re-enable tap when disabled by watchdog timeout
        if type == .tapDisabledByTimeout {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        // Pass through when disabled by secure user input
        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(cgEvent)
        }

        // Strictly verify event type to prevent passing pseudo/corrupt events to NSEvent
        guard type.rawValue == SYSTEM_DEFINED_EVENT_TYPE_RAW,
              cgEvent.type.rawValue == SYSTEM_DEFINED_EVENT_TYPE_RAW else {
            return Unmanaged.passUnretained(cgEvent)
        }

        return handleEvent(cgEvent)
    }
    
    private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard cgEvent.type != .null, cgEvent.type.rawValue == SYSTEM_DEFINED_EVENT_TYPE_RAW else {
            return Unmanaged.passUnretained(cgEvent)
        }
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)
        
        guard let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        // 0xB = key up: immediately cancel hold stepping
        if stateByte == 0xB {
            stateLock.lock()
            let isHoldingCurrentKey = (activeHoldingKey == keyType)
            stateLock.unlock()

            if isHoldingCurrentKey {
                stopHoldTimer()
                return nil
            }
            return Unmanaged.passUnretained(cgEvent)
        }
        
        // 0xA = key down
        guard stateByte == 0xA else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        // Safely extract modifier flags directly from CGEvent
        let flags = cgEvent.flags
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)
        
        stateLock.lock()
        let isSameKeyHolding = (activeHoldingKey == keyType)
        stateLock.unlock()

        // If this is an OS key repeat while our hold timer is already active, consume it silently
        if isSameKeyHolding {
            return nil
        }
        
        // Pass through option key press (without shift) directly to macOS system
        if option && !shift {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        // Handle initial single key press
        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command, isHolding: false)
        
        // Start hold timer for continuous keys (volume & brightness) to bypass macOS repeat lag
        if keyType != .mute {
            startHoldTimer(for: keyType, option: option, shift: shift, command: command)
        }
        
        return nil
    }
    
    private func startHoldTimer(for keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        stopHoldTimer()
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        // 200ms initial delay before continuous stepping, then repeat every 40ms (100 steps * 40ms = 4.0s full traversal)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(40))
        
        var ticks = 0
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let isCurrentKey = (self.activeHoldingKey == keyType)
            self.stateLock.unlock()

            guard isCurrentKey else { return }
            ticks += 1
            // Watchdog: auto stop after 125 ticks (~5 seconds) if KeyUp was lost
            if ticks > 125 {
                self.stopHoldTimer()
                return
            }
            self.handleKeyPress(keyType: keyType, option: option, shift: shift, command: command, isHolding: true)
        }
        
        stateLock.lock()
        activeHoldingKey = keyType
        holdTimer = timer
        stateLock.unlock()

        timer.resume()
    }
    
    private func stopHoldTimer() {
        stateLock.lock()
        let timer = holdTimer
        holdTimer = nil
        let hadHoldingKey = (activeHoldingKey != nil)
        activeHoldingKey = nil
        stateLock.unlock()

        timer?.cancel()

        if hadHoldingKey {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .notchMediaKeyDidRelease, object: nil)
            }
        }
    }

    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
                print("🔊 [MediaKeyInterceptor] Loaded default Bezel audio from: \(defaultPath)")
            } catch {
                print("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
            }
        } else {
            print("⚠️ [MediaKeyInterceptor] Default bezel audio not found at: \(defaultPath)")
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private var cachedFeedbackSetting: Bool?
    private var lastFeedbackCheckTime: TimeInterval = 0

    private func isFeedbackSoundEnabled() -> Bool {
        let now = Date().timeIntervalSince1970
        if let cached = cachedFeedbackSetting, now - lastFeedbackCheckTime < 2.0 {
            return cached
        }
        let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int
        let enabled = (feedback == 1)
        cachedFeedbackSetting = enabled
        lastFeedbackCheckTime = now
        return enabled
    }

    private func playFeedbackSound() {
        guard isFeedbackSoundEnabled() else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else {
            return
        }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool, isHolding: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0
        
        switch keyType {
        case .soundUp:
            Task { @MainActor in
                if !isHolding {
                    self.playFeedbackSound()
                }
                VolumeManager.shared.increase(stepDivisor: stepDivisor, isHolding: isHolding)
            }
        case .soundDown:
            Task { @MainActor in
                if !isHolding {
                    self.playFeedbackSound()
                }
                VolumeManager.shared.decrease(stepDivisor: stepDivisor, isHolding: isHolding)
            }
        case .mute:
            Task { @MainActor in
                VolumeManager.shared.toggleMuteAction()
            }
        case .brightnessUp, .keyboardBrightnessUp:
            // Single tap = 1/16; Holding = 1/100 (4.0s full traversal)
            let delta = (isHolding ? (2.5 / 100.0) : DEFAULT_STEP) / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -((isHolding ? (2.5 / 100.0) : DEFAULT_STEP) / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }
    
    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }
}
