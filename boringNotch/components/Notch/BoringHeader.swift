//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

/// The expanded notch header keeps compact status controls on both sides of
/// the physical notch. Primary navigation lives in the bottom bar.
struct BoringHeader: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    var body: some View {
        HStack(spacing: 0) {
            leadingStatus
                .frame(maxWidth: .infinity, alignment: .leading)

            if vm.notchState == .open {
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width)
                    .mask { NotchShape() }
            }

            trailingStatus
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.gray)
        .opacity(vm.notchState == .closed ? 0 : 1)
        .blur(radius: vm.notchState == .closed ? 20 : 0)
        .font(.system(.headline, design: .rounded))
    }

    @ViewBuilder
    private var leadingStatus: some View {
        if vm.notchState == .open {
            HStack(spacing: 4) {
                if Defaults[.showMirror] {
                    headerButton(systemName: "web.camera") {
                        vm.toggleCameraPreview()
                    }
                }

                if Defaults[.settingsIconInNotch] {
                    headerButton(systemName: "gear") {
                        DispatchQueue.main.async {
                            SettingsWindowController.shared.showWindow()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if vm.notchState == .open {
            if isHUDType(coordinator.sneakPeek.type)
                && coordinator.sneakPeek.show
                && Defaults[.showOpenNotchHUD]
            {
                OpenNotchHUD(
                    type: $coordinator.sneakPeek.type,
                    value: $coordinator.sneakPeek.value,
                    icon: $coordinator.sneakPeek.icon
                )
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if Defaults[.showBatteryIndicator] {
                BoringBatteryView(
                    batteryWidth: 30,
                    isCharging: batteryModel.isCharging,
                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                    isPluggedIn: batteryModel.isPluggedIn,
                    levelBattery: batteryModel.levelBattery,
                    maxCapacity: batteryModel.maxCapacity,
                    timeToFullCharge: batteryModel.timeToFullCharge,
                    isForNotification: false
                )
            }
        }
    }

    private func headerButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: systemName)
                        .foregroundStyle(.white)
                        .imageScale(.medium)
                }
        }
        .buttonStyle(.plain)
    }

    private func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
