//
//  timer_preset.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import Defaults
import Foundation

/// 预设计时器配置模型
struct TimerPreset: Codable, Identifiable, Equatable, Hashable, Defaults.Serializable {
    var id: String
    var name: String
    var duration: TimeInterval
    var icon: String
    var descriptionText: String

    var minutes: Int {
        Int(duration / 60)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        duration: TimeInterval,
        icon: String = "timer",
        descriptionText: String = ""
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.icon = icon
        self.descriptionText = descriptionText
    }
}

/// 默认预设计时器定义常量
enum TimerPresetConstants {
    /// 25 分钟番茄钟
    static let DEFAULT_POMODORO = TimerPreset(
        id: "preset_pomodoro_25",
        name: "番茄钟",
        duration: 25 * 60,
        icon: "timer",
        descriptionText: "专注工作 25 分钟，提高专注力"
    )

    /// 40 分钟望远提醒：医学建议近距离看屏幕 40-45 分钟后，远眺 6 米以外 5 分钟舒缓睫状肌
    static let DEFAULT_EYE_REST = TimerPreset(
        id: "preset_eye_rest_40",
        name: "望远护眼",
        duration: 40 * 60,
        icon: "eye.fill",
        descriptionText: "长时间看近处 40 分钟，建议远眺 5 分钟"
    )

    /// 5 分钟短休息
    static let DEFAULT_SHORT_BREAK = TimerPreset(
        id: "preset_short_break_5",
        name: "短休息",
        duration: 5 * 60,
        icon: "cup.and.saucer.fill",
        descriptionText: "活动身体、喝水或远眺 5 分钟"
    )

    /// 15 分钟深度休息
    static let DEFAULT_LONG_BREAK = TimerPreset(
        id: "preset_long_break_15",
        name: "长休息",
        duration: 15 * 60,
        icon: "figure.walk",
        descriptionText: "散步或闭目深呼吸，放松身心"
    )

    /// 默认预设列表
    static let ALL_DEFAULT_PRESETS: [TimerPreset] = [
        DEFAULT_POMODORO,
        DEFAULT_EYE_REST,
        DEFAULT_SHORT_BREAK,
        DEFAULT_LONG_BREAK
    ]
}
