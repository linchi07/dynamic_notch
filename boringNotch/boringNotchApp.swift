//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon

    let updaterController: SPUStandardUpdaterController

    init() {
        // Never launch as an accessory-only app with every visible entry point
        // disabled. Existing preferences from older versions are repaired here.
        if Defaults[.hideNotchOption] != .never && !Defaults[.menubarIcon] {
            Defaults[.menubarIcon] = true
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("boring.notch (Dev)", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Boring Notch") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    let vm: BoringViewModel = .init()
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?

    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked = false
    private var dragDetector: DragDetector?
    private let windowSnapController = WindowSnapController()
    private var screenConfigurationTask: Task<Void, Never>?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenConfigurationTask?.cancel()
        NotificationCenter.default.removeObserver(self)

        if let screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(screenLockedObserver)
        }
        if let screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(screenUnlockedObserver)
        }

        MusicManager.shared.destroy()
        windowSnapController.cancel()
        stopDragDetector()
        cleanupWindow()
        XPCHelperClient.shared.shutdown()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true

        if Defaults[.showOnLockScreen] {
            (window as? BoringNotchSkyLightWindow)?.enableSkyLight()
        } else {
            screenConfigurationTask?.cancel()
            stopDragDetector()
            window?.orderOut(nil)
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        (window as? BoringNotchSkyLightWindow)?.disableSkyLight()
        refreshNotchWindow(changeAlpha: true)
    }

    private func cleanupWindow() {
        guard let window else { return }
        window.close()
        NotchSpaceManager.shared.notchSpace.windows.remove(window)
        self.window = nil
    }

    private func stopDragDetector() {
        windowSnapController.cancel()
        dragDetector?.stopMonitoring()
        dragDetector = nil
    }

    @MainActor
    private func setupDragDetector(on screen: NSScreen) {
        stopDragDetector()
        let notchRegion = CGRect(
            x: screen.frame.midX - openNotchSize.width / 2,
            y: screen.frame.maxY - openNotchSize.height,
            width: openNotchSize.width,
            height: openNotchSize.height
        )
        let detector = DragDetector(notchRegion: notchRegion)
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                guard Defaults[.expandedDragDetection],
                      let self,
                      self.window?.isVisible == true
                else { return }
                self.vm.open()
                // `open()` intentionally selects Home while music is active. A
                // content drag is an explicit destination, so apply it last.
                self.coordinator.currentView = .dropLanding
            }
        }
        detector.onDragExitsNotchRegion = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.coordinator.currentView == .dropLanding {
                    self.vm.close()
                }
            }
        }
        detector.onMouseDown = { [weak self] point, modifiers in
            Task { @MainActor in
                guard Defaults[.enableWindowSnapping] else { return }
                self?.windowSnapController.beginDrag(at: point, modifiers: modifiers)
            }
        }
        detector.onMouseDragged = { [weak self] point, modifiers in
            Task { @MainActor in
                guard Defaults[.enableWindowSnapping] else { return }
                self?.windowSnapController.updateDrag(at: point, modifiers: modifiers)
            }
        }
        detector.onModifierFlagsChanged = { [weak self] modifiers in
            Task { @MainActor in
                guard Defaults[.enableWindowSnapping] else { return }
                self?.windowSnapController.updateModifiers(modifiers)
            }
        }
        detector.onMouseUp = { [weak self] point, modifiers in
            Task { @MainActor in
                if let self, self.coordinator.currentView == .dropLanding {
                    // Give SwiftUI's drop target and the asynchronous router time
                    // to claim the drop before treating mouse-up as a cancellation.
                    try? await Task.sleep(for: .milliseconds(300))
                    if self.coordinator.currentView == .dropLanding,
                       !self.vm.dropEvent {
                        self.vm.close()
                    }
                }
                guard Defaults[.enableWindowSnapping] else {
                    self?.windowSnapController.cancel()
                    return
                }
                self?.windowSnapController.endDrag(at: point, modifiers: modifiers)
            }
        }
        detector.onContentDragStarted = { [weak self] in
            Task { @MainActor in
                self?.windowSnapController.cancel()
            }
        }
        dragDetector = detector
        detector.startMonitoring()
    }

    private func createBoringNotchWindow() -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        let window = BoringNotchSkyLightWindow(
            contentRect: rect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(vm)
        )
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool) {
        if changeAlpha {
            window.alphaValue = 0
        }

        window.setFrameOrigin(
            NSPoint(
                x: screen.frame.midX - window.frame.width / 2,
                y: screen.frame.maxY - window.frame.height
            )
        )
        window.alphaValue = 1

        if !isScreenLocked || Defaults[.showOnLockScreen] {
            window.orderFrontRegardless()
        }
    }

    /// The app has exactly one presentation target: the active built-in display
    /// with a physical camera notch. External and non-notched displays are never
    /// eligible, including when a supported MacBook is used with its lid closed.
    @MainActor
    private func refreshNotchWindow(changeAlpha: Bool = false) {
        guard !isScreenLocked || Defaults[.showOnLockScreen] else {
            stopDragDetector()
            window?.orderOut(nil)
            return
        }

        guard let screen = NSScreen.supportedBuiltInDisplay else {
            stopDragDetector()
            window?.orderOut(nil)
            return
        }

        vm.refreshClosedNotchSize()
        if window == nil {
            window = createBoringNotchWindow()
        }

        guard let window else { return }
        positionWindow(window, on: screen, changeAlpha: changeAlpha)
        if vm.notchState == .closed {
            vm.close()
        }
        setupDragDetector(on: screen)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await XPCHelperClient.shared.primeNativeWindowLayoutShortcuts()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNotchWindow()
            }
        }

        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.onScreenLocked(notification)
            }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.onScreenUnlocked(notification)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self else { return }
            coordinator.postNotification(
                title: MusicManager.shared.songTitle,
                message: MusicManager.shared.artistName,
                customImage: MusicManager.shared.albumArt,
                iconName: "music.note",
                iconColor: .pink,
                iconBackground: Color.pink.opacity(0.18),
                category: .activityUpdate,
                activityId: "music.playback",
                duration: 3.0
            )
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self, self.window?.isVisible == true else { return }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch self.vm.notchState {
                case .closed:
                    await MainActor.run {
                        self.vm.open()
                    }

                    self.closeNotchTask = Task { [weak viewModel = self.vm] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                case .open:
                    await MainActor.run {
                        self.vm.close()
                    }
                }
            }
        }

        refreshNotchWindow(changeAlpha: true)

        if coordinator.firstLaunch {
            let initialStep: OnboardingStep = NSScreen.supportedBuiltInDisplay == nil
                ? .unsupported
                : .welcome
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: initialStep)
            }
            if initialStep == .welcome {
                playWelcomeSound()
            }
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
    }

    @objc func screenConfigurationDidChange() {
        screenConfigurationTask?.cancel()
        screenConfigurationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self else { return }
            self.screenConfigurationTask = nil
            self.refreshNotchWindow(changeAlpha: true)
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        refreshNotchWindow(changeAlpha: changeAlpha)
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            refreshNotchWindow()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                )
            )
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")
            onboardingWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}
