//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
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
let ALBUM_ART_CORNER_RADIUS_CLOSED: CGFloat = 4.0

/// 展开状态下面板容器的固定高度（Home/Shelf 等面板统一固定在此高度）
let NOTCH_PANEL_CONTAINER_HEIGHT: CGFloat = 98

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let openNotchSize: CGSize = .init(width: 460, height: 170)
let windowSize: CGSize = .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
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

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            // The auxiliary menu-bar areas terminate at the physical notch edges.
            // Do not add virtual padding here; active wings own their outer padding.
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
