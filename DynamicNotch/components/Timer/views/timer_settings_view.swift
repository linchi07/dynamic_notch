//
//  timer_settings_view.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import Defaults
import KeyboardShortcuts
import SwiftUI

/// 计时器模块设置视图
struct TimerSettingsView: View {
    @Default(.TIMER_ENABLED) private var isTimerEnabled
    @Default(.TIMER_LIVE_ACTIVITY_ENABLED) private var isLiveActivityEnabled
    @Default(.TIMER_SOUND_ENABLED) private var isSoundEnabled
    @Default(.TIMER_SYSTEM_NOTIFICATION_ENABLED) private var isSystemNotificationEnabled
    @Default(.TIMER_NOTCH_NOTIFICATION_ENABLED) private var isNotchNotificationEnabled
    @Default(.TIMER_PRESETS) private var presets

    @State private var showingEditPresetSheet = false
    @State private var editingPresetIndex: Int? = nil

    var body: some View {
        Form {
            Section(header: Text("基础设置")) {
                Toggle("启用计时器模块", isOn: $isTimerEnabled)

                Toggle("在刘海两翼实时显示倒计时", isOn: $isLiveActivityEnabled)
                    .disabled(!isTimerEnabled)

                Toggle("到时间时播放提示音", isOn: $isSoundEnabled)
                    .disabled(!isTimerEnabled)

                Toggle("到时间时发送 macOS 系统通知", isOn: $isSystemNotificationEnabled)
                    .disabled(!isTimerEnabled)

                Toggle("到时间时在刘海弹出横幅提醒", isOn: $isNotchNotificationEnabled)
                    .disabled(!isTimerEnabled)
            }

            Section(
                header: Text("快捷键配置"),
                footer: Text("可点击右侧快捷键录制框，直接按下您习惯的键盘快捷键（如 Option + Shift + P）进行自定义设置。")
            ) {
                HStack {
                    Label("启动 25 分钟番茄钟", systemImage: "timer")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .START_POMODORO)
                }

                HStack {
                    Label("启动 40 分钟望远护眼提醒", systemImage: "eye.fill")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .START_EYE_REST)
                }

                HStack {
                    Label("暂停 / 继续当前计时", systemImage: "playpause.fill")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .TOGGLE_TIMER)
                }

                HStack {
                    Label("重置 / 停止当前计时", systemImage: "arrow.counterclockwise")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .RESET_TIMER)
                }

                HStack {
                    Label("打开 / 展开刘海计时器", systemImage: "macbook.and.ipad")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .OPEN_TIMER_PANEL)
                }
            }

            Section(
                header: Text("快速预设管理"),
                footer: Text("💡 医学护眼建议：长时间近距离看屏幕（40至45分钟）后，睫状肌处于持续收缩痉挛状态。建议远眺 6 米（20英尺）外的景物至少 5 分钟，让眼部肌肉彻底放松，有效预防近视加深和视疲劳。")
            ) {
                ForEach(presets.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Image(systemName: presets[index].icon)
                            .foregroundStyle(.orange)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(presets[index].name)
                                .font(.system(size: 13, weight: .medium))

                            if !presets[index].descriptionText.isEmpty {
                                Text(presets[index].descriptionText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("\(presets[index].minutes) 分钟")
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)

                        Stepper(
                            "",
                            value: Binding(
                                get: { presets[index].minutes },
                                set: { newMinutes in
                                    presets[index].duration = TimeInterval(max(1, newMinutes) * 60)
                                }
                            ),
                            in: 1...180
                        )
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }

                Button("恢复默认预设") {
                    presets = TimerPresetConstants.ALL_DEFAULT_PRESETS
                }
                .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
