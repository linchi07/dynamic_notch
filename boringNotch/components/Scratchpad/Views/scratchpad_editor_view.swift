//
//  scratchpad_editor_view.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct ScratchpadEditorView: View {
    let itemId: UUID
    var onClose: (() -> Void)?

    @ObservedObject private var viewModel = ScratchpadViewModel.shared
    @State private var title: String = ""
    @State private var text: String = ""
    @State private var showCopiedAlert: Bool = false

    private var currentItem: ScratchpadItem? {
        viewModel.item(for: itemId)
    }

    private var characterCount: Int {
        text.count
    }

    private var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with custom title field and quick action buttons
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    // Editable Title Field
                    TextField("Title (optional)", text: $title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .onChange(of: title) { _, newTitle in
                            saveChanges()
                        }

                    Spacer()

                    // Copy button
                    Button {
                        copyContent()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                            Text(showCopiedAlert ? "Copied" : "Copy")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(showCopiedAlert ? 0.25 : 0.10))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(showCopiedAlert ? .green : .primary)

                    // Delete button
                    Button {
                        deleteContent()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                            Text("Delete")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)

                    // Close button
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Subtitle metadata row
                HStack(spacing: 8) {
                    if let item = currentItem {
                        Text(item.formattedDate)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(characterCount) chars, \(lineCount) lines")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))

            Divider()

            // Large text editor
            TextEditor(text: $text)
                .font(.system(size: 14, design: .default))
                .lineSpacing(5)
                .padding(14)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                .onChange(of: text) { _, _ in
                    saveChanges()
                }
        }
        .frame(minWidth: 440, minHeight: 480)
        .onAppear {
            if let item = currentItem {
                title = item.title ?? ""
                text = item.content
            }
        }
    }

    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        viewModel.updateItem(id: itemId, title: resolvedTitle, content: text)
    }

    private func copyContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedAlert = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedAlert = false
            }
        }
    }

    private func deleteContent() {
        viewModel.removeItem(id: itemId)
        onClose?()
    }
}
