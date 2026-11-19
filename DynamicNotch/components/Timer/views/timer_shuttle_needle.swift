//
//  timer_shuttle_needle.swift
//  DynamicNotch
//
//  Created on 2026-11-19.
//

import SwiftUI

/// 现代 Apple 风格极简表针：从圆心根部（粗）到针尖（细）平滑渐缩的锥形直线指针
struct TaperedNeedleShape: Shape {
    /// 根部（圆心端）半宽
    var baseHalfWidth: CGFloat = 1.3
    /// 针尖（圆周端）半宽
    var tipHalfWidth: CGFloat = 0.45
    /// 针尾相对圆心的微小延展
    var tailOffset: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let centerY = rect.midY
        let length = min(rect.width, rect.height) / 2.0

        // 顶端针尖（12 点钟方向，细致微圆角）
        let tipLeft = CGPoint(x: centerX - tipHalfWidth, y: centerY - length)
        let tipRight = CGPoint(x: centerX + tipHalfWidth, y: centerY - length)

        // 底端根部（圆心处，较粗饱满）
        let baseRight = CGPoint(x: centerX + baseHalfWidth, y: centerY + tailOffset)
        let baseLeft = CGPoint(x: centerX - baseHalfWidth, y: centerY + tailOffset)

        path.move(to: baseLeft)
        path.addLine(to: tipLeft)
        path.addQuadCurve(to: tipRight, control: CGPoint(x: centerX, y: centerY - length - tipHalfWidth * 0.6))
        path.addLine(to: baseRight)
        path.addQuadCurve(to: baseLeft, control: CGPoint(x: centerX, y: centerY + tailOffset + baseHalfWidth * 0.6))
        path.closeSubpath()

        return path
    }
}

/// 现代 Apple 风格倒计时指针组件：无明显箭头，纯粹的由粗至细极简线条，精准指向圆弧末端
struct ModernTaperedNeedle: View {
    var progress: Double
    var radius: CGFloat
    var baseHalfWidth: CGFloat = 1.2
    var tipHalfWidth: CGFloat = 0.4
    var color: Color = .orange

    private var rotationAngle: Double {
        360.0 * max(0, min(1, progress))
    }

    var body: some View {
        TaperedNeedleShape(
            baseHalfWidth: baseHalfWidth,
            tipHalfWidth: tipHalfWidth,
            tailOffset: 0.3
        )
        .fill(color)
        .frame(width: radius * 2, height: radius * 2)
        .rotationEffect(.degrees(rotationAngle))
    }
}
