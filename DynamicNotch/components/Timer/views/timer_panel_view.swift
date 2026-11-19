//
//  timer_panel_view.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import Defaults
import SwiftUI

/// 展开状态下的刘海计时器交互面板
struct TimerPanelView: View {
    @ObservedObject var timerManager = TimerManager.shared
    @Default(.TIMER_PRESETS) private var presets

    @State private var customMinutes: Int = 25

    var body: some View {
        Group {
            if timerManager.status == .idle {
                idlePanel
            } else {
                activePanel
            }
        }
        .padding(.horizontal, 16)
        .frame(height: NOTCH_PANEL_CONTAINER_HEIGHT)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.3), value: timerManager.status)
    }

    // MARK: - 1. 默认未开始界面 (待机态：左侧自定义时间输入+开始，右侧预设列表)

    @ViewBuilder
    private var idlePanel: some View {
        HStack(spacing: 16) {
            // 左侧：自定义时间输入与开始按钮
            VStack(alignment: .leading, spacing: 8) {
                Text("自定义计时")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    // 减号按钮
                    Button(action: {
                        if customMinutes > 1 {
                            customMinutes -= 1
                        }
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)

                    // 分钟展示与微调
                    HStack(spacing: 2) {
                        Text("\(customMinutes)")
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("分钟")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 54)

                    // 加号按钮
                    Button(action: {
                        if customMinutes < 180 {
                            customMinutes += 1
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                // 开始计时大按钮
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        timerManager.start(
                            duration: TimeInterval(customMinutes * 60),
                            title: "" // 自定义不设预设标题
                        )
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("开始计时")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 76)
                .background(Color.white.opacity(0.12))

            // 右侧：快捷预设列表
            VStack(alignment: .leading, spacing: 4) {
                Text("快捷预设")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)

                let availablePresets = presets.isEmpty ? TimerPresetConstants.ALL_DEFAULT_PRESETS : presets

                VStack(spacing: 4) {
                    ForEach(Array(availablePresets.prefix(3))) { preset in
                        idlePresetRow(preset: preset)
                    }
                }
            }
            .frame(width: 155)
        }
    }

    @ViewBuilder
    private func idlePresetRow(preset: TimerPreset) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                timerManager.start(preset: preset)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(width: 16)

                Text(preset.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(preset.minutes)m")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. 计时运行中 / 暂停界面 (预设隐藏，轮盘居左，标题与控制占据右侧全部空间)

    @ViewBuilder
    private var activePanel: some View {
        HStack(spacing: 18) {
            // 左侧：大号带梭形指针与滑动数字的圆形倒计时轮盘
            TimerCircularProgressView(size: 82, lineWidth: 6)
                .frame(width: 86, height: 86)

            // 右侧：标题与控制占据所有空间！
            VStack(alignment: .leading, spacing: 6) {
                // 标题栏：如果是预设显示标题；如果是自定义则不显示多余标题
                HStack(spacing: 8) {
                    if !timerManager.currentTitle.isEmpty {
                        Text(timerManager.currentTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Text(timerManager.status.displayText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(statusColor.opacity(0.18), in: Capsule())

                    Spacer(minLength: 0)
                }

                // 控制按钮行：大播放/暂停胶囊、重置、加时按钮
                HStack(spacing: 8) {
                    // 主控制按钮（播放/暂停）
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timerManager.togglePlayPause()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: playPauseIconName)
                                .font(.system(size: 11, weight: .bold))
                            Text(timerManager.status == .running ? "暂停" : "继续")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(statusColor, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // 重置/停止按钮
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            timerManager.reset()
                        }
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("停止并重置计时器")

                    // 快速 +1 分钟
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timerManager.addSeconds(60)
                        }
                    }) {
                        Text("+1m")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("增加 1 分钟")

                    // 快速 +5 分钟
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timerManager.addSeconds(300)
                        }
                    }) {
                        Text("+5m")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("增加 5 分钟")
                }

                // 底部说明或贴心建议
                if timerManager.currentPreset?.id == TimerPresetConstants.DEFAULT_EYE_REST.id {
                    Text("💡 护眼建议：看屏幕 40 分钟，建议远眺 6 米外 5 分钟放松眼睛")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.green.opacity(0.9))
                        .lineLimit(1)
                } else if timerManager.currentPreset?.id == TimerPresetConstants.DEFAULT_POMODORO.id {
                    Text("🍅 保持专注，沉浸于手头任务")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Text("快捷键：⌥⇧Space 暂停/继续 · ⌥⇧X 重置")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusColor: Color {
        switch timerManager.status {
        case .idle:
            return .orange
        case .running:
            return timerManager.currentPreset?.id == TimerPresetConstants.DEFAULT_EYE_REST.id ? .green : .orange
        case .paused:
            return .yellow
        case .completed:
            return .red
        }
    }

    private var playPauseIconName: String {
        switch timerManager.status {
        case .running:
            return "pause.fill"
        case .paused, .idle, .completed:
            return "play.fill"
        }
    }
}
