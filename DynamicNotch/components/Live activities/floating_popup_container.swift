//
//  floating_popup_container.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Reusable floating container positioned beneath the MacBook notch for fast sliders (volume/brightness).
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
            // Ambient hover glow to pop out from wallpaper
            .shadow(color: Color.white.opacity(0.14), radius: 6, x: 0, y: 0)
            .shadow(color: Color.white.opacity(0.06), radius: 14, x: 0, y: 0)
            // Spatial drop shadow
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 5)
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

    /// Keeps stacked popups attached to a notch or notification whose bottom
    /// edge can change while the HUD is already visible.
    static var anchorAnimation: Animation {
        .interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.08)
    }

    /// Fluid slider physics with inertia: slight launch delay followed by vigorous acceleration
    static var fluidSliderSpring: Animation {
        .interpolatingSpring(mass: 0.85, stiffness: 135, damping: 14.5)
    }

    /// Responsive bouncy spring for boundary collisions and rubber-banding
    static var bounceSpring: Animation {
        .interpolatingSpring(mass: 0.5, stiffness: 220, damping: 12)
    }

    /// High-impact elastic bounce for releasing boundary tension (BOING effect)
    static var strongBounceSpring: Animation {
        .interpolatingSpring(mass: 0.45, stiffness: 340, damping: 9.5)
    }

    static var transition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.88, anchor: .top)
                .combined(with: .offset(y: -16))
                .combined(with: .opacity),
            removal: .scale(scale: 0.88, anchor: .top)
                .combined(with: .offset(y: -14))
                .combined(with: .opacity)
        )
    }
}
