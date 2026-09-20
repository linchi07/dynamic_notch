//
//  notch_wings_container.swift
//  boringNotch
//
//  Created on 2026-09-15.
//

import Defaults
import SwiftUI

/// Fixed-width active notch. Visuals touch the physical notch on their inner
/// edge, while the virtual notch keeps padding only at its outer edges.
struct NotchWingsContainer: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.notchOuterPadding) private var outerPadding

    let state: NotchActiveState

    private var visualSize: CGFloat {
        NotchLayoutMetrics.visualSize(for: vm.effectiveClosedNotchHeight)
    }

    private var wingWidth: CGFloat {
        NotchLayoutMetrics.wingWidth(
            for: vm.effectiveClosedNotchHeight,
            outerPadding: outerPadding
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            wing(item: state.leadingItem, edge: .leading)

            Rectangle()
                .fill(.black)
                .frame(
                    width: vm.closedNotchSize.width,
                    height: vm.effectiveClosedNotchHeight
                )

            wing(item: state.trailingItem, edge: .trailing)
        }
        .frame(
            width: NotchLayoutMetrics.activeWidth(
                physicalNotchWidth: vm.closedNotchSize.width,
                notchHeight: vm.effectiveClosedNotchHeight,
                outerPadding: outerPadding
            ),
            height: vm.effectiveClosedNotchHeight
        )
    }

    private enum WingEdge {
        case leading
        case trailing

        var outerPaddingEdge: Edge.Set {
            switch self {
            case .leading: return .leading
            case .trailing: return .trailing
            }
        }
    }

    @ViewBuilder
    private func wing(item: NotchActivityItem?, edge: WingEdge) -> some View {
        ZStack(alignment: edge == .leading ? .trailing : .leading) {
            Color.black

            if let item {
                activityVisual(item)
                    .frame(width: visualSize, height: visualSize)
                    .padding(edge.outerPaddingEdge, outerPadding)
                    .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .frame(width: wingWidth, height: vm.effectiveClosedNotchHeight)
    }

    @ViewBuilder
    private func activityVisual(_ item: NotchActivityItem) -> some View {
        switch item.visual {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: min(16, visualSize), weight: .semibold))
                .foregroundStyle(item.tintColor)
                .symbolEffect(.pulse, options: .repeating, isActive: item.isPulsing)
                .notchHeroSource(id: item.heroId)

        case .customImage(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .notchHeroSource(id: item.heroId)
                .clipShape(RoundedRectangle(cornerRadius: ALBUM_ART_CORNER_RADIUS_CLOSED, style: .continuous))

        case .colorDot(let color):
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

        case .audioVisualizer:
            Rectangle()
                .fill(item.tintColor.gradient)
                .frame(width: visualSize, height: visualSize)
                .mask {
                    AudioSpectrumView(isPlaying: $musicManager.isPlaying, genre: musicManager.currentGenre)
                        .frame(width: min(16, visualSize), height: min(12, visualSize))
                }
        }
    }
}
