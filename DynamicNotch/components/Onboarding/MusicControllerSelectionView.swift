//
//  MusicControllerSelectionView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import Defaults

struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @Default(.mediaController) var mediaController
    @Default(.enabledMediaControllers) var enabledMediaControllers
    
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
    
    @State private var selectedControllers: Set<MediaControllerType> = Set(Defaults[.enabledMediaControllers])
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Playback Sources")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 24)

            Text("Select the music and media sources you want to use (multiple selections supported). You can adjust this later in settings.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(availableMediaControllers) { controller in
                        ControllerOptionView(
                            controller: controller,
                            isSelected: selectedControllers.contains(controller)
                        )
                        .onTapGesture {
                            toggleController(controller)
                        }
                    }
                }
                .padding()
            }
            .scrollDisabled(availableMediaControllers.count <= 4)

            Button("Continue", action: {
                let ordered = availableMediaControllers.filter { selectedControllers.contains($0) }
                enabledMediaControllers = ordered.isEmpty ? availableMediaControllers : ordered
                if !selectedControllers.contains(mediaController), let first = ordered.first {
                    mediaController = first
                }
                NotificationCenter.default.post(
                    name: Notification.Name.mediaControllerChanged,
                    object: nil
                )
                onContinue()
            })
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private func toggleController(_ controller: MediaControllerType) {
        if selectedControllers.contains(controller) {
            if selectedControllers.count > 1 {
                selectedControllers.remove(controller)
            }
        } else {
            selectedControllers.insert(controller)
        }
    }
}

struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundColor(isSelected ? .effectiveAccent : .secondary.opacity(0.5))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.displayNameKey)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(LocalizedStringKey(controller.description))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if controller == .youtubeMusic, let url = URL(string: "https://github.com/pear-devs/pear-desktop") {
                    Link("View on GitHub: pear-devs/pear-desktop", destination: url)
                        .font(.subheadline)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.effectiveAccent.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.effectiveAccent : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

extension MediaControllerType {
    var description: String {
        switch self {
        case .nowPlaying:
            return "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version."
        case .spotify:
            return "Connects directly to the Spotify app."
        case .appleMusic:
            return "Connects directly to the Apple Music app."
        case .youtubeMusic:
            return "Requires a third-party client with API plugin enabled."
        case .qqMusic:
            return "Connects directly to QQ Music."
        case .neteaseMusic:
            return "Connects directly to NetEase Music."
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
