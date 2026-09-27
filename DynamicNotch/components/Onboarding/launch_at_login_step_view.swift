//
//  launch_at_login_step_view.swift
//  DynamicNotch
//

import SwiftUI
import LaunchAtLogin

struct LaunchAtLoginStepView: View {
    let onContinue: () -> Void

    @State private var isLaunchAtLoginEnabled: Bool = true

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.effectiveAccent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "power.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundColor(.effectiveAccent)
            }
            .padding(.top, 24)

            // Recommended badge
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Recommended")
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.effectiveAccent.opacity(0.15))
            .foregroundColor(.effectiveAccent)
            .clipShape(Capsule())

            // Title
            Text("Start Automatically at Login")
                .font(.title2)
                .fontWeight(.bold)

            // Usage explanation
            Text("Enable DynamicNotch at login so your notch gestures, media controls, and shelf are always ready whenever you log into your Mac.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            // Configuration & Benefits Card
            VStack(alignment: .leading, spacing: 14) {
                // Interactive Toggle Row
                HStack(spacing: 12) {
                    Image(systemName: "macbook.and.visionpro")
                        .font(.title2)
                        .foregroundColor(.effectiveAccent)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at Login")
                            .font(.headline)
                        Text("Start silently in the background")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $isLaunchAtLoginEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                // Benefits
                VStack(alignment: .leading, spacing: 8) {
                    benefitRow(
                        icon: "bolt.fill",
                        text: "Instant Access: Notch tools and HUDs are ready immediately."
                    )
                    benefitRow(
                        icon: "menubar.arrow.up.rectangle",
                        text: "Silent in Background: Runs quietly without popping up windows."
                    )
                    benefitRow(
                        icon: "gearshape",
                        text: "Preferences: You can change this anytime in Settings."
                    )
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            // Action area
            VStack(spacing: 10) {
                Button("Continue") {
                    applySettingAndContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if isLaunchAtLoginEnabled {
                    Button("Don't Launch at Login") {
                        isLaunchAtLoginEnabled = false
                        applySettingAndContinue()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            if LaunchAtLogin.isEnabled {
                isLaunchAtLoginEnabled = true
            }
        }
    }

    private func benefitRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)
                .padding(.top, 2)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func applySettingAndContinue() {
        LaunchAtLogin.isEnabled = isLaunchAtLoginEnabled
        onContinue()
    }
}

struct LaunchAtLoginStepView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchAtLoginStepView(onContinue: {})
    }
}
