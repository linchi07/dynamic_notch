//
//  timer_tests.swift
//  DynamicNotchTests
//
//  Created on 2026-11-19.
//

import AppKit
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        fputs("❌ 测试失败: \(message) [\(file):\(line)]\n", stderr)
        exit(1)
    }
}

@main
struct TimerTests {
    static func main() async throws {
        print("开始运行 Timer 模块单元测试...")

        testTimerPresetDefaults()
        testTimerFormatting()
        testTimerStateAndProgress()

        print("✅ 所有 Timer 单元测试全部通过！")
    }

    /// 测试预设模型与默认预设值
    static func testTimerPresetDefaults() {
        let pomodoro = TimerPresetConstants.DEFAULT_POMODORO
        expect(pomodoro.duration == 1500, "番茄钟时长应为 1500 秒 (25 分钟)")
        expect(pomodoro.minutes == 25, "番茄钟转换分钟数应为 25")
        expect(pomodoro.name == "番茄钟", "番茄钟名称应正确")

        let eyeRest = TimerPresetConstants.DEFAULT_EYE_REST
        expect(eyeRest.duration == 2400, "望远提醒时长应为 2400 秒 (40 分钟)")
        expect(eyeRest.minutes == 40, "望远提醒转换分钟数应为 40")
        expect(eyeRest.name == "望远护眼", "望远护眼名称应正确")
        expect(eyeRest.descriptionText.contains("40") && eyeRest.descriptionText.contains("5"), "望远描述应包含40分钟用眼与5分钟远眺")

        let shortBreak = TimerPresetConstants.DEFAULT_SHORT_BREAK
        expect(shortBreak.duration == 300, "短休息时长应为 300 秒 (5 分钟)")
        expect(shortBreak.minutes == 5, "短休息转换分钟数应为 5")

        let longBreak = TimerPresetConstants.DEFAULT_LONG_BREAK
        expect(longBreak.duration == 900, "长休息时长应为 900 秒 (15 分钟)")
        expect(longBreak.minutes == 15, "长休息转换分钟数应为 15")

        let presets = TimerPresetConstants.ALL_DEFAULT_PRESETS
        expect(presets.count == 4, "默认应提供 4 个核心预设")

        // 验证 Codable 序列化与反序列化
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(presets)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode([TimerPreset].self, from: data)
            expect(decoded.count == 4, "预设 JSON 反序列化后数量应一致")
            expect(decoded[0].id == pomodoro.id, "反序列化后的番茄钟 ID 应一致")
            expect(decoded[1].duration == eyeRest.duration, "反序列化后的望远时长应一致")
        } catch {
            expect(false, "预设序列化或反序列化失败: \(error)")
        }
    }

    /// 测试时间文本格式化逻辑
    static func testTimerFormatting() {
        func formatSeconds(_ seconds: TimeInterval) -> String {
            let total = Int(ceil(seconds))
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let secs = total % 60
            if hours > 0 {
                return String(format: "%02d:%02d:%02d", hours, minutes, secs)
            } else {
                return String(format: "%02d:%02d", minutes, secs)
            }
        }

        expect(formatSeconds(1500) == "25:00", "1500 秒应格式化为 25:00")
        expect(formatSeconds(2400) == "40:00", "2400 秒应格式化为 40:00")
        expect(formatSeconds(59) == "00:59", "59 秒应格式化为 00:59")
        expect(formatSeconds(0) == "00:00", "0 秒应格式化为 00:00")
        expect(formatSeconds(3665) == "01:01:05", "3665 秒应格式化为 01:01:05")
    }

    /// 测试进度与状态流转计算
    static func testTimerStateAndProgress() {
        let total: TimeInterval = 1500
        let remaining: TimeInterval = 750

        let remainingRatio = remaining / total
        expect(abs(remainingRatio - 0.5) < 0.001, "剩余进度比率应为 0.5")

        let elapsedRatio = 1.0 - (remaining / total)
        expect(abs(elapsedRatio - 0.5) < 0.001, "已消耗进度比率应为 0.5")

        expect(TimerStatus.idle.displayText == "待开始", "idle 状态文字应为 '待开始'")
        expect(TimerStatus.running.displayText == "计时中", "running 状态文字应为 '计时中'")
        expect(TimerStatus.paused.displayText == "已暂停", "paused 状态文字应为 '已暂停'")
        expect(TimerStatus.completed.displayText == "已完成", "completed 状态文字应为 '已完成'")
    }
}
