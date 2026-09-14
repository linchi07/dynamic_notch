//
//  floating_hud_bar.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Composed Floating HUD Bar that combines FloatingPopupContainer and VolumeSliderContent
struct FloatingHUDBar: View {
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String

    var body: some View {
        FloatingPopupContainer {
            VolumeSliderContent(type: $type, value: $value, icon: $icon)
        }
    }
}

#Preview {
    struct FloatingHUDBarPreview: View {
        @State private var type: SneakContentType = .volume
        @State private var value: CGFloat = 0.65
        @State private var icon: String = ""

        var body: some View {
            FloatingHUDBar(type: $type, value: $value, icon: $icon)
                .environmentObject(BoringViewModel())
                .padding(40)
                .background(Color.blue.opacity(0.3))
        }
    }

    return FloatingHUDBarPreview()
}
