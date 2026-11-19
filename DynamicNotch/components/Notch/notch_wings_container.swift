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

    private var effectiveOuterPadding: CGFloat {
        NotchLayoutMetrics.effectiveOuterPadding(outerPadding)
    }

    private var wingWidth: CGFloat {
        NotchLayoutMetrics.wingWidth(
            for: vm.effectiveClosedNotchHeight,
            outerPadding: effectiveOuterPadding
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
                outerPadding: effectiveOuterPadding,
                state: state
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

        var innerPaddingEdge: Edge.Set {
            switch self {
            case .leading: return .trailing
            case .trailing: return .leading
            }
        }
    }

    @ViewBuilder
    private func wing(item: NotchActivityItem?, edge: WingEdge) -> some View {
        let currentVisualWidth = NotchLayoutMetrics.visualWidth(for: item, notchHeight: vm.effectiveClosedNotchHeight)
        let currentWingWidth = NotchLayoutMetrics.singleWingWidth(
            for: item,
            notchHeight: vm.effectiveClosedNotchHeight,
            outerPadding: effectiveOuterPadding
        )

        ZStack(alignment: edge == .leading ? .trailing : .leading) {
            Color.black

            if let item {
                activityVisual(item)
                    .frame(width: currentVisualWidth, height: visualSize)
                    .padding(edge.outerPaddingEdge, effectiveOuterPadding)
                    .padding(edge.innerPaddingEdge, NotchLayoutMetrics.innerPadding)
                    .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .frame(width: currentWingWidth, height: vm.effectiveClosedNotchHeight)
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
        case .progress(let value):
            Circle()
                .stroke(item.tintColor.opacity(0.25), lineWidth: 2.5)
                .overlay {
                    Circle()
                        .trim(from: 0, to: min(max(value, 0), 1))
                        .stroke(item.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(2)

        case .circularTimer(let progress):
            CompactTimerRingView(progress: progress, color: item.tintColor)
                .padding(2)

        case .text(let str):
            Text(str)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(item.tintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 刘海两翼上的紧凑型倒计时圆环，末端带现代 Apple 风格从粗到细的极简指针
struct CompactTimerRingView: View {
    var progress: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let lineWidth: CGFloat = 2.0
            let radius = (diameter - lineWidth) / 2.0
            let clamped = max(0, min(1, progress))

            ZStack {
                // 背景底圈轨道
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: lineWidth)

                // 进度弧线
                Circle()
                    .trim(from: 0, to: CGFloat(clamped))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // 核心：现代 Apple 风格，从粗到细的极简表针（无箭头，纯粹的线性渐缩）
                ModernTaperedNeedle(
                    progress: clamped,
                    radius: radius,
                    baseHalfWidth: max(0.9, diameter * 0.07),
                    tipHalfWidth: 0.35,
                    color: color
                )

                // 中心轴心圆帽（精致小巧）
                Circle()
                    .fill(color)
                    .frame(width: max(2.4, diameter * 0.18), height: max(2.4, diameter * 0.18))
            }
            .frame(width: diameter, height: diameter)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
