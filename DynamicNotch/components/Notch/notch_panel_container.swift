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
    @State private var programmaticDestination: NotchViews?

    private let pages: [NotchViews] = [.home, .shelf, .scratchpad]

    var body: some View {
        Group {
            if coordinator.currentView == .dropLanding {
                DropLandingView()
                    .transition(.opacity)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(pages) { page in
                                panelComponent(for: page)
                                    .frame(
                                        width: proxy.size.width,
                                        height: proxy.size.height
                                    )
                                    // Keep every page as one strictly bounded
                                    // render and hit-test surface.
                                    .contentShape(Rectangle())
                                    .compositingGroup()
                                    .clipped()
                                    .id(page)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.never)
                    .scrollClipDisabled(false)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $visiblePage, anchor: .center)
                    .onAppear {
                        visiblePage = coordinator.currentView
                    }
                    .onChange(of: coordinator.currentView) { _, newPage in
                        guard newPage != .dropLanding,
                              visiblePage != newPage
                        else { return }
                        programmaticDestination = newPage
                        withAnimation(.smooth(duration: 0.28)) {
                            visiblePage = newPage
                        }
                    }
                    .onChange(of: visiblePage) { _, newPage in
                        guard let newPage else { return }

                        // A programmatic jump can report the middle page while
                        // travelling from the first page to the third. Do not let
                        // that transient value overwrite the button's destination.
                        if let destination = programmaticDestination {
                            if newPage == destination {
                                programmaticDestination = nil
                            }
                            return
                        }

                        guard coordinator.currentView != newPage else { return }
                        coordinator.currentView = newPage
                    }
                }
            }
        }
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .clipped()
        .mask(Rectangle())
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
