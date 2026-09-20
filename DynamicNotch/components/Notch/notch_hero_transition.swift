//
//  notch_hero_transition.swift
//  boringNotch
//
//  Created on 2026-09-16.
//

import SwiftUI

/// Hero 动效标识符，用于在刘海闭合翅膀与展开面板对应元素之间建立转场几何映射
struct NotchHeroIdentifier: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// 音乐专辑封面 Hero 标识符
    static let MUSIC_ARTWORK: NotchHeroIdentifier = "notch_hero_music_artwork"
}

// MARK: - Environment Namespace

private struct NotchHeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// 全局刘海 Hero 动效命名空间
    var notchHeroNamespace: Namespace.ID? {
        get { self[NotchHeroNamespaceKey.self] }
        set { self[NotchHeroNamespaceKey.self] = newValue }
    }
}

// MARK: - Hero Modifiers

/// 闭合态刘海翅膀中的 Hero 动效源修饰器
struct NotchHeroSourceModifier: ViewModifier {
    let id: String?
    let isSource: Bool
    @Environment(\.notchHeroNamespace) private var heroNamespace

    func body(content: Content) -> some View {
        if let id, let heroNamespace {
            content
                .matchedGeometryEffect(id: id, in: heroNamespace, isSource: isSource)
        } else {
            content
        }
    }
}

/// 展开面板中的 Hero 动效目标修饰器
struct NotchHeroDestinationModifier: ViewModifier {
    let id: String?
    let isSource: Bool
    @Environment(\.notchHeroNamespace) private var heroNamespace

    func body(content: Content) -> some View {
        if let id, let heroNamespace {
            content
                .matchedGeometryEffect(id: id, in: heroNamespace, isSource: isSource)
        } else {
            content
        }
    }
}

extension View {
    /// 标记视图为刘海 Hero 动效源（例如闭合态 Live Activity 的图标或封面）
    func notchHeroSource(id: String?, isSource: Bool = true) -> some View {
        modifier(NotchHeroSourceModifier(id: id, isSource: isSource))
    }

    /// 标记视图为刘海 Hero 动效目标（例如展开态详情面板中的大图或图标）
    func notchHeroDestination(id: String?, isSource: Bool = true) -> some View {
        modifier(NotchHeroDestinationModifier(id: id, isSource: isSource))
    }
}
