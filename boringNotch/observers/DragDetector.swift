//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
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
        let validTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string
        ]
        return dragPasteboard.types?.contains(where: validTypes.contains) ?? false
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
            WindowSnapSlot(id: "native-left", unitFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            WindowSnapSlot(id: "native-right", unitFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ]),
        WindowSnapLayout(id: "vertical-halves", slots: [
            WindowSnapSlot(id: "native-top", unitFrame: CGRect(x: 0, y: 0, width: 1, height: 0.5)),
            WindowSnapSlot(id: "native-bottom", unitFrame: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)),
        ]),
        WindowSnapLayout(id: "quarters", slots: [
            WindowSnapSlot(id: "native-top-left", unitFrame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            WindowSnapSlot(id: "native-top-right", unitFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            WindowSnapSlot(id: "native-bottom-left", unitFrame: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
            WindowSnapSlot(id: "native-bottom-right", unitFrame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
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

private struct WindowSnapOverlayView: View {
    @ObservedObject var model: WindowSnapOverlayModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.48), radius: 16, y: 7)

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

                HStack(spacing: 10) {
                    ForEach(WindowSnapLayout.presets) { layout in
                        GeometryReader { proxy in
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.075))

                                ForEach(layout.slots) { slot in
                                    let frame = slot.unitFrame
                                    let inset: CGFloat = 6
                                    let availableWidth = proxy.size.width - inset * 2
                                    let availableHeight = proxy.size.height - inset * 2
                                    let isSelected = model.selectedSlotID == slot.id
                                        || (model.arrangesAllWindows
                                            && layout.id == "quarters"
                                            && layout.slots.contains { $0.id == model.selectedSlotID })
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(
                                            isSelected
                                                ? Color.white.opacity(0.92)
                                                : Color.white.opacity(0.22)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                        }
                                        .shadow(
                                            color: isSelected
                                                ? Color.white.opacity(0.16)
                                                : .clear,
                                            radius: 5
                                        )
                                        .frame(
                                            width: max(1, availableWidth * frame.width - 3),
                                            height: max(1, availableHeight * frame.height - 3)
                                        )
                                        .position(
                                            x: inset + availableWidth * frame.midX,
                                            y: inset + availableHeight * frame.midY
                                        )
                                        .animation(.easeOut(duration: 0.12), value: model.selectedSlotID)
                                }
                            }
                        }
                        .frame(width: 104, height: 72)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .opacity(model.isContentVisible ? 1 : 0)
            .scaleEffect(model.isContentVisible ? 1 : 0.92)
        }
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
    }
}

/// Coordinates the Windows 11-style top-edge snap chooser. It deliberately
/// consumes the generic mouse callbacks from `DragDetector`, so shelf drops and
/// window drags still share a single process-wide event monitor.
@MainActor
final class WindowSnapController {
    private enum NativeWindowLayoutCommand: Int {
        case left = 0
        case right = 1
        case top = 2
        case bottom = 3
        case topLeft = 4
        case topRight = 5
        case bottomLeft = 6
        case bottomRight = 7
        case leftAndRight = 8
        case rightAndLeft = 9
        case topAndBottom = 10
        case bottomAndTop = 11
        case quarters = 12
        case leftAndQuarters = 13
        case rightAndQuarters = 14
        case topAndQuarters = 15
        case bottomAndQuarters = 16
    }

    private struct TrackedWindow {
        let id: CGWindowID
        let processIdentifier: Int32
        let initialBounds: CGRect
    }

    private let panelSize = CGSize(width: 360, height: 120)
    private let usesDirectAccessibilityFrameFallback = false
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

        hideOverlay()
        capturedWindow = false
        confirmedWindowMovement = false
        movementCheckInFlight = false
        trackedWindow = nil
        dragStartPoint = nil

        guard let selectedSlot, let screen else {
            XPCHelperClient.shared.cancelWindowDrag()
            return
        }

        Task {
            guard generation == dragGeneration else { return }
            if let nativeCommand = nativeCommand(for: selectedSlot, modifiers: modifiers),
               await XPCHelperClient.shared.performNativeWindowLayout(nativeCommand.rawValue) {
                return
            }
            // Experiment mode intentionally stops here. The previous direct AX
            // frame path remains implemented in XPCHelperClient and the helper,
            // but is disabled while native shortcut behavior is evaluated.
            if usesDirectAccessibilityFrameFallback {
                let destination = destinationFrame(for: selectedSlot, on: screen)
                _ = await XPCHelperClient.shared.setCapturedWindowFrame(
                    appKitToAccessibility(destination)
                )
                return
            }
            NSLog("No configured native window shortcut for slot %@", selectedSlot.id)
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
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: WindowSnapOverlayView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 2
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private func showOverlay(on screen: NSScreen) {
        overlayAnimationTask?.cancel()
        activeScreen = screen
        let notchHeight = max(getClosedNotchSize().height, 32)
        let origin = CGPoint(
            x: screen.frame.midX - panelSize.width / 2,
            y: screen.frame.maxY - notchHeight - panelSize.height - 4
        )
        panel.setFrameOrigin(origin)
        model.isPresented = false
        model.isContentVisible = false
        panel.orderFrontRegardless()
        isOverlayVisible = true

        // Match the notification ejection language: emerge vertically from
        // behind the notch first, then reveal the layout glyphs as it expands.
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
        let contentOrigin = CGPoint(x: panel.frame.minX + 14, y: panel.frame.minY + 14)
        let cardSize = CGSize(width: 104, height: 72)
        let cardSpacing: CGFloat = 10
        let slotInset: CGFloat = 6
        let slotArea = CGSize(
            width: cardSize.width - slotInset * 2,
            height: cardSize.height - slotInset * 2
        )

        for (layoutIndex, layout) in WindowSnapLayout.presets.enumerated() {
            let cardOrigin = CGPoint(
                x: contentOrigin.x + CGFloat(layoutIndex) * (cardSize.width + cardSpacing),
                y: contentOrigin.y
            )
            for slot in layout.slots {
                let unit = slot.unitFrame
                let hitFrame = CGRect(
                    x: cardOrigin.x + slotInset + unit.minX * slotArea.width,
                    y: cardOrigin.y + slotInset + (1 - unit.maxY) * slotArea.height,
                    width: unit.width * slotArea.width,
                    height: unit.height * slotArea.height
                ).insetBy(dx: 1.5, dy: 1.5)
                if hitFrame.contains(point) {
                    return slot
                }
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

    private func nativeCommand(
        for slot: WindowSnapSlot,
        modifiers: NSEvent.ModifierFlags
    ) -> NativeWindowLayoutCommand? {
        let requestsDesktopArrangement = modifiers.contains(.shift)
        switch slot.id {
        case "native-left":
            return requestsDesktopArrangement ? .leftAndRight : .left
        case "native-right":
            return requestsDesktopArrangement ? .rightAndLeft : .right
        case "native-top":
            return requestsDesktopArrangement ? .topAndBottom : .top
        case "native-bottom":
            return requestsDesktopArrangement ? .bottomAndTop : .bottom
        case "native-top-left":
            return requestsDesktopArrangement ? .quarters : .topLeft
        case "native-top-right":
            return requestsDesktopArrangement ? .quarters : .topRight
        case "native-bottom-left":
            return requestsDesktopArrangement ? .quarters : .bottomLeft
        case "native-bottom-right":
            return requestsDesktopArrangement ? .quarters : .bottomRight
        default:
            return nil
        }
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

    private func isInTopTrigger(_ point: CGPoint, of screen: NSScreen) -> Bool {
        point.y >= screen.visibleFrame.maxY - topTriggerDepth
            && point.y <= screen.frame.maxY
            && point.x >= screen.frame.minX
            && point.x <= screen.frame.maxX
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
