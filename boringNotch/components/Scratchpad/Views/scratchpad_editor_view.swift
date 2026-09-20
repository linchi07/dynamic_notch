//
//  scratchpad_editor_view.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import SwiftUI

/// Custom native text view to ensure 100% reliable cursor rendering, text selection, and undo operations.
private struct ScratchpadNativeTextView: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isSelectable = true
        textView.isEditable = true
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .none
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            if selectedRanges.allSatisfy({ $0.rangeValue.upperBound <= textView.string.utf16.count }) {
                textView.selectedRanges = selectedRanges
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadNativeTextView

        init(_ parent: ScratchpadNativeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onTextChange?()
        }
    }
}

struct ScratchpadEditorView: View {
    let itemId: UUID
    var onClose: (() -> Void)?

    @ObservedObject private var viewModel = ScratchpadViewModel.shared
    @State private var title: String = ""
    @State private var text: String = ""
    @State private var showCopiedAlert: Bool = false
    @State private var hasLoadedItem: Bool = false

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
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TextField("Title (optional)", text: $title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .textFieldStyle(.plain)
                            .onChange(of: title) { _, _ in
                                saveChanges()
                            }
                    }

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
                }

                Spacer(minLength: 12)

                Button {
                    copyContent()
                } label: {
                    Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(showCopiedAlert ? 0.18 : 0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(showCopiedAlert ? .green : .primary)
                .help(showCopiedAlert ? "Copied" : "Copy")

                Button {
                    deleteContent()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Delete")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))

            Divider()

            // Robust native text view for distraction-free editing and accurate cursor
            ScratchpadNativeTextView(text: $text) {
                saveChanges()
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
        }
        .frame(minWidth: 440, minHeight: 480)
        .onAppear {
            if let item = currentItem {
                title = item.title ?? ""
                text = item.content
            }
            hasLoadedItem = true
        }
    }

    private func saveChanges() {
        guard hasLoadedItem else { return }
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
