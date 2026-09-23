//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Foundation
import SwiftUI

// MARK: - Notch Curvature & Layout Constants
let OPEN_NOTCH_TOP_CORNER_RADIUS: CGFloat = 22
let OPEN_NOTCH_BOTTOM_CORNER_RADIUS: CGFloat = 28
let CLOSED_NOTCH_TOP_CORNER_RADIUS: CGFloat = 6
let CLOSED_NOTCH_BOTTOM_CORNER_RADIUS: CGFloat = 14

/// 专辑插图距刘海外轮廓的同心间距（提前预置，避免运行时计算）
let ALBUM_ART_INSET_FROM_NOTCH: CGFloat = 12
/// 展开时统一的专辑插图曲率（同心平滑圆角：外圆角 - 边距）
let ALBUM_ART_CORNER_RADIUS_OPENED: CGFloat = OPEN_NOTCH_BOTTOM_CORNER_RADIUS - ALBUM_ART_INSET_FROM_NOTCH
/// 闭合时统一的专辑插图曲率
let ALBUM_ART_CORNER_RADIUS_CLOSED: CGFloat = 6

/// 展开状态下面板容器的固定高度（Home/Shelf 等面板统一固定在此高度）
let NOTCH_PANEL_CONTAINER_HEIGHT: CGFloat = 103

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
/// Extra transparent window space used by HUDs that appear below an expanded notch.
let floatingOverlaySpace: CGFloat = 64
let openNotchSize: CGSize = .init(width: 460, height: 181)
let windowSize: CGSize = .init(
    width: openNotchSize.width,
    height: openNotchSize.height + shadowPadding + floatingOverlaySpace
)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (
    opened: (top: OPEN_NOTCH_TOP_CORNER_RADIUS, bottom: OPEN_NOTCH_BOTTOM_CORNER_RADIUS),
    closed: (top: CLOSED_NOTCH_TOP_CORNER_RADIUS, bottom: CLOSED_NOTCH_BOTTOM_CORNER_RADIUS)
)

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (
        opened: ALBUM_ART_CORNER_RADIUS_OPENED,
        closed: ALBUM_ART_CORNER_RADIUS_CLOSED
    )
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame() -> CGRect? {
    NSScreen.supportedBuiltInDisplay?.frame
}

@MainActor func getClosedNotchSize() -> CGSize {
    guard let screen = NSScreen.supportedBuiltInDisplay else {
        return .zero
    }

    var notchWidth: CGFloat = 185

    if let leftWidth = screen.auxiliaryTopLeftArea?.width,
       let rightWidth = screen.auxiliaryTopRightArea?.width
    {
        notchWidth = screen.frame.width - leftWidth - rightWidth
    }

    return .init(width: notchWidth, height: screen.safeAreaInsets.top)
}
