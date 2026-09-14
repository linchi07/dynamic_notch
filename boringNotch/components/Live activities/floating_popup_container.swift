//
//  floating_popup_container.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Reusable floating container positioned beneath the MacBook notch.
/// Designed for modular popups (volume/brightness sliders, clipboard, shortcuts, etc.)
struct FloatingPopupContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(0.85)
                    Color(white: 0.18)
                        .opacity(0.55)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: FloatingPopupStyle.CORNER_RADIUS, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
    }
}

/// Unified animation and transition specifications for notch floating popups
enum FloatingPopupStyle {
    static let CORNER_RADIUS: CGFloat = 10
    static let SPRING_RESPONSE: Double = 0.32
    static let SPRING_DAMPING: Double = 0.78

    static var springAnimation: Animation {
        .spring(response: SPRING_RESPONSE, dampingFraction: SPRING_DAMPING)
    }

    /// Fluid slider physics with inertia: slight launch delay followed by vigorous acceleration
    static var fluidSliderSpring: Animation {
        .interpolatingSpring(mass: 0.85, stiffness: 135, damping: 14.5)
    }

    static var transition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.85, anchor: .top)
                .combined(with: .offset(y: -14))
                .combined(with: .opacity),
            removal: .scale(scale: 0.9, anchor: .top)
                .combined(with: .offset(y: -10))
                .combined(with: .opacity)
        )
    }
}
