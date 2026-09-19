//
//  notch_panel_container.swift
//  boringNotch
//
//  Created on 2026-09-15.
//

import SwiftUI

/// 统一的面板容器组件，为所有功能面板提供固定的高度约束和水平左右切换动效，
/// 便于快速插拔与扩展替换不同面板组件。
struct NotchPanelContainer: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @State private var slideDirection: SlideDirection = .forward
    @State private var activeView: NotchViews = .home

    enum SlideDirection {
        case forward
        case backward
    }

    var body: some View {
        ZStack {
            panelComponent(for: coordinator.currentView)
                .id(coordinator.currentView)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: slideDirection == .forward ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: slideDirection == .forward ? .leading : .trailing)
                            .combined(with: .opacity)
                    )
                )
        }
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .frame(maxWidth: .infinity)
        .clipped()
        .onAppear {
            activeView = coordinator.currentView
        }
        .onChange(of: coordinator.currentView) { oldView, newView in
            slideDirection = newView.rawValue >= oldView.rawValue ? .forward : .backward
            activeView = newView
        }
    }

    /// 各功能面板的统一插拔注册处
    @ViewBuilder
    private func panelComponent(for view: NotchViews) -> some View {
        switch view {
        case .home:
            NotchHomeView()
        case .shelf:
            ShelfView()
        case .scratchpad:
            ScratchpadPanelView()
        case .dropLanding:
            DropLandingView()
        }
    }
}
