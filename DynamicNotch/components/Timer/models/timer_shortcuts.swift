//
//  timer_shortcuts.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import AppKit
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 启动 25 分钟番茄钟快捷键
    static let START_POMODORO = Self(
        "timer_start_pomodoro",
        default: .init(.p, modifiers: [.option, .shift])
    )

    /// 启动 40 分钟望远护眼提醒快捷键
    static let START_EYE_REST = Self(
        "timer_start_eye_rest",
        default: .init(.e, modifiers: [.option, .shift])
    )

    /// 暂停 / 继续当前计时器
    static let TOGGLE_TIMER = Self(
        "timer_toggle_pause_resume",
        default: .init(.space, modifiers: [.option, .shift])
    )

    /// 停止 / 复位当前计时器
    static let RESET_TIMER = Self(
        "timer_reset_stop",
        default: .init(.x, modifiers: [.option, .shift])
    )

    /// 打开 / 聚焦刘海计时器视图
    static let OPEN_TIMER_PANEL = Self(
        "timer_open_panel",
        default: .init(.t, modifiers: [.option, .shift])
    )
}
