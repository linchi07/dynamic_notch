//
//  timer_state.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import Foundation

/// 计时器的运行状态枚举
enum TimerStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case completed

    var displayText: String {
        switch self {
        case .idle:
            return "待开始"
        case .running:
            return "计时中"
        case .paused:
            return "已暂停"
        case .completed:
            return "已完成"
        }
    }
}
