//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AVFoundation

enum OnboardingStep {
    case unsupported
    case welcome
    case cameraPermission
    case accessibilityPermission
    case musicPermission
    case finished
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .unsupported:
                UnsupportedDeviceView {
                    guard NSScreen.supportedBuiltInDisplay != nil else { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        step = .welcome
                    }
                }
                .transition(.opacity)

            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "DynamicNotch includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .accessibilityPermission
                        }
                    }
                )
                .transition(.opacity)

            case .accessibilityPermission:
                AccessibilityPermissionStepView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .musicPermission
                    }
                }
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            BoringViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

struct AccessibilityPermissionStepView: View {
    let onGranted: () -> Void

    @State private var isAuthorized: Bool = AXIsProcessTrusted()
    @State private var timer: Timer?
    @State private var hasRequested: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if isAuthorized {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "hand.raised.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .foregroundColor(.effectiveAccent)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isAuthorized)
            .padding(.top, 24)

            // Required Badge
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.shield.fill")
                Text("Required Permission")
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.effectiveAccent.opacity(0.15))
            .foregroundColor(.effectiveAccent)
            .clipShape(Capsule())

            // Title
            Text("Enable Accessibility Access")
                .font(.title2)
                .fontWeight(.bold)

            // Usage explanation
            Text("DynamicNotch requires Accessibility access to power window snapping and custom HUD controls. It allows the app to detect windows you are dragging and resize them to your chosen layout.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            // Privacy and Open-Source Evidence Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("Accessibility access is used exclusively for window management and system controls. No window content or user data is ever collected or shared.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "curlybraces.square")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DynamicNotch is 100% open source. You can inspect the source code as proof.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            if let url = URL(string: "https://github.com/linchi07/dynamic_notch") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("View Source Code on GitHub")
                                .font(.caption.bold())
                                .foregroundColor(.effectiveAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            // Action area
            VStack(spacing: 12) {
                if isAuthorized {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("Accessibility Granted!")
                            .font(.subheadline.bold())
                            .foregroundColor(.green)
                    }

                    Button("Continue") {
                        onGranted()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(hasRequested ? "Open System Settings" : "Grant Accessibility Access") {
                        hasRequested = true
                        openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if hasRequested {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for permission in System Settings...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .onAppear {
            checkAuthorization()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkAuthorization()
        }
    }

    private func checkAuthorization() {
        let authorized = AXIsProcessTrusted()
        if authorized != isAuthorized {
            withAnimation(.easeInOut(duration: 0.3)) {
                isAuthorized = authorized
            }
            if authorized {
                stopPolling()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onGranted()
                }
            }
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            checkAuthorization()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct UnsupportedDeviceView: View {
    let onTryAgain: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "laptopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("This Mac isn't supported")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("DynamicNotch now works only on the built-in notched display of a supported MacBook Air, MacBook Pro, or MacBook Neo. External displays, desktop Macs, older MacBooks, and closed-lid mode are not supported.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Text("If this is a supported MacBook, open the lid and try again.")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Try Again", action: onTryAgain)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}
