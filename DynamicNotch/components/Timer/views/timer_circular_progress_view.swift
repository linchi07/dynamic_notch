//
//  timer_circular_progress_view.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import SwiftUI

/// 模仿 iOS 灵动岛计时器风格的大号圆形倒计时轮盘，支持转满开场动画与仿真滑动数字
struct TimerCircularProgressView: View {
    @ObservedObject var timerManager = TimerManager.shared

    var size: CGFloat = 82
    var lineWidth: CGFloat = 6.0

    @State private var windUpProgress: Double = 0.0
    @State private var isWindingUp: Bool = false

    private var activeProgress: Double {
        if isWindingUp {
            return windUpProgress
        }
        return timerManager.remainingProgress
    }

    private var ringGradient: LinearGradient {
        if timerManager.status == .paused {
            return LinearGradient(
                colors: [Color.gray, Color.gray.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if timerManager.currentPreset?.id == TimerPresetConstants.DEFAULT_EYE_REST.id {
            return LinearGradient(
                colors: [Color.green, Color.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.orange, Color(red: 1.0, green: 0.65, blue: 0.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var accentColor: Color {
        if timerManager.status == .paused {
            return .gray
        } else if timerManager.currentPreset?.id == TimerPresetConstants.DEFAULT_EYE_REST.id {
            return .green
        } else {
            return .orange
        }
    }

    var body: some View {
        let radius = (size - lineWidth) / 2

        ZStack {
            // 背景底圈轨道
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // 动态进度圆环（从顶部顺时针倒数）
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, activeProgress))))
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)

            // 中心内容：仿真滚动的倒计时数字
            VStack(spacing: 2) {
                slidingTimeDisplay
                    .frame(maxWidth: size - 10)
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                timerManager.togglePlayPause()
            }
        }
        .onAppear {
            triggerWindUpAnimationIfNeeded()
        }
        .onChange(of: timerManager.status) { oldStatus, newStatus in
            if oldStatus == .idle && (newStatus == .running || newStatus == .paused) {
                triggerWindUpAnimationIfNeeded()
            }
        }
    }

    /// 数字仿真滑动翻滚的倒计时文本组件
    @ViewBuilder
    private var slidingTimeDisplay: some View {
        let total = Int(ceil(timerManager.remainingSeconds))
        let minutes = total / 60
        let seconds = total % 60

        HStack(spacing: 1) {
            Text(String(format: "%02d", minutes))
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))

            Text(":")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))

            Text(String(format: "%02d", seconds))
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
        }
        .animation(.snappy(duration: 0.3), value: timerManager.remainingSeconds)
    }

    /// 触发轮盘从 0 顺滑转满的发条开场动画
    private func triggerWindUpAnimationIfNeeded() {
        guard timerManager.status == .running || timerManager.status == .paused else { return }
        windUpProgress = 0.0
        isWindingUp = true

        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            windUpProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isWindingUp = false
        }
    }
}
