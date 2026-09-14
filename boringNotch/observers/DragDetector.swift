//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
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
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
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

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?


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
        switch event.type {
        case .leftMouseDown:
            pasteboardChangeCount = dragPasteboard.changeCount
            isDragging = true
            isContentDragging = false
            hasEnteredNotchRegion = false

        case .leftMouseDragged:
            guard isDragging else { return }

            if !isContentDragging,
               dragPasteboard.changeCount != pasteboardChangeCount,
               hasValidDragContent() {
                isContentDragging = true
            }

            guard isContentDragging else { return }

            let mouseLocation = NSEvent.mouseLocation
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
            resetDragState()

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
