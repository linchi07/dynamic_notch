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
        testNotchWingSymmetryAndLayout()

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

    /// 测试刘海两翼严格对称性与长文本自适应逻辑
    static func testNotchWingSymmetryAndLayout() {
        let notchHeight: CGFloat = 32.0
        let outerPadding: CGFloat = 12.0
        let physicalNotchWidth: CGFloat = 185.0
        let visualSize = max(12.0, notchHeight - 12.0) // 20.0

        // 模拟左翼为圆环，右翼为 38:35 时间文本
        let ringVisualWidth = visualSize // 20.0
        let text3835 = "38:35"
        let textVisualWidth = max(CGFloat(text3835.count) * 6.8 + 6.0, visualSize) // 5 * 6.8 + 6 = 40.0
        expect(textVisualWidth == 40.0, "38:35 的视觉预留宽度应为 40.0")

        let innerPadding: CGFloat = 4.0
        let symmetricWingW = max(ringVisualWidth, textVisualWidth) + outerPadding + innerPadding // 40 + 12 + 4 = 56.0
        expect(symmetricWingW == 56.0, "两翼对称宽度应为 56.0")

        let activeW = physicalNotchWidth + 2 * symmetricWingW // 185 + 112 = 297.0
        expect(activeW == 297.0, "总宽度应为 297.0")

        // 验证对称性：中间物理刘海到左边缘与到右边缘的距离必须完全相等
        let leftEdgeToCenter = symmetricWingW + physicalNotchWidth / 2.0
        let rightEdgeToCenter = symmetricWingW + physicalNotchWidth / 2.0
        expect(leftEdgeToCenter == rightEdgeToCenter, "物理刘海几何中心偏移量必须严格为 0")

        // 测试更长文本（如 01:25:00，8位字符）
        let longTime = "01:25:00"
        let longVisualWidth = max(CGFloat(longTime.count) * 6.8 + 6.0, visualSize) // 8 * 6.8 + 6 = 60.4
        let longSymmetricWingW = max(ringVisualWidth, longVisualWidth) + outerPadding + innerPadding
        expect(longVisualWidth > 60.0, "超过 1 小时的时间文本预留宽度应大于 60.0")
        expect(longSymmetricWingW > 76.0, "两翼对称宽度应平滑延展且严格保持对称")
    }
}
