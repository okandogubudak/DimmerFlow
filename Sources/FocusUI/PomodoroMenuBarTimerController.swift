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
    private var settingsCancellables = Set<AnyCancellable>()
    private var timerCancellables = Set<AnyCancellable>()
    private var isVisible = false
    private var forceVisibleUntil: Date = .distantPast

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
            }
            .store(in: &settingsCancellables)

        startHoverPolling()
    }

    func setPomodoroTimer(_ timer: PomodoroTimer?) {
        pomodoroTimer = timer
        timerCancellables.removeAll()

        timer?.$remainingSeconds
            .sink { [weak self] _ in
                self?.repositionPanel()
            }
            .store(in: &timerCancellables)

        timer?.$phase
            .sink { [weak self] _ in
                self?.forceReveal()
                self?.refreshPanelState()
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
            onStart: { [weak self] in
                guard let self, let timer = self.pomodoroTimer else { return }
                timer.startFocus()
                self.forceReveal()
            },
            onStop: { [weak self] in
                guard let self, let timer = self.pomodoroTimer else { return }
                timer.stop()
                self.forceReveal()
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
        createdPanel.hasShadow = true
        createdPanel.level = .statusBar
        createdPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let glassView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glassView.material = .hudWindow
        glassView.blendingMode = .withinWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 12
        glassView.layer?.masksToBounds = true

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        glassView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: glassView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
        ])

        createdPanel.contentView = glassView
        createdPanel.alphaValue = 0
        createdPanel.orderOut(nil)

        hostingController = hosting
        panel = createdPanel
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        isVisible = false
    }

    private func startHoverPolling() {
        hoverPollingTimer?.invalidate()
        hoverPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.hoverTick()
            }
        }
        if let hoverPollingTimer {
            RunLoop.main.add(hoverPollingTimer, forMode: .common)
        }
    }

    private func stopHoverPolling() {
        hoverPollingTimer?.invalidate()
        hoverPollingTimer = nil
    }

    private func hoverTick() {
        guard shouldManagePanel else {
            closePanel()
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
                Task { @MainActor in
                    guard let self, let panel else { return }
                    if !self.isVisible {
                        panel.orderOut(nil)
                    }
                }
            }
        }
    }

    private func repositionPanel() {
        guard let panel else { return }
        let size = panel.frame.size
        panel.setFrame(targetFrame(for: size), display: false)
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

    private func currentTargetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}

private struct PomodoroMenuBarTimerView: View {
    @ObservedObject var timer: PomodoroTimer
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
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
        .padding(.vertical, 8)
        .frame(width: 240)
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
