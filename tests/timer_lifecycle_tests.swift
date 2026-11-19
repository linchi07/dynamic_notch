//
//  timer_lifecycle_tests.swift
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

/// 模拟计时器核心状态与进度引擎
final class MockTimerEngine {
    var status: String = "idle"
    var remainingSeconds: TimeInterval = 0
    var totalDuration: TimeInterval = 0
    var currentTitle: String = "计时器"

    var remainingProgress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, remainingSeconds / totalDuration))
    }

    var elapsedProgress: Double {
        guard totalDuration > 0 else { return 0 }
        return max(0, min(1, 1.0 - (remainingSeconds / totalDuration)))
    }

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

    func start(duration: TimeInterval, title: String) {
        totalDuration = duration
        remainingSeconds = duration
        currentTitle = title
        status = "running"
    }

    func pause() {
        if status == "running" {
            status = "paused"
        }
    }

    func resume() {
        if status == "paused" {
            status = "running"
        }
    }

    func toggle() {
        if status == "running" {
            pause()
        } else if status == "paused" {
            resume()
        }
    }

    func reset() {
        status = "idle"
        remainingSeconds = 0
        totalDuration = 0
    }

    func addSeconds(_ seconds: TimeInterval) {
        if status == "running" || status == "paused" {
            remainingSeconds += seconds
            totalDuration += seconds
        }
    }

    func tick(elapsed: TimeInterval) {
        if status == "running" {
            remainingSeconds -= elapsed
            if remainingSeconds <= 0 {
                remainingSeconds = 0
                status = "completed"
            }
        }
    }
}

@main
struct TimerLifecycleTests {
    static func main() async throws {
        print("开始运行 Timer 逻辑引擎与边界条件测试...")

        let engine = MockTimerEngine()

        // 1. 初始状态
        expect(engine.status == "idle", "初始状态应为 idle")
        expect(engine.remainingSeconds == 0, "初始剩余时间为 0")
        expect(engine.formattedTime == "00:00", "初始时间文本为 00:00")

        // 2. 启动 25 分钟番茄钟
        engine.start(duration: 25 * 60, title: "番茄钟")
        expect(engine.status == "running", "启动后状态应为 running")
        expect(engine.totalDuration == 1500, "总时长应为 1500 秒")
        expect(engine.remainingSeconds == 1500, "初始剩余 1500 秒")
        expect(engine.formattedTime == "25:00", "时间应显示为 25:00")
        expect(engine.remainingProgress == 1.0, "初始剩余比例为 1.0")
        expect(engine.elapsedProgress == 0.0, "初始消耗比例为 0.0")

        // 3. 走过 300 秒（5分钟）
        engine.tick(elapsed: 300)
        expect(engine.remainingSeconds == 1200, "流逝5分钟后剩余 1200 秒")
        expect(engine.formattedTime == "20:00", "时间显示为 20:00")
        expect(abs(engine.remainingProgress - 0.8) < 0.001, "剩余进度比率为 0.8")
        expect(abs(engine.elapsedProgress - 0.2) < 0.001, "消耗进度比率为 0.2")

        // 4. 暂停与继续
        engine.pause()
        expect(engine.status == "paused", "暂停后状态为 paused")
        engine.tick(elapsed: 100) // 暂停时不应扣除时间
        expect(engine.remainingSeconds == 1200, "暂停期间时间应保持不变")

        engine.resume()
        expect(engine.status == "running", "继续后状态为 running")

        // 5. 快速加时 (+60 秒)
        engine.addSeconds(60)
        expect(engine.remainingSeconds == 1260, "加时后剩余 1260 秒")
        expect(engine.totalDuration == 1560, "加时后总时长为 1560 秒")
        expect(engine.formattedTime == "21:00", "时间显示为 21:00")

        // 6. 切换（Toggle）
        engine.toggle()
        expect(engine.status == "paused", "toggle 应变为 paused")
        engine.toggle()
        expect(engine.status == "running", "toggle 应变为 running")

        // 7. 40 分钟望远护眼启动与倒计时结束测试
        engine.start(duration: 40 * 60, title: "望远护眼")
        expect(engine.status == "running", "启动望远护眼应为 running")
        expect(engine.totalDuration == 2400, "望远总时长应为 2400 秒 (40分钟)")
        expect(engine.formattedTime == "40:00", "时间显示为 40:00")

        // 模拟时间走完
        engine.tick(elapsed: 2400)
        expect(engine.status == "completed", "时间到达 0 后状态应为 completed")
        expect(engine.remainingSeconds == 0, "完成时剩余时间为 0")
        expect(engine.formattedTime == "00:00", "完成时格式化时间为 00:00")

        // 8. 重置
        engine.reset()
        expect(engine.status == "idle", "重置后状态为 idle")

        print("✅ Timer 逻辑引擎与边界条件测试全部通过！")
    }
}
