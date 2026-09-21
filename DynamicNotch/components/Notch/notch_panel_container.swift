//
//  notch_panel_container.swift
//  boringNotch
//
//  Created on 2026-09-15.
//

import SwiftUI

/// 统一的面板容器组件。macOS 不提供可用的 PageTabViewStyle，因此使用
/// 系统 ScrollView 的 paging 行为承载页面。页面选择只有
/// coordinator.currentView 一个事实来源，避免滚动位置在动画途中反向覆盖标签选择。
struct NotchPanelContainer: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var visiblePage: NotchViews?
    @State private var programmaticDestination: NotchViews?
    @State private var selectionSyncTask: Task<Void, Never>?

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
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .compositingGroup()
                                    .id(page)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(0, for: .scrollContent)
                    .scrollIndicators(.never)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $visiblePage, anchor: .center)
                    .scrollClipDisabled(false)
                    .onAppear {
                        visiblePage = coordinator.currentView
                    }
                    .onChange(of: coordinator.currentView) { _, newPage in
                        guard newPage != .dropLanding, visiblePage != newPage else { return }

                        selectionSyncTask?.cancel()
                        programmaticDestination = newPage
                        withAnimation(.easeInOut(duration: 0.22)) {
                            visiblePage = newPage
                        }

                        // scrollPosition can report an intermediate page while a
                        // non-adjacent tab jump is animating. Ignore those reports
                        // until the requested destination has settled.
                        selectionSyncTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            if visiblePage != newPage {
                                visiblePage = newPage
                            }
                            programmaticDestination = nil
                        }
                    }
                    .onChange(of: visiblePage) { _, newPage in
                        guard programmaticDestination == nil,
                              let newPage,
                              coordinator.currentView != newPage
                        else { return }
                        coordinator.currentView = newPage
                    }
                    .onDisappear {
                        selectionSyncTask?.cancel()
                    }
                }
            }
        }
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .frame(maxWidth: .infinity)
        // The paging scroll view draws neighbouring pages outside its bounds
        // while transitioning. A mask keeps them out of the notch wings.
        .mask(Rectangle())
        .contentShape(Rectangle())
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
