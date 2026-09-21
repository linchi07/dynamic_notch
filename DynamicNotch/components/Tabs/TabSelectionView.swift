//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    let label: String
    let icon: String
    let view: NotchViews

    var id: NotchViews { view }
}

let tabs = [
    TabModel(label: "Home", icon: "waveform", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Notes", icon: "note.text", view: .scratchpad)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(width: 34, height: 18)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(tab.view == coordinator.currentView ? .isSelected : [])
            }
        }
        .padding(1)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .zIndex(3)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
