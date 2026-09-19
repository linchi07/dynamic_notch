//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var shelfState = ShelfStateViewModel.shared
    @ObservedObject private var scratchpadState = ScratchpadViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace private var notchHeroNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.notchOuterPadding) private var notchOuterPadding

    @Default(.showNotHumanFace) var showNotHumanFace

    private var isUnifiedHUDVisible: Bool {
        coordinator.sneakPeek.show &&
        (coordinator.sneakPeek.type == .volume || coordinator.sneakPeek.type == .brightness || coordinator.sneakPeek.type == .backlight || coordinator.sneakPeek.type == .mic)
    }

    private var notchBottomY: CGFloat {
        vm.notchState == .open
            ? vm.notchSize.height
            : vm.effectiveClosedNotchHeight
    }

    private var floatingNotificationOffsetY: CGFloat {
        notchBottomY + 8
    }

    private var floatingHUDOffsetY: CGFloat {
        let notificationBottom = floatingNotificationOffsetY + 30
        let anchorBottom = coordinator.isNotificationPresented
            ? max(notchBottomY, notificationBottom)
            : notchBottomY
        let spacing: CGFloat = coordinator.isNotificationPresented
            ? 8
            : (vm.notchState == .open ? 16 : 8)
        return anchorBottom + spacing
    }

    // Unified interactive spring for movement/resizing to keep hero and notch layout strictly in sync
    private let NOTCH_OPEN_SPRING = Animation.interactiveSpring(response: 0.40, dampingFraction: 0.82, blendDuration: 0)
    private let NOTCH_CLOSE_SPRING = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.85, blendDuration: 0)
    private let NOTIFICATION_CONTENT_SLIDE_SPRING = Animation.spring(response: 0.36, dampingFraction: 0.88)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var shouldShowMusicActivity: Bool {
        vm.notchState == .closed
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled
            && !vm.hideOnClosed
    }

    private var musicActiveState: NotchActiveState {
        let tint = Defaults[.coloredSpectrogram]
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
            : Color.gray
        let trailingVisual: NotchActivityVisual = useMusicVisualizer
            ? .audioVisualizer
            : .system(name: "waveform")

        return NotchActiveState(
            activity: NotchLiveActivity(
                id: "music.playback",
                leading: NotchActivityItem(
                    visual: .customImage(image: musicManager.albumArt),
                    accessibilityLabel: musicManager.songTitle,
                    heroId: NotchHeroIdentifier.MUSIC_ARTWORK.rawValue
                ),
                trailing: NotchActivityItem(
                    visual: trailingVisual,
                    tintColor: tint,
                    accessibilityLabel: musicManager.isPlaying ? "Playing" : "Paused"
                )
            )
        )
    }

    /// 获取当前生效的常驻持续活动状态（用于通知打断检测）
    private var activeStateForInterruptionCheck: NotchActiveState? {
        if case .active(let state) = coordinator.displayMode {
            return state
        }
        if case .active(let priorState) = coordinator.stateBeforeNotification {
            return priorState
        }
        if shouldShowMusicActivity {
            return musicActiveState
        }
        return nil
    }

    private var effectiveDisplayMode: NotchDisplayMode {
        switch coordinator.displayMode {
        case .idle:
            if let active = activeStateForInterruptionCheck {
                return .active(active)
            }
            return .idle

        case .active(let state):
            return .active(state)

        case .notification(let item):
            if let active = activeStateForInterruptionCheck {
                // 仅当通知为持续活动自身的更新事件（如切歌）且匹配当前活动 ID 时，才打断当前活动收起翅膀
                let isCurrentActivityUpdate = item.category == .activityUpdate
                    && item.activityId != nil
                    && active.activities.contains(where: { $0.id == item.activityId })

                if isCurrentActivityUpdate {
                    return .notification(item)
                } else {
                    // 系统事件（如电池警告）或非当前活动的通知，不打断持续活动，刘海翅膀保持显示
                    return .active(active)
                }
            }
            return .notification(item)
        }
    }

    private var shouldShowBottomNavigation: Bool {
        (Defaults[.boringShelf] && (!shelfState.isEmpty || coordinator.alwaysShowTabs))
            || !scratchpadState.isEmpty
            || coordinator.currentView == .scratchpad
    }

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if case .active = effectiveDisplayMode, vm.notchState == .closed {
            chinWidth = NotchLayoutMetrics.activeWidth(
                physicalNotchWidth: vm.closedNotchSize.width,
                notchHeight: vm.effectiveClosedNotchHeight,
                outerPadding: notchOuterPadding
            )
        } else if vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 16)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            if isUnifiedHUDVisible {
                FloatingHUDBar(
                    type: $coordinator.sneakPeek.type,
                    value: $coordinator.sneakPeek.value,
                    icon: $coordinator.sneakPeek.icon
                )
                .offset(y: floatingHUDOffsetY)
                .transition(FloatingPopupStyle.transition)
                .zIndex(0)
            }

            if let notification = coordinator.activeNotification {
                let contentWidth: CGFloat = notification.isBattery ? 246 : 224
                let contentHeight: CGFloat = 30

                FloatingNotificationContainer(
                    isPresented: $coordinator.isNotificationPresented,
                    autoDismissAfter: notification.duration,
                    updateTrigger: notification.id,
                    onDismiss: {
                        coordinator.notificationDidDismiss()
                    }
                ) { isContentVisible in
                    ZStack {
                        Group {
                            switch notification.payload {
                            case .standard:
                                FloatingNotificationPopup(
                                    item: notification,
                                    isContentVisible: isContentVisible
                                ) {
                                    coordinator.dismissNotification()
                                }
                            case .battery(let batteryData):
                                BatteryNotificationPopup(
                                    payload: batteryData,
                                    isContentVisible: isContentVisible,
                                    onEnableLowPowerMode: {
                                        BatteryStatusViewModel.shared.enableLowPowerMode()
                                    },
                                    onClose: {
                                        coordinator.dismissNotification()
                                    }
                                )
                            }
                        }
                        .id(notification.id)
                        .transition(
                            .asymmetric(
                                insertion: .offset(x: contentWidth),
                                removal: .offset(x: -contentWidth)
                            )
                        )
                    }
                    .frame(width: contentWidth, height: contentHeight)
                    .clipShape(Capsule())
                    .animation(NOTIFICATION_CONTENT_SLIDE_SPRING, value: notification.id)
                }
                .offset(y: floatingNotificationOffsetY)
                .animation(FloatingPopupStyle.anchorAnimation, value: floatingNotificationOffsetY)
                .zIndex(0.5)
            }

            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : 0
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .animation(.smooth, value: gestureProgress)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.doClose()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.doClose()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
            .zIndex(1)
        }
        .animation(FloatingPopupStyle.springAnimation, value: isUnifiedHUDVisible)
        .animation(FloatingPopupStyle.anchorAnimation, value: floatingHUDOffsetY)
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .environment(\.notchHeroNamespace, notchHeroNamespace)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    if DropRouterService.shared.isDraggingPlainText() {
                        coordinator.currentView = .scratchpad
                    } else {
                        coordinator.currentView = .shelf
                    }
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    doClose()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if case .active(let activeState) = effectiveDisplayMode, vm.notchState == .closed {
                          NotchWingsContainer(state: activeState)
                              .frame(alignment: .center)
                      } else if vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
                       }
                  }
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack(spacing: 4) {
                    NotchPanelContainer()

                    if shouldShowBottomNavigation {
                        Spacer(minLength: 0)
                        TabSelectionView()
                            .padding(.bottom, 2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.clear)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )
                .padding(.leading, 8)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)
            MinimalFaceFeatures()
                .padding(.trailing, 8)
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            DropRouterService.shared.handleDrop(providers: providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        if coordinator.isNotificationPresented {
            coordinator.dismissNotification()
        }
        withAnimation(NOTCH_OPEN_SPRING) {
            vm.open()
        }
    }

    private func doClose() {
        withAnimation(NOTCH_CLOSE_SPRING) {
            vm.close()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(NOTCH_OPEN_SPRING) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(NOTCH_CLOSE_SPRING) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.doClose()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(NOTCH_CLOSE_SPRING) { gestureProgress = .zero }
            return
        }

        withAnimation(NOTCH_OPEN_SPRING) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(NOTCH_OPEN_SPRING) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(NOTCH_CLOSE_SPRING) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(NOTCH_CLOSE_SPRING) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(NOTCH_CLOSE_SPRING) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                doClose()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
