import AppKit
import Combine
import SwiftUI
import FocusCore

@MainActor
final class PomodoroMenuBarTimerController {
    private let settings: AppSettings
    private var pomodoroTimer: PomodoroTimer?

    private var hostingController: NSHostingController<PomodoroMenuBarTimerView>?
    private var panel: NSPanel?
    private var hoverPollingTimer: Timer?

    private var expandedHostingController: NSHostingController<PomodoroExpandedTimerView>?
    private var expandedPanel: FocusModePanel?
    private var expandedKeyMonitor: Any?

    private var settingsCancellables = Set<AnyCancellable>()
    private var timerCancellables = Set<AnyCancellable>()
    private var isVisible = false
    private var forceVisibleUntil: Date = .distantPast

    private var isExpanded = false
    private var keepExpandedCycle = false
    private var pendingReexpandAfterBreak = false
    private var lastObservedPhase: PomodoroPhase = .idle

    init(settings: AppSettings) {
        self.settings = settings

        settings.$pomodoroEnabled
            .combineLatest(settings.$pomodoroMenuBarTimerEnabled)
            .sink { [weak self] _, _ in
                self?.refreshPanelState()
            }
            .store(in: &settingsCancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.repositionPanel()
                self?.repositionExpandedPanel()
            }
            .store(in: &settingsCancellables)

        startHoverPolling()
    }

    func setPomodoroTimer(_ timer: PomodoroTimer?) {
        let previousTimer = pomodoroTimer
        pomodoroTimer = timer
        timerCancellables.removeAll()

        if previousTimer !== timer {
            closePanel()
            closeExpandedPanel()
            keepExpandedCycle = false
            pendingReexpandAfterBreak = false
        }

        lastObservedPhase = timer?.phase ?? .idle

        timer?.$remainingSeconds
            .sink { [weak self] _ in
                self?.repositionPanel()
            }
            .store(in: &timerCancellables)

        timer?.$phase
            .sink { [weak self] phase in
                guard let self else { return }
                self.handlePhaseChange(phase)
                self.forceReveal()
                self.refreshPanelState()
            }
            .store(in: &timerCancellables)

        refreshPanelState()
    }

    private var shouldManagePanel: Bool {
        settings.pomodoroEnabled &&
        settings.pomodoroMenuBarTimerEnabled &&
        pomodoroTimer != nil
    }

    private func refreshPanelState() {
        guard shouldManagePanel else {
            closePanel()
            closeExpandedPanel()
            return
        }

        if isExpanded {
            if let timer = pomodoroTimer {
                ensureExpandedPanel(timer: timer)
            }
            repositionExpandedPanel()
            return
        }

        ensurePanel()
        repositionPanel()
        updateVisibility()
    }

    private func ensurePanel() {
        guard panel == nil, let timer = pomodoroTimer else { return }

        let content = PomodoroMenuBarTimerView(
            timer: timer,
            onStart: { [weak self, timer] in
                guard let self else { return }
                timer.startFocus()
                self.forceReveal()
            },
            onStop: { [weak self, timer] in
                guard let self else { return }
                timer.stop()
                self.keepExpandedCycle = false
                self.pendingReexpandAfterBreak = false
                if self.isExpanded {
                    self.collapseFocusMode(manual: false)
                }
                self.forceReveal()
            },
            onExpand: { [weak self] in
                self?.expandFocusMode(manual: true)
            }
        )

        let hosting = NSHostingController(rootView: content)
        hosting.view.frame.size = hosting.view.fittingSize
        let size = hosting.view.fittingSize
        let frame = targetFrame(for: size)

        let createdPanel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        createdPanel.isReleasedWhenClosed = false
        createdPanel.isOpaque = false
        createdPanel.backgroundColor = .clear
        createdPanel.hasShadow = false
        createdPanel.level = .statusBar
        createdPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        createdPanel.contentViewController = hosting
        createdPanel.alphaValue = 0
        createdPanel.orderOut(nil)

        hostingController = hosting
        panel = createdPanel
    }

    private func ensureExpandedPanel(timer: PomodoroTimer) {
        guard expandedPanel == nil else { return }

        let content = PomodoroExpandedTimerView(
            timer: timer,
            onCollapse: { [weak self] in
                self?.collapseFocusMode(manual: true)
            }
        )

        let hosting = NSHostingController(rootView: content)
        let target = expandedTargetFrame()
        hosting.view.frame = NSRect(origin: .zero, size: target.size)

        let createdPanel = FocusModePanel(
            contentRect: target,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        createdPanel.isReleasedWhenClosed = false
        createdPanel.isOpaque = false
        createdPanel.backgroundColor = .clear
        createdPanel.hasShadow = false
        createdPanel.level = .statusBar
        createdPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        createdPanel.contentViewController = hosting
        createdPanel.alphaValue = 0
        createdPanel.orderOut(nil)

        expandedHostingController = hosting
        expandedPanel = createdPanel
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        isVisible = false
    }

    private func closeExpandedPanel() {
        stopExpandedKeyMonitor()
        expandedPanel?.orderOut(nil)
        expandedPanel = nil
        expandedHostingController = nil
        isExpanded = false
    }

    private func startHoverPolling() {
        hoverPollingTimer?.invalidate()
        hoverPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.hoverTick()
            }
        }
        if let hoverPollingTimer {
            RunLoop.main.add(hoverPollingTimer, forMode: .common)
        }
    }

    private func hoverTick() {
        guard shouldManagePanel else {
            closePanel()
            closeExpandedPanel()
            return
        }

        if isExpanded {
            repositionExpandedPanel()
            return
        }

        ensurePanel()
        repositionPanel()
        updateVisibility()
    }

    private func forceReveal() {
        forceVisibleUntil = Date().addingTimeInterval(2.5)
    }

    private func updateVisibility() {
        guard let panel else { return }

        if isExpanded {
            panel.orderOut(nil)
            isVisible = false
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let revealRect = panel.frame.insetBy(dx: -130, dy: -40)
        let shouldShow = revealRect.contains(mouseLocation) || Date() < forceVisibleUntil

        guard shouldShow != isVisible else { return }
        isVisible = shouldShow

        if shouldShow {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 0
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak panel] in
                guard let self, let panel else { return }
                if !self.isVisible {
                    panel.orderOut(nil)
                }
            }
        }
    }

    private func handlePhaseChange(_ phase: PomodoroPhase) {
        let previous = lastObservedPhase
        lastObservedPhase = phase

        switch (previous, phase) {
        case (.focus, .breakTime):
            if keepExpandedCycle {
                pendingReexpandAfterBreak = true
            }
            if isExpanded {
                collapseFocusMode(manual: false)
            }
        case (.breakTime, .focus):
            if keepExpandedCycle && pendingReexpandAfterBreak {
                pendingReexpandAfterBreak = false
                expandFocusMode(manual: false)
            }
        case (_, .idle):
            pendingReexpandAfterBreak = false
            keepExpandedCycle = false
            if isExpanded {
                collapseFocusMode(manual: false)
            }
        default:
            break
        }
    }

    private func expandFocusMode(manual: Bool) {
        guard shouldManagePanel, let timer = pomodoroTimer else { return }

        if manual {
            keepExpandedCycle = true
            pendingReexpandAfterBreak = false
        }

        ensurePanel()
        ensureExpandedPanel(timer: timer)
        guard let expandedPanel else { return }

        if isExpanded {
            NSApp.activate(ignoringOtherApps: true)
            expandedPanel.makeKeyAndOrderFront(nil)
            return
        }

        isExpanded = true
        forceReveal()

        let fallbackSize = NSSize(width: 240, height: 92)
        let fromFrame = panel?.frame ?? targetFrame(for: fallbackSize)
        let toFrame = expandedTargetFrame()

        expandedPanel.setFrame(fromFrame, display: false)
        expandedPanel.alphaValue = 0
        expandedPanel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        expandedPanel.makeKeyAndOrderFront(nil)
        startExpandedKeyMonitor()

        panel?.orderOut(nil)
        isVisible = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            expandedPanel.animator().setFrame(toFrame, display: true)
            expandedPanel.animator().alphaValue = 1
        }
    }

    private func collapseFocusMode(manual: Bool, immediate: Bool = false) {
        guard let expandedPanel else { return }

        if manual {
            keepExpandedCycle = false
            pendingReexpandAfterBreak = false
        }

        stopExpandedKeyMonitor()
        isExpanded = false

        guard shouldManagePanel else {
            closeExpandedPanel()
            return
        }

        ensurePanel()
        repositionPanel()
        forceReveal()

        let fallbackSize = NSSize(width: 240, height: 92)
        let destination = panel?.frame ?? targetFrame(for: fallbackSize)

        if immediate {
            expandedPanel.orderOut(nil)
            updateVisibility()
            return
        }

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        isVisible = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            expandedPanel.animator().setFrame(destination, display: true)
            expandedPanel.animator().alphaValue = 0
            panel?.animator().alphaValue = 1
        }, completionHandler: { [weak self, weak expandedPanel] in
            guard let self, let expandedPanel else { return }
            expandedPanel.orderOut(nil)
            DispatchQueue.main.async {
                self.updateVisibility()
            }
        })
    }

    private func startExpandedKeyMonitor() {
        stopExpandedKeyMonitor()
        expandedKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.collapseFocusMode(manual: true)
                return nil
            }
            return event
        }
    }

    private func stopExpandedKeyMonitor() {
        if let expandedKeyMonitor {
            NSEvent.removeMonitor(expandedKeyMonitor)
        }
        expandedKeyMonitor = nil
    }

    private func repositionPanel() {
        guard let panel else { return }
        let size = panel.frame.size
        panel.setFrame(targetFrame(for: size), display: false)
    }

    private func repositionExpandedPanel() {
        guard isExpanded, let expandedPanel else { return }
        expandedPanel.setFrame(expandedTargetFrame(), display: false)
    }

    private func targetFrame(for size: NSSize) -> NSRect {
        guard let screen = currentTargetScreen() else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let x = round(frame.midX - size.width / 2)
        let y = round(visible.maxY - size.height - 6)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func expandedTargetFrame() -> NSRect {
        guard let screen = expandedTargetScreen() else {
            return NSRect(x: 0, y: 0, width: 900, height: 600)
        }
        return screen.frame
    }

    private func expandedTargetScreen() -> NSScreen? {
        panel?.screen ?? currentTargetScreen() ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func currentTargetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}

private final class FocusModePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct PomodoroMenuBarTimerView: View {
    @ObservedObject var timer: PomodoroTimer
    let onStart: () -> Void
    let onStop: () -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .center, spacing: 2) {
                    Text(timer.phaseTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timer.formattedClockTime)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .frame(width: 118)

                Divider()
                    .frame(height: 24)

                HStack(spacing: 6) {
                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 10, height: 10)
                    }
                    .disabled(timer.isRunning)

                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 10, height: 10)
                    }
                    .disabled(!timer.isRunning)
                }
                .buttonStyle(GlassIconButtonStyle())
                .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            )

            Button(action: onExpand) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(GlassChevronButtonStyle())
            .padding(.top, 6)
        }
        .frame(width: 240)
    }
}

private struct PomodoroExpandedTimerView: View {
    @ObservedObject var timer: PomodoroTimer
    let onCollapse: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.96)
                .ignoresSafeArea()
            Text(timer.formattedClockTime)
                .font(.system(size: 136, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.horizontal, 120)

            VStack {
                HoverCloseButton(action: onCollapse)
                    .padding(.top, 14)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.6))
            .frame(width: 24, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(configuration.isPressed ? 0.7 : 0.56))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GlassChevronButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.6))
            .frame(width: 18, height: 18)
            .background(
                Circle()
                    .fill(.ultraThinMaterial.opacity(configuration.isPressed ? 0.7 : 0.56))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct HoverCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isHovering ? 1.0 : 0.2))
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.10 : 0.02))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}
