//
//  scratchpad_card_view.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct ScratchpadCardView: View {
    let item: ScratchpadItem
    var onSelect: () -> Void

    @ObservedObject private var viewModel = ScratchpadViewModel.shared
    @State private var isHovering: Bool = false
    @State private var isCopied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header row: timestamp and actions
            HStack(spacing: 4) {
                Text(item.formattedDate)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                // Copy button
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isCopied ? .green : .white.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(isCopied ? 0.2 : 0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy text")

                // Delete button
                Button {
                    viewModel.removeItem(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Delete note")
            }

            // Text preview
            Text(item.content.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(3)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 148, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(isHovering ? 0.22 : 0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
    }

    private func copyToClipboard() {
        viewModel.copyItem(item)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.15)) {
                isCopied = false
            }
        }
    }
}
