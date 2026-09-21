//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// Owns the one process-wide global event monitor used by every display-specific
/// detector. The monitor is removed as soon as the last detector unregisters.
private final class GlobalDragEventMonitor {
    static let shared = GlobalDragEventMonitor()

    private final class WeakDetector {
        weak var value: DragDetector?

        init(_ value: DragDetector) {
            self.value = value
        }
    }

    private var monitor: Any?
    private var detectors: [ObjectIdentifier: WeakDetector] = [:]

    func add(_ detector: DragDetector) {
        detectors[ObjectIdentifier(detector)] = WeakDetector(detector)
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in
            // Global monitor callbacks bridge CGEvent data into several autoreleased
            // AppKit objects. Drain those objects for every high-frequency callback.
            autoreleasepool {
                self?.dispatch(event)
            }
        }
    }

    func remove(_ detector: DragDetector) {
        detectors.removeValue(forKey: ObjectIdentifier(detector))
        removeReleasedDetectors()

        guard detectors.isEmpty, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func dispatch(_ event: NSEvent) {
        removeReleasedDetectors()
        let activeDetectors = detectors.values.compactMap(\.value)
        activeDetectors.forEach { $0.handle(event) }
    }

    private func removeReleasedDetectors() {
        detectors = detectors.filter { $0.value.value != nil }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

final class DragDetector {

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void
    typealias DragCallback = (_ globalPoint: CGPoint, _ modifiers: NSEvent.ModifierFlags) -> Void
    typealias DragEndCallback = (_ globalPoint: CGPoint, _ modifiers: NSEvent.ModifierFlags) -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?
    var onMouseDown: DragCallback?
    var onMouseDragged: DragCallback?
    var onModifierFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
    var onMouseUp: DragEndCallback?
    var onContentDragStarted: VoidCallback?


    private var isMonitoring = false

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

    // MARK: - Private Helpers
    
    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        guard let pasteboardTypes = dragPasteboard.types else { return false }

        return pasteboardTypes.contains { pasteboardType in
            guard let contentType = UTType(pasteboardType.rawValue) else {
                return pasteboardType == .fileURL || pasteboardType == .string
            }
            return contentType.conforms(to: .fileURL)
                || contentType.conforms(to: .url)
                || contentType.conforms(to: .text)
                || contentType.conforms(to: .image)
                || contentType.conforms(to: .data)
        }
    }

    func startMonitoring() {
        stopMonitoring()
        isMonitoring = true
        GlobalDragEventMonitor.shared.add(self)
    }

    fileprivate func handle(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            pasteboardChangeCount = dragPasteboard.changeCount
            isDragging = true
            isContentDragging = false
            hasEnteredNotchRegion = false
            onMouseDown?(
                mouseLocation,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )

        case .leftMouseDragged:
            guard isDragging else { return }

            if !isContentDragging,
               dragPasteboard.changeCount != pasteboardChangeCount,
               hasValidDragContent() {
                isContentDragging = true
                onContentDragStarted?()
            }

            guard isContentDragging else {
                onMouseDragged?(
                    mouseLocation,
                    event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                )
                return
            }

            onDragMove?(mouseLocation)

            let containsMouse = notchRegion.contains(mouseLocation)
            if containsMouse && !hasEnteredNotchRegion {
                hasEnteredNotchRegion = true
                onDragEntersNotchRegion?()
            } else if !containsMouse && hasEnteredNotchRegion {
                hasEnteredNotchRegion = false
                onDragExitsNotchRegion?()
            }

        case .leftMouseUp:
            if isDragging {
                onMouseUp?(mouseLocation, event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            }
            resetDragState()

        case .flagsChanged:
            guard isDragging, !isContentDragging else { return }
            onModifierFlagsChanged?(
                event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )

        default:
            break
        }
    }

    private func resetDragState() {
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
        pasteboardChangeCount = -1
    }

    func stopMonitoring() {
        if isMonitoring {
            GlobalDragEventMonitor.shared.remove(self)
        }
        isMonitoring = false
        resetDragState()
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - Window snapping

private struct WindowSnapSlot: Identifiable, Equatable {
    let id: String
    /// Unit rectangle expressed from the top-left of the destination display.
    let unitFrame: CGRect
}

private struct WindowSnapLayout: Identifiable {
    let id: String
    let slots: [WindowSnapSlot]

    static let presets: [WindowSnapLayout] = [
        WindowSnapLayout(id: "halves", slots: [
            WindowSnapSlot(id: "half-left", unitFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            WindowSnapSlot(id: "half-right", unitFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ]),
        WindowSnapLayout(id: "wide-left", slots: [
            WindowSnapSlot(id: "two-thirds-left", unitFrame: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)),
            WindowSnapSlot(id: "third-right", unitFrame: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
        ]),
        WindowSnapLayout(id: "thirds", slots: [
            WindowSnapSlot(id: "third-left", unitFrame: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)),
            WindowSnapSlot(id: "third-center", unitFrame: CGRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
            WindowSnapSlot(id: "third-right-balanced", unitFrame: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
        ]),
        WindowSnapLayout(id: "one-two", slots: [
            WindowSnapSlot(id: "one-two-left", unitFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            WindowSnapSlot(id: "one-two-top-right", unitFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            WindowSnapSlot(id: "one-two-bottom-right", unitFrame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
        ]),
        WindowSnapLayout(id: "quarters", slots: [
            WindowSnapSlot(id: "quarter-top-left", unitFrame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            WindowSnapSlot(id: "quarter-top-right", unitFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            WindowSnapSlot(id: "quarter-bottom-left", unitFrame: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
            WindowSnapSlot(id: "quarter-bottom-right", unitFrame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
        ]),
    ]

    static var allSlots: [WindowSnapSlot] {
        presets.flatMap(\.slots)
    }
}

@MainActor
private final class WindowSnapOverlayModel: ObservableObject {
    @Published var selectedSlotID: String?
    @Published var arrangesAllWindows = false
    @Published var isPresented = false
    @Published var isContentVisible = false
}

private enum WindowSnapOverlayMetrics {
    static let contentSize = CGSize(width: 490, height: 112)
    static let shadowInsets = EdgeInsets(top: 46, leading: 50, bottom: 60, trailing: 50)
    static let panelSize = CGSize(
        width: contentSize.width + shadowInsets.leading + shadowInsets.trailing,
        height: contentSize.height + shadowInsets.top + shadowInsets.bottom
    )
}

private final class TransparentWindowSnapHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

private struct WindowSnapOverlayView: View {
    @ObservedObject var model: WindowSnapOverlayModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.085),
                            Color(white: 0.025),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.055),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                }
                .background {
                    // Draw the shadow from the rounded silhouette itself. A
                    // blurred filled shape fades naturally into the transparent
                    // panel, without shadowing the rectangular hosting layer.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                        .blur(radius: 22)
                        .offset(y: 10)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.32))
                        .blur(radius: 6)
                        .offset(y: 3)
                }

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: model.arrangesAllWindows ? "rectangle.3.group.fill" : "macwindow")
                    Text(
                        model.arrangesAllWindows
                            ? String(localized: "All windows")
                            : String(localized: "Current window")
                    )
                    Spacer(minLength: 8)
                    Text(
                        model.arrangesAllWindows
                            ? String(localized: "Shift held")
                            : String(localized: "Hold Shift for all")
                    )
                        .foregroundStyle(model.arrangesAllWindows ? Color.black : Color.white.opacity(0.58))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            model.arrangesAllWindows
                                ? Color.white
                                : Color.white.opacity(0.10),
                            in: Capsule()
                        )
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))

                HStack(spacing: 8) {
                    ForEach(WindowSnapLayout.presets) { layout in
                        GeometryReader { proxy in
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.075))

                                ForEach(layout.slots) { slot in
                                    let frame = slot.unitFrame
                                    let inset: CGFloat = 5
                                    let availableWidth = proxy.size.width - inset * 2
                                    let availableHeight = proxy.size.height - inset * 2
                                    let isSelected = model.selectedSlotID == slot.id
                                        || (model.arrangesAllWindows
                                            && layout.slots.contains { $0.id == model.selectedSlotID })
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(
                                            isSelected
                                                ? Color.white.opacity(0.92)
                                                : Color.white.opacity(0.22)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                        }
                                        .shadow(
                                            color: isSelected
                                                ? Color.white.opacity(0.16)
                                                : .clear,
                                            radius: 5
                                        )
                                        .frame(
                                            width: max(1, availableWidth * frame.width - 2),
                                            height: max(1, availableHeight * frame.height - 2)
                                        )
                                        .position(
                                            x: inset + availableWidth * frame.midX,
                                            y: inset + availableHeight * frame.midY
                                        )
                                        .animation(.easeOut(duration: 0.12), value: model.selectedSlotID)
                                }
                            }
                        }
                        .frame(width: 86, height: 64)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .opacity(model.isContentVisible ? 1 : 0)
            .scaleEffect(model.isContentVisible ? 1 : 0.92)
        }
        .frame(
            width: WindowSnapOverlayMetrics.contentSize.width,
            height: WindowSnapOverlayMetrics.contentSize.height
        )
        .scaleEffect(
            x: model.isPresented ? 1 : 0.40,
            y: model.isPresented ? 1 : 0.22,
            anchor: .top
        )
        .offset(y: model.isPresented ? 0 : -38)
        .animation(
            .interactiveSpring(response: 0.28, dampingFraction: 0.80, blendDuration: 0),
            value: model.isPresented
        )
        .animation(.easeOut(duration: 0.13), value: model.isContentVisible)
        .animation(.easeOut(duration: 0.14), value: model.arrangesAllWindows)
        .padding(WindowSnapOverlayMetrics.shadowInsets)
        .background(Color.clear)
    }
}

/// Coordinates the Windows 11-style top-edge snap chooser. It deliberately
/// consumes the generic mouse callbacks from `DragDetector`, so shelf drops and
/// window drags still share a single process-wide event monitor.
@MainActor
final class WindowSnapController {
    private struct TrackedWindow {
        let id: CGWindowID
        let processIdentifier: Int32
        let initialBounds: CGRect
    }

    /// Window title bars stop at `visibleFrame.maxY`; the menu bar above it is
    /// not a reachable window destination while a native window is being moved.
    private let topTriggerDepth: CGFloat = 44
    private let model = WindowSnapOverlayModel()
    private lazy var panel: NSPanel = makePanel()

    private var dragGeneration = UUID()
    private var capturedWindow = false
    private var confirmedWindowMovement = false
    private var movementCheckInFlight = false
    private var trackedWindow: TrackedWindow?
    private var dragStartPoint: CGPoint?
    private var activeScreen: NSScreen?
    private var isOverlayVisible = false
    private var overlayAnimationTask: Task<Void, Never>?

    func beginDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        cancel(resetHelper: false)
        updateModifiers(modifiers)
        trackedWindow = windowCandidate(at: point)
        dragStartPoint = point
        dragGeneration = UUID()
        let generation = dragGeneration
        let candidate = trackedWindow

        Task {
            let captured = await XPCHelperClient.shared.beginWindowDrag(
                processIdentifier: candidate?.processIdentifier ?? 0,
                initialFrame: candidate?.initialBounds
            )
            guard generation == dragGeneration else { return }
            capturedWindow = captured
            if captured {
                updateDrag(
                    at: NSEvent.mouseLocation,
                    modifiers: NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                )
            }
        }
    }

    func updateDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        updateModifiers(modifiers)
        guard let screen = screenContaining(point) else { return }

        if !confirmedWindowMovement, trackedWindowHasMoved() {
            confirmedWindowMovement = true
        }

        if isOverlayVisible {
            guard activeScreen == screen else {
                hideOverlay()
                return
            }
            updateSelection(at: point)
            return
        }

        guard isInTopTrigger(point, of: screen) else { return }
        if confirmedWindowMovement || dragHasTravelled(to: point) {
            showOverlay(on: screen)
            updateSelection(at: point)
            return
        }

        guard capturedWindow else { return }
        guard !movementCheckInFlight else { return }
        movementCheckInFlight = true
        let generation = dragGeneration
        Task {
            let moved = await XPCHelperClient.shared.capturedWindowHasMoved()
            guard generation == dragGeneration else { return }
            movementCheckInFlight = false
            confirmedWindowMovement = moved
            guard moved,
                  let currentScreen = screenContaining(NSEvent.mouseLocation),
                  isInTopTrigger(NSEvent.mouseLocation, of: currentScreen)
            else { return }
            showOverlay(on: currentScreen)
            updateSelection(at: NSEvent.mouseLocation)
        }
    }

    func endDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if isOverlayVisible {
            updateSelection(at: point)
        }
        let selectedSlot = model.selectedSlotID.flatMap { selectedID in
            WindowSnapLayout.allSlots.first { $0.id == selectedID }
        }
        let screen = activeScreen
        let generation = dragGeneration
        let candidate = trackedWindow
        let layout = selectedSlot.flatMap { selected in
            WindowSnapLayout.presets.first { $0.slots.contains(selected) }
        }

        hideOverlay()
        capturedWindow = false
        confirmedWindowMovement = false
        movementCheckInFlight = false
        trackedWindow = nil
        dragStartPoint = nil

        guard let selectedSlot, let layout, let screen else {
            XPCHelperClient.shared.cancelWindowDrag()
            return
        }

        Task {
            guard generation == dragGeneration else { return }
            if modifiers.contains(.shift), let candidate {
                await arrangeAllWindows(
                    layout: layout,
                    selectedSlot: selectedSlot,
                    capturedWindow: candidate,
                    on: screen
                )
            } else {
                await arrangeCurrentWindow(
                    in: selectedSlot,
                    candidate: candidate,
                    on: screen
                )
            }
        }
    }

    func updateModifiers(_ modifiers: NSEvent.ModifierFlags) {
        model.arrangesAllWindows = modifiers.contains(.shift)
    }

    func cancel() {
        cancel(resetHelper: true)
    }

    private func cancel(resetHelper: Bool) {
        dragGeneration = UUID()
        capturedWindow = false
        confirmedWindowMovement = false
        movementCheckInFlight = false
        trackedWindow = nil
        dragStartPoint = nil
        hideOverlay()
        if resetHelper {
            XPCHelperClient.shared.cancelWindowDrag()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: WindowSnapOverlayMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let hostingView = TransparentWindowSnapHostingView(rootView: WindowSnapOverlayView(model: model))
        panel.contentView = hostingView
        return panel
    }

    private func showOverlay(on screen: NSScreen) {
        overlayAnimationTask?.cancel()
        activeScreen = screen
        let notchHeight = max(getClosedNotchSize().height, 32)
        let origin = CGPoint(
            x: screen.frame.midX - WindowSnapOverlayMetrics.panelSize.width / 2,
            y: screen.frame.maxY
                - notchHeight
                - WindowSnapOverlayMetrics.contentSize.height
                - 4
                - WindowSnapOverlayMetrics.shadowInsets.bottom
        )
        panel.setFrameOrigin(origin)
        model.isPresented = false
        model.isContentVisible = false
        panel.orderFrontRegardless()
        isOverlayVisible = true

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOverlayVisible else { return }
            self.model.isPresented = true
            self.overlayAnimationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(105))
                guard let self, !Task.isCancelled, self.isOverlayVisible else { return }
                self.model.isContentVisible = true
            }
        }
    }

    private func hideOverlay() {
        overlayAnimationTask?.cancel()
        model.selectedSlotID = nil
        model.arrangesAllWindows = false
        model.isContentVisible = false
        model.isPresented = false
        activeScreen = nil
        isOverlayVisible = false

        overlayAnimationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(190))
            guard let self, !Task.isCancelled, !self.isOverlayVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func updateSelection(at point: CGPoint) {
        model.selectedSlotID = slot(at: point)?.id
    }

    private func slot(at point: CGPoint) -> WindowSnapSlot? {
        let contentOrigin = CGPoint(
            x: panel.frame.minX + WindowSnapOverlayMetrics.shadowInsets.leading + 14,
            y: panel.frame.minY + WindowSnapOverlayMetrics.shadowInsets.bottom + 10
        )
        let cardSize = CGSize(width: 86, height: 64)
        let cardSpacing: CGFloat = 8
        let slotInset: CGFloat = 5
        let slotArea = CGSize(
            width: cardSize.width - slotInset * 2,
            height: cardSize.height - slotInset * 2
        )

        let cardYMin = contentOrigin.y
        let cardYMax = contentOrigin.y + cardSize.height
        guard point.y >= cardYMin - 6 && point.y <= cardYMax + 6 else {
            return nil
        }

        for (layoutIndex, layout) in WindowSnapLayout.presets.enumerated() {
            let cardOriginX = contentOrigin.x + CGFloat(layoutIndex) * (cardSize.width + cardSpacing)
            guard point.x >= cardOriginX - 2 && point.x <= cardOriginX + cardSize.width + 2 else {
                continue
            }

            let localX = point.x - (cardOriginX + slotInset)
            let localY = point.y - (cardYMin + slotInset)
            let unitX = max(0, min(1, localX / slotArea.width))
            let unitY = max(0, min(1, 1.0 - (localY / slotArea.height)))
            let unitPoint = CGPoint(x: unitX, y: unitY)

            for slot in layout.slots {
                if slot.unitFrame.contains(unitPoint) {
                    return slot
                }
            }

            return layout.slots.min { a, b in
                let distA = hypot(a.unitFrame.midX - unitX, a.unitFrame.midY - unitY)
                let distB = hypot(b.unitFrame.midX - unitX, b.unitFrame.midY - unitY)
                return distA < distB
            }
        }
        return nil
    }

    private func destinationFrame(for slot: WindowSnapSlot, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let unit = slot.unitFrame
        return CGRect(
            x: visible.minX + unit.minX * visible.width,
            y: visible.minY + (1 - unit.maxY) * visible.height,
            width: unit.width * visible.width,
            height: unit.height * visible.height
        ).insetBy(dx: 4, dy: 4)
    }

    private func arrangeCurrentWindow(
        in slot: WindowSnapSlot,
        candidate: TrackedWindow?,
        on screen: NSScreen
    ) async {
        let appKitDestination = destinationFrame(for: slot, on: screen)
        let destination = appKitToAccessibility(appKitDestination)

        // Trigger frosted glass proxy animation
        if let candidate {
            let latestBounds = currentWindowBounds(for: candidate.id) ?? candidate.initialBounds
            let startAppKitFrame = accessibilityToAppKit(latestBounds)
            WindowSnapGhostAnimator.shared.animate(
                from: startAppKitFrame,
                to: appKitDestination,
                on: screen,
                processIdentifier: candidate.processIdentifier,
                windowID: candidate.id
            )
        }

        var succeeded = false
        if let candidate {
            succeeded = await XPCHelperClient.shared.applyWindowFrame(
                processIdentifier: candidate.processIdentifier,
                windowID: candidate.id,
                targetFrame: destination,
                minimizeIntermediateFrames: Defaults[.enableWindowSnapGhostAnimation]
            )
        }

        if !succeeded {
            succeeded = await XPCHelperClient.shared.setCapturedWindowFrame(
                destination,
                animated: false
            )
        }

        if !succeeded {
            NSLog("Unable to place window in slot %@", slot.id)
        }

        if let candidate {
            if succeeded {
                await completeGhostPlacement(for: candidate.id, on: screen)
            } else {
                WindowSnapGhostAnimator.shared.placementFailed()
            }

            let application = NSRunningApplication(
                processIdentifier: candidate.processIdentifier
            )
            application?.activate(options: .activateIgnoringOtherApps)
        }
    }

    private func arrangeAllWindows(
        layout: WindowSnapLayout,
        selectedSlot: WindowSnapSlot,
        capturedWindow: TrackedWindow,
        on screen: NSScreen
    ) async {
        let remainingSlots = layout.slots.filter { $0 != selectedSlot }
        let otherWindows = otherVisibleWindowCandidates(
            on: screen,
            excludingWindowID: capturedWindow.id,
            limit: remainingSlots.count
        )

        let selectedAppKitDestination = destinationFrame(for: selectedSlot, on: screen)
        let selectedDestination = appKitToAccessibility(selectedAppKitDestination)

        // Trigger frosted glass proxy animation for the primary captured window
        let latestBounds = currentWindowBounds(for: capturedWindow.id) ?? capturedWindow.initialBounds
        let startAppKitFrame = accessibilityToAppKit(latestBounds)
        WindowSnapGhostAnimator.shared.animate(
            from: startAppKitFrame,
            to: selectedAppKitDestination,
            on: screen,
            processIdentifier: capturedWindow.processIdentifier,
            windowID: capturedWindow.id
        )

        let assignments = Array(zip(otherWindows, remainingSlots)).map { window, slot in
            (
                window,
                appKitToAccessibility(destinationFrame(for: slot, on: screen))
            )
        }

        // Place primary window first
        let primarySucceeded = await XPCHelperClient.shared.applyWindowFrame(
            processIdentifier: capturedWindow.processIdentifier,
            windowID: capturedWindow.id,
            targetFrame: selectedDestination,
            minimizeIntermediateFrames: Defaults[.enableWindowSnapGhostAnimation]
        )

        if primarySucceeded {
            await completeGhostPlacement(for: capturedWindow.id, on: screen)
        } else {
            WindowSnapGhostAnimator.shared.placementFailed()
        }

        // Sequentially place remaining windows cleanly without IPC flood
        for (window, destination) in assignments {
            _ = await XPCHelperClient.shared.applyWindowFrame(
                processIdentifier: window.processIdentifier,
                windowID: window.id,
                targetFrame: destination,
                minimizeIntermediateFrames: Defaults[.enableWindowSnapGhostAnimation]
            )
        }

        let application = NSRunningApplication(
            processIdentifier: capturedWindow.processIdentifier
        )
        application?.activate(options: .activateIgnoringOtherApps)
    }

    private func otherVisibleWindowCandidates(
        on screen: NSScreen,
        excludingWindowID: CGWindowID,
        limit: Int
    ) -> [TrackedWindow] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        let ownProcessID = getpid()
        let accessibilityScreenFrame = appKitToAccessibility(screen.visibleFrame)
        var results: [TrackedWindow] = []

        for info in windowInfo {
            guard (info[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                  pid != ownProcessID,
                  let windowNumber = (info[kCGWindowNumber] as? NSNumber)?.uint32Value,
                  windowNumber != excludingWindowID,
                  let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 120,
                  bounds.height >= 80,
                  bounds.intersects(accessibilityScreenFrame)
            else { continue }

            results.append(TrackedWindow(
                id: windowNumber,
                processIdentifier: pid,
                initialBounds: bounds
            ))
            if results.count >= limit {
                break
            }
        }
        return results
    }

    private func appKitToAccessibility(_ frame: CGRect) -> CGRect {
        let mainScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: frame.minX,
            y: mainScreenMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func accessibilityToAppKit(_ frame: CGRect) -> CGRect {
        let mainScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: frame.minX,
            y: mainScreenMaxY - (frame.origin.y + frame.height),
            width: frame.width,
            height: frame.height
        )
    }

    private func currentWindowBounds(for windowID: CGWindowID) -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[CFString: Any]],
        let info = windowInfo.first,
        let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else { return nil }
        return bounds
    }

    /// Samples WindowServer a bounded number of times so asynchronously constrained
    /// resizes can retarget the proxy before the real window is revealed. This is
    /// deliberately not a display-link or per-frame AX loop.
    private func completeGhostPlacement(for windowID: CGWindowID, on screen: NSScreen) async {
        let maximumSamples = 6
        let sampleIntervalMs = 25
        var previousBounds: CGRect?
        var latestAppKitFrame: CGRect?
        var stableComparisons = 0

        for sampleIndex in 0..<maximumSamples {
            if sampleIndex > 0 {
                try? await Task.sleep(for: .milliseconds(sampleIntervalMs))
            }

            guard let bounds = currentWindowBounds(for: windowID) else { continue }
            let appKitFrame = accessibilityToAppKit(bounds)
            latestAppKitFrame = appKitFrame
            WindowSnapGhostAnimator.shared.updateTarget(appKitFrame, on: screen)

            if let previousBounds, framesMatch(previousBounds, bounds, tolerance: 1) {
                stableComparisons += 1
                if stableComparisons >= 2 {
                    break
                }
            } else {
                stableComparisons = 0
            }
            previousBounds = bounds
        }

        WindowSnapGhostAnimator.shared.completePlacement(latestAppKitFrame, on: screen)
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func isInTopTrigger(_ point: CGPoint, of screen: NSScreen) -> Bool {
        // Keep activation near the display centre. A full-width strip causes the
        // chooser to appear while the dragged window is still far from the notch.
        let triggerWidth = min(
            WindowSnapOverlayMetrics.contentSize.width,
            max(280, screen.frame.width * 0.24)
        )
        let triggerMinX = screen.frame.midX - triggerWidth / 2
        let triggerMaxX = screen.frame.midX + triggerWidth / 2
        return point.y >= screen.visibleFrame.maxY - topTriggerDepth
            && point.y <= screen.frame.maxY
            && point.x >= triggerMinX
            && point.x <= triggerMaxX
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// Captures the frontmost regular window under the initial mouse-down. The
    /// bounds are available without Screen Recording permission and give us a
    /// reliable live-move signal for apps that defer AX position updates.
    private func windowCandidate(at appKitPoint: CGPoint) -> TrackedWindow? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        let quartzPoint = appKitToAccessibility(
            CGRect(origin: appKitPoint, size: .zero)
        ).origin
        let ownProcessID = getpid()

        for info in windowInfo {
            guard (info[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value != ownProcessID,
                  let windowNumber = (info[kCGWindowNumber] as? NSNumber)?.uint32Value,
                  let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 120,
                  bounds.height >= 80,
                  bounds.contains(quartzPoint)
            else { continue }

            // A generous title-bar/toolbar band is safe because an actual bounds
            // change is still required before the chooser can be shown.
            let draggableBandHeight = min(110, max(36, bounds.height * 0.25))
            guard quartzPoint.y <= bounds.minY + draggableBandHeight else { return nil }
            let processIdentifier = (info[kCGWindowOwnerPID] as? NSNumber)?.int32Value ?? 0
            return TrackedWindow(
                id: windowNumber,
                processIdentifier: processIdentifier,
                initialBounds: bounds
            )
        }
        return nil
    }

    private func trackedWindowHasMoved() -> Bool {
        guard let trackedWindow,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow],
                trackedWindow.id
              ) as? [[CFString: Any]],
              let info = windowInfo.first,
              let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else { return false }

        return hypot(
            bounds.minX - trackedWindow.initialBounds.minX,
            bounds.minY - trackedWindow.initialBounds.minY
        ) >= 3
    }

    private func dragHasTravelled(to point: CGPoint) -> Bool {
        guard let dragStartPoint else { return false }
        return hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y) >= 8
    }
}
