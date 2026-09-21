//
//  notch_panel_container.swift
//  boringNotch
//
//  Created on 2026-09-15.
//

import SwiftUI

/// 统一的面板容器组件。常规功能页始终处在同一个分页容器中，避免切页时
/// 一个页面里的左右子视图被 SwiftUI 当作独立过渡内容。
struct NotchPanelContainer: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var visiblePage: NotchViews?

    private let pages: [NotchViews] = [.home, .shelf, .scratchpad]

    var body: some View {
        Group {
            if coordinator.currentView == .dropLanding {
                DropLandingView()
                    .transition(.opacity)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(pages) { page in
                                panelComponent(for: page)
                                    .frame(
                                        width: proxy.size.width,
                                        height: proxy.size.height
                                    )
                                    // Keep compound pages such as Shelf on one
                                    // composited surface while they travel.
                                    .compositingGroup()
                                    .id(page)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.never)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $visiblePage)
                    .onAppear {
                        visiblePage = coordinator.currentView
                    }
                    .onChange(of: coordinator.currentView) { _, newPage in
                        guard newPage != .dropLanding,
                              visiblePage != newPage
                        else { return }
                        withAnimation(.smooth(duration: 0.28)) {
                            visiblePage = newPage
                        }
                    }
                    .onChange(of: visiblePage) { _, newPage in
                        guard let newPage,
                              coordinator.currentView != newPage
                        else { return }
                        coordinator.currentView = newPage
                    }
                }
            }
        }
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .frame(maxWidth: .infinity)
        .clipped()
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
            EmptyView()
        }
    }
}
