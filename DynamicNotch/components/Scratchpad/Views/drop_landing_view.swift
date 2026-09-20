//
//  drop_landing_view.swift
//  boringNotch
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Dedicated landing view displayed when dragging items over the notch,
/// eliminating confusion between Shelf and Scratchpad before the drop completes.
struct DropLandingView: View {
    @EnvironmentObject var vm: BoringViewModel
    @State private var pulseAnimation: Bool = false

    private let DASH_PATTERN: [CGFloat] = [6, 4]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.85),
                            Color.purple.opacity(0.70),
                            Color.accentColor.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: vm.dragDetectorTargeting ? 3 : 2,
                        lineCap: .round,
                        dash: DASH_PATTERN
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

            HStack(spacing: 18) {
                // Text destination indicator
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plain Text")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Notes Shelf")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Center drop prompt
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .scaleEffect(pulseAnimation ? 1.12 : 1.0)

                    Text("Drop Here to Save")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .frame(maxWidth: .infinity)

                // Files destination indicator
                HStack(spacing: 8) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Files & URLs")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("File Shelf")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 16)
        }
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .onDrop(
            of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
            isTargeted: $vm.dragDetectorTargeting,
            perform: handleDrop(providers:)
        )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        vm.dropEvent = true
        DropRouterService.shared.handleDrop(providers: providers)
        return true
    }
}
