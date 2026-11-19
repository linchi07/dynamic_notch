//
//  timer_manager.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import AppKit
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import SwiftUI
import UserNotifications

/// 计时器模块核心管理器
@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    /// 计时器在 LiveActivity 中的唯一标识
    static let TIMER_ACTIVITY_ID = "timer.countdown"

    @Published private(set) var status: TimerStatus = .idle
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var currentPreset: TimerPreset? = nil
    @Published private(set) var currentTitle: String = "计时器"

    private var tickTimer: Timer?
    private var targetEndDate: Date?
    private var isShortcutsListening = false

    /// 剩余时间的进度比例（从 1.0 逐渐减少到 0.0）
    var remainingProgress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, remainingSeconds / totalDuration))
    }

    /// 已消耗的时间进度比例（从 0.0 逐渐增加到 1.0）
    var elapsedProgress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, 1.0 - (remainingSeconds / totalDuration)))
    }

    /// 格式化的倒计时文本展示 (mm:ss 或 hh:mm:ss)
    var formattedTime: String {
        let total = Int(ceil(remainingSeconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private init() {
        requestNotificationPermissionIfNeeded()
        setupSleepWakeObservers()
    }

    /// 请求系统通知授权
    func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 设置系统休眠与唤醒监听，确保休眠唤醒后时间准确无误
    private func setupSleepWakeObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }
    }

    /// 唤醒时校准时间
    private func handleSystemWake() {
        guard status == .running, let targetDate = targetEndDate else { return }
        let now = Date()
        let diff = targetDate.timeIntervalSince(now)
        if diff <= 0 {
            finishTimer()
        } else {
            remainingSeconds = diff
            updateLiveActivity()
        }
    }

    /// 开始监听全局快捷键
    func startMonitoringShortcuts() {
        guard !isShortcutsListening else { return }
        isShortcutsListening = true

        KeyboardShortcuts.onKeyUp(for: .START_POMODORO) { [weak self] in
            Task { @MainActor in
                self?.start(preset: TimerPresetConstants.DEFAULT_POMODORO)
                BoringViewCoordinator.shared.postNotification(
                    title: "🍅 番茄钟已启动",
                    message: "专注 25 分钟，保持专注高效",
                    iconName: "timer",
                    iconColor: .orange,
                    duration: 2.5
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .START_EYE_REST) { [weak self] in
            Task { @MainActor in
                self?.start(preset: TimerPresetConstants.DEFAULT_EYE_REST)
                BoringViewCoordinator.shared.postNotification(
                    title: "👁️ 望远护眼已启动",
                    message: "专注看屏幕 40 分钟，到期后请远眺 5 分钟",
                    iconName: "eye.fill",
                    iconColor: .green,
                    duration: 2.5
                )
            }
        }

        KeyboardShortcuts.onKeyUp(for: .TOGGLE_TIMER) { [weak self] in
            Task { @MainActor in
                self?.togglePlayPause()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .RESET_TIMER) { [weak self] in
            Task { @MainActor in
                self?.reset()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .OPEN_TIMER_PANEL) {
            Task { @MainActor in
                BoringViewCoordinator.shared.currentView = .timer
                NotificationCenter.default.post(name: Notification.Name("openDynamicNotch"), object: nil)
            }
        }
    }

    /// 根据预设启动计时器
    func start(preset: TimerPreset) {
        start(duration: preset.duration, title: preset.name, preset: preset)
    }

    /// 指定时长启动计时器
    func start(duration: TimeInterval, title: String, preset: TimerPreset? = nil) {
        guard duration > 0 else { return }
        stopTimerTick()

        self.totalDuration = duration
        self.remainingSeconds = duration
        self.currentTitle = title
        self.currentPreset = preset
        self.status = .running
        self.targetEndDate = Date().addingTimeInterval(duration)

        startTimerTick()
        updateLiveActivity()
    }

    /// 暂停或继续
    func togglePlayPause() {
        if status == .running {
            pause()
        } else if status == .paused {
            resume()
        } else if status == .idle, let preset = currentPreset {
            start(preset: preset)
        } else if status == .idle {
            start(preset: TimerPresetConstants.DEFAULT_POMODORO)
        }
    }

    /// 暂停计时器
    func pause() {
        guard status == .running else { return }
        stopTimerTick()
        status = .paused
        targetEndDate = nil
        updateLiveActivity()
    }

    /// 继续计时器
    func resume() {
        guard status == .paused, remainingSeconds > 0 else { return }
        status = .running
        targetEndDate = Date().addingTimeInterval(remainingSeconds)
        startTimerTick()
        updateLiveActivity()
    }

    /// 重置 / 停止计时器
    func reset() {
        stopTimerTick()
        status = .idle
        remainingSeconds = 0
        totalDuration = 0
        targetEndDate = nil
        LiveActivityManager.shared.end(Self.TIMER_ACTIVITY_ID)
    }

    /// 快速增加时长（例如 +60 秒或 +300 秒）
    func addSeconds(_ seconds: TimeInterval) {
        guard status == .running || status == .paused else { return }
        remainingSeconds += seconds
        totalDuration += seconds
        if let target = targetEndDate {
            targetEndDate = target.addingTimeInterval(seconds)
        }
        updateLiveActivity()
    }

    private func startTimerTick() {
        stopTimerTick()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTimerTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func handleTick() {
        guard status == .running, let target = targetEndDate else { return }
        let now = Date()
        let remaining = target.timeIntervalSince(now)

        if remaining <= 0 {
            finishTimer()
        } else {
            remainingSeconds = remaining
            updateLiveActivity()
        }
    }

    /// 计时完成触发提醒与通知
    private func finishTimer() {
        stopTimerTick()
        status = .completed
        remainingSeconds = 0
        targetEndDate = nil

        let finishedTitle = currentTitle
        let isEyeRest = currentPreset?.id == TimerPresetConstants.DEFAULT_EYE_REST.id

        // 1. 播放系统提示音
        if Defaults[.TIMER_SOUND_ENABLED] {
            NSSound(named: "Glass")?.play()
        }

        // 2. 刘海浮动通知
        if Defaults[.TIMER_NOTCH_NOTIFICATION_ENABLED] {
            let notificationMessage: String
            if isEyeRest {
                notificationMessage = "长时间看近处 40 分钟，请望向 6 米外远眺 5 分钟，让眼睛充分放松！"
            } else {
                notificationMessage = "\(finishedTitle) 倒计时已结束，放松一下吧！"
            }

            BoringViewCoordinator.shared.postNotification(
                title: "⏰ 时间到！",
                message: notificationMessage,
                iconName: "timer",
                iconColor: .orange,
                duration: 5.0
            )
        }

        // 3. 发送 macOS 系统通知
        if Defaults[.TIMER_SYSTEM_NOTIFICATION_ENABLED] {
            sendSystemNotification(isEyeRest: isEyeRest, title: finishedTitle)
        }

        // 更新或清除刘海 Live Activity
        LiveActivityManager.shared.end(Self.TIMER_ACTIVITY_ID)
    }

    /// 发送系统级横幅通知
    private func sendSystemNotification(isEyeRest: Bool, title: String) {
        let content = UNMutableNotificationContent()
        content.title = "⏰ 时间到了：\(title)"
        if isEyeRest {
            content.body = "长时间近距离用眼 40 分钟已满。医学建议远眺 6 米（20英尺）外 5 分钟，舒缓睫状肌！"
        } else {
            content.body = "您的 \(title) 倒计时已完成，请适当休息活动一下。"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// 更新刘海两翼的实时显示
    private func updateLiveActivity() {
        guard Defaults[.TIMER_LIVE_ACTIVITY_ENABLED],
              status == .running || status == .paused else {
            LiveActivityManager.shared.end(Self.TIMER_ACTIVITY_ID)
            return
        }

        let tintColor: Color = status == .paused ? .gray : .orange
        let progress = remainingProgress

        let circularRingItem = NotchActivityItem(
            visual: .circularTimer(progress: progress),
            tintColor: tintColor,
            accessibilityLabel: "倒计时进行中"
        )

        let timeTextItem = NotchActivityItem(
            visual: .text(formattedTime),
            tintColor: tintColor,
            accessibilityLabel: formattedTime
        )

        LiveActivityManager.shared.register(NotchLiveActivity(
            id: Self.TIMER_ACTIVITY_ID,
            leading: circularRingItem,
            trailing: timeTextItem,
            minimalPresentation: circularRingItem
        ))
    }
}
