//
//  scratchpad_panel_view.swift
//  boringNotch
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScratchpadPanelView: View {
    @ObservedObject private var viewModel = ScratchpadViewModel.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var isTargeted: Bool = false

    private let CARD_SPACING: CGFloat = 8

    var body: some View {
        ZStack {
            if viewModel.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .frame(maxWidth: .infinity)
        .onDrop(
            of: [.utf8PlainText, .plainText],
            isTargeted: $isTargeted,
            perform: handleDrop(providers:)
        )
    }

    private var emptyView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6])
                )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)

                        Text("Text Scratchpad")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Text("Drag plain text here from browser or anywhere to save")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    let newItem = viewModel.addItem(content: "")
                    openEditor(for: newItem)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
        }
        .padding(.horizontal, 6)
    }

    private var listView: some View {
        HStack(spacing: 8) {
            // New note quick button
            Button {
                let newItem = viewModel.addItem(content: "")
                openEditor(for: newItem)
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("New")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 82)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Scrollable list of text record cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CARD_SPACING) {
                    ForEach(viewModel.items) { item in
                        ScratchpadCardView(item: item) { sourceRect in
                            openEditor(for: item, from: sourceRect)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 6)
    }

    private func openEditor(for item: ScratchpadItem, from sourceRect: NSRect? = nil) {
        ScratchpadEditorWindowController.shared.show(item: item, from: sourceRect) {
            withAnimation(.smooth(duration: 0.28)) {
                vm.close()
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandle = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ||
               provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                Task { @MainActor in
                    if let text = await provider.extractText(), !text.isEmpty {
                        viewModel.addItem(content: text)
                    }
                }
                didHandle = true
            }
        }
        return didHandle
    }
}
