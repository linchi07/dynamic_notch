//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared
	private var pendingRelativeDelta: Float = 0
	private var pendingBoundaryFeedback = false
	private var pendingAbsoluteValue: Float?
	private var updateTask: Task<Void, Never>?

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentScreenBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float, isHolding: Bool = false) {
		pendingRelativeDelta += delta
		pendingBoundaryFeedback = pendingBoundaryFeedback || isHolding
		if isHolding {
			NotificationCenter.default.post(name: .notchMediaKeyDidRepeat, object: SneakContentType.brightness)
		}
		startUpdateLoop()
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor [weak self] in
			guard let self else { return }
			// An absolute slider position supersedes older queued deltas. Any
			// relative input arriving afterwards is applied on top of this value.
			self.pendingAbsoluteValue = clamped
			self.pendingRelativeDelta = 0
			self.pendingBoundaryFeedback = false
			self.startUpdateLoop()
		}
	}

	@MainActor
	private func startUpdateLoop() {
		guard updateTask == nil else { return }
		updateTask = Task { @MainActor [weak self] in
			await self?.drainPendingUpdates()
		}
	}

	@MainActor
	private func drainPendingUpdates() async {
		var current = rawBrightness
		var hasAuthoritativeCurrent = false

		while !Task.isCancelled {
			if pendingAbsoluteValue == nil,
			   pendingRelativeDelta != 0,
			   !hasAuthoritativeCurrent {
				current = await client.currentScreenBrightness() ?? current
				hasAuthoritativeCurrent = true
				continue
			}

			let absolute = pendingAbsoluteValue
			let delta = pendingRelativeDelta
			let allowsBoundaryFeedback = pendingBoundaryFeedback
			guard absolute != nil || delta != 0 else { break }

			pendingAbsoluteValue = nil
			pendingRelativeDelta = 0
			pendingBoundaryFeedback = false
			let starting = absolute ?? current
			let target = max(0, min(1, starting + delta))

			if await client.setScreenBrightness(target) {
				current = target
				hasAuthoritativeCurrent = true
				publish(brightness: target, touchDate: true)
				if absolute == nil {
					BoringViewCoordinator.shared.toggleSneakPeek(
						status: true,
						type: .brightness,
						value: CGFloat(target)
					)
					notifyBoundaryHit(
						starting: starting,
						delta: delta,
						isHolding: allowsBoundaryFeedback
					)
				}
			} else {
				hasAuthoritativeCurrent = false
			}
		}

		updateTask = nil
		if pendingAbsoluteValue != nil || pendingRelativeDelta != 0 {
			startUpdateLoop()
		}
	}

	@MainActor
	private func notifyBoundaryHit(starting: Float, delta: Float, isHolding: Bool) {
		guard isHolding else { return }
		if starting >= 0.999 && delta > 0 {
			NotificationCenter.default.post(name: .notchBoundaryHit, object: true)
		} else if starting <= 0.001 && delta < 0 {
			NotificationCenter.default.post(name: .notchBoundaryHit, object: false)
		}
	}

	@MainActor
	private func publish(brightness: Float, touchDate: Bool) {
		if rawBrightness != brightness || touchDate {
			if touchDate { lastChangeAt = Date() }
			rawBrightness = brightness
			animatedBrightness = brightness
		}
	}
}

// (DisplayServices helpers moved into XPC helper)

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared
	private var pendingRelativeDelta: Float = 0
	private var pendingBoundaryFeedback = false
	private var pendingAbsoluteValue: Float?
	private var updateTask: Task<Void, Never>?

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float, isHolding: Bool = false) {
		pendingRelativeDelta += delta
		pendingBoundaryFeedback = pendingBoundaryFeedback || isHolding
		if isHolding {
			NotificationCenter.default.post(name: .notchMediaKeyDidRepeat, object: SneakContentType.backlight)
		}
		startUpdateLoop()
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor [weak self] in
			guard let self else { return }
			self.pendingAbsoluteValue = clamped
			self.pendingRelativeDelta = 0
			self.pendingBoundaryFeedback = false
			self.startUpdateLoop()
		}
	}

	@MainActor
	private func startUpdateLoop() {
		guard updateTask == nil else { return }
		updateTask = Task { @MainActor [weak self] in
			await self?.drainPendingUpdates()
		}
	}

	@MainActor
	private func drainPendingUpdates() async {
		var current = rawBrightness
		var hasAuthoritativeCurrent = false

		while !Task.isCancelled {
			if pendingAbsoluteValue == nil,
			   pendingRelativeDelta != 0,
			   !hasAuthoritativeCurrent {
				current = await client.currentKeyboardBrightness() ?? current
				hasAuthoritativeCurrent = true
				continue
			}

			let absolute = pendingAbsoluteValue
			let delta = pendingRelativeDelta
			let allowsBoundaryFeedback = pendingBoundaryFeedback
			guard absolute != nil || delta != 0 else { break }

			pendingAbsoluteValue = nil
			pendingRelativeDelta = 0
			pendingBoundaryFeedback = false
			let starting = absolute ?? current
			let target = max(0, min(1, starting + delta))

			if await client.setKeyboardBrightness(target) {
				current = target
				hasAuthoritativeCurrent = true
				publish(brightness: target, touchDate: true)
				if absolute == nil {
					BoringViewCoordinator.shared.toggleSneakPeek(
						status: true,
						type: .backlight,
						value: CGFloat(target)
					)
					notifyBoundaryHit(
						starting: starting,
						delta: delta,
						isHolding: allowsBoundaryFeedback
					)
				}
			} else {
				hasAuthoritativeCurrent = false
			}
		}

		updateTask = nil
		if pendingAbsoluteValue != nil || pendingRelativeDelta != 0 {
			startUpdateLoop()
		}
	}

	@MainActor
	private func notifyBoundaryHit(starting: Float, delta: Float, isHolding: Bool) {
		guard isHolding else { return }
		if starting >= 0.999 && delta > 0 {
			NotificationCenter.default.post(name: .notchBoundaryHit, object: true)
		} else if starting <= 0.001 && delta < 0 {
			NotificationCenter.default.post(name: .notchBoundaryHit, object: false)
		}
	}

	@MainActor
	private func publish(brightness: Float, touchDate: Bool) {
		if rawBrightness != brightness || touchDate {
			if touchDate { lastChangeAt = Date() }
			rawBrightness = brightness
		}
	}
}
