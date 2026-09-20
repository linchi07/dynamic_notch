//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @ObservedObject private var quickLookService = QuickLookService.shared
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
        }
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .compositingGroup()
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        DropRouterService.shared.handleDrop(providers: providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    vm.dragDetectorTargeting
                        ? Color.accentColor.opacity(0.9)
                        : Color.white.opacity(0.1),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8])
                )

            content
                .padding(6)

            if tvm.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.black.opacity(0.7), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selection.clear() }
        .onDrop(
            of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
            isTargeted: $vm.dragDetectorTargeting,
            perform: handleDrop(providers:)
        )
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.medium)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
            ShelfKeyboardMonitor.shared.start()
        }
        .onDisappear {
            ShelfKeyboardMonitor.shared.stop()
        }
    }
}
