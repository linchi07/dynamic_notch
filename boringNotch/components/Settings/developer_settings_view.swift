//
//  developer_settings_view.swift
//  boringNotch
//
//  Created on 2026-09-14.
//

import SwiftUI

/// Developer control panel for testing floating notifications, battery ejection states, and debug toggles
struct DeveloperSettingsView: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared

    @State private var simulatedLevel: Float = 85.0
    @State private var simulatedIsPluggedIn: Bool = true
    @State private var simulatedIsCharging: Bool = true
    @State private var simulatedIsLowPowerMode: Bool = false
    @State private var simulatedIsLowBatteryAlert: Bool = false
    @State private var simulatedTimeToFull: Int = 45
    @State private var simulatedDuration: Double = 2.0

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("电池状态胶囊快速触发")
                        .font(.headline)
                    Text("点击下方预设按钮，可直接触发对应电池状态的两阶段下探与两阶段回收通知。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                // 1. Green Theme States (>20%)
                VStack(alignment: .leading, spacing: 6) {
                    Label("绿色填充状态（正常电量 > 20%）", systemImage: "battery.100.bolt")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.green)

                    HStack(spacing: 8) {
                        Button("🟢 85% 正在充电 (预计35分充满)") {
                            triggerSimulated(
                                level: 85,
                                isPluggedIn: true,
                                isCharging: true,
                                isLowPower: false,
                                isAlert: false,
                                timeToFull: 35
                            )
                        }

                        Button("🟢 100% 已充满") {
                            triggerSimulated(
                                level: 100,
                                isPluggedIn: true,
                                isCharging: false,
                                isLowPower: false,
                                isAlert: false
                            )
                        }

                        Button("⚪ 72% 已连接未充电") {
                            triggerSimulated(
                                level: 72,
                                isPluggedIn: true,
                                isCharging: false,
                                isLowPower: false,
                                isAlert: false
                            )
                        }
                    }
                }
                .padding(.vertical, 4)

                // 2. Red Theme States (<=20%)
                VStack(alignment: .leading, spacing: 6) {
                    Label("红色填充状态（低电量 <= 20%）", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.red)

                    HStack(spacing: 8) {
                        Button("🔴 20% 低电量告警 (含开启按钮)") {
                            triggerSimulated(
                                level: 20,
                                isPluggedIn: false,
                                isCharging: false,
                                isLowPower: false,
                                isAlert: true
                            )
                        }

                        Button("🔴 12% 低电量接入充电") {
                            triggerSimulated(
                                level: 12,
                                isPluggedIn: true,
                                isCharging: true,
                                isLowPower: false,
                                isAlert: false,
                                timeToFull: 90
                            )
                        }
                    }
                }
                .padding(.vertical, 4)

                // 3. Yellow Theme States (Low Power Mode)
                VStack(alignment: .leading, spacing: 6) {
                    Label("黄色填充状态（低电量模式启用）", systemImage: "bolt.badge.automatic.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.yellow)

                    HStack(spacing: 8) {
                        Button("🟡 18% 低电量模式已开启") {
                            triggerSimulated(
                                level: 18,
                                isPluggedIn: false,
                                isCharging: false,
                                isLowPower: true,
                                isAlert: false
                            )
                        }

                        Button("🟡 45% 低电量模式充电中") {
                            triggerSimulated(
                                level: 45,
                                isPluggedIn: true,
                                isCharging: true,
                                isLowPower: true,
                                isAlert: false,
                                timeToFull: 50
                            )
                        }
                    }
                }
                .padding(.vertical, 4)

                // Dismiss Button
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        coordinator.dismissNotification()
                    } label: {
                        Label("立即收回通知 (测试两阶段收回)", systemImage: "xmark.circle")
                    }
                }
            } header: {
                Text("一键测试状态 (Presets)")
            }

            // Custom Interactive Playground
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("模拟电量: \(Int(simulatedLevel))%")
                            .font(.system(size: 12, weight: .medium))
                        Slider(value: $simulatedLevel, in: 0...100, step: 1)
                    }

                    Toggle("已接入电源 (isPluggedIn)", isOn: $simulatedIsPluggedIn)
                    Toggle("正在充电 (isCharging)", isOn: $simulatedIsCharging)
                    Toggle("低电量模式 (isInLowPowerMode)", isOn: $simulatedIsLowPowerMode)
                    Toggle("低电量告警模式 (isLowBatteryAlert)", isOn: $simulatedIsLowBatteryAlert)

                    HStack {
                        Text("显示时长: \(String(format: "%.1f", simulatedDuration))s")
                            .font(.system(size: 12, weight: .medium))
                        Slider(value: $simulatedDuration, in: 2...15, step: 0.5)
                    }

                    Button {
                        triggerSimulated(
                            level: simulatedLevel,
                            isPluggedIn: simulatedIsPluggedIn,
                            isCharging: simulatedIsCharging,
                            isLowPower: simulatedIsLowPowerMode,
                            isAlert: simulatedIsLowBatteryAlert,
                            timeToFull: simulatedTimeToFull,
                            duration: simulatedDuration
                        )
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("发射自定义模拟通知")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            } header: {
                Text("自定义状态调试 (Playground)")
            }

            // Real Hardware Status
            Section {
                LabeledContent("真实硬件电量", value: "\(Int(batteryModel.levelBattery))%")
                LabeledContent("真实电源接入", value: batteryModel.isPluggedIn ? "已连接" : "未连接")
                LabeledContent("真实正在充电", value: batteryModel.isCharging ? "是" : "否")
                LabeledContent("真实低电量模式", value: batteryModel.isInLowPowerMode ? "已开启" : "已关闭")

                Button("使用当前真实硬件状态发送通知") {
                    batteryModel.triggerBatteryNotification(isLowBatteryAlert: false)
                }
            } header: {
                Text("当前 Mac 真实电池硬件状态")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Developer")
    }

    private func triggerSimulated(
        level: Float,
        isPluggedIn: Bool,
        isCharging: Bool,
        isLowPower: Bool,
        isAlert: Bool,
        timeToFull: Int = 0,
        duration: Double = 2.0
    ) {
        coordinator.postBatteryNotification(
            level: level,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            isInLowPowerMode: isLowPower,
            isLowBatteryAlert: isAlert,
            timeToFullCharge: timeToFull,
            duration: duration
        )
    }
}
