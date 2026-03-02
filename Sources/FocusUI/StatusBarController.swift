import AppKit
import Combine
import SwiftUI
import FocusCore

@MainActor
public final class StatusBarController: NSObject {
    private let settings: AppSettings
    private let statusItem: NSStatusItem
    private var popoverPanel: NSPanel?
    private var preferencesWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    public var pomodoroTimer: PomodoroTimer?

    public init(settings: AppSettings) {
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupStatusItem()

        cancellable = settings.$isEnabled
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateIcon() }
            }
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        updateIcon()
    }

    private func updateIcon() {
        let name = settings.isEnabled ? "circle.lefthalf.filled" : "circle.dashed"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "DimmerFlow")
    }

    @objc private func togglePopover() {
        if let panel = popoverPanel, panel.isVisible {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let content = MenuPopoverView(
            settings: settings,
            pomodoroTimer: pomodoroTimer,
            onSettings: { [weak self] in
                self?.closePopover()
                self?.openPreferences()
            },
            onQuit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: content)
        hostingController.view.frame.size = hostingController.view.fittingSize

        let panelSize = hostingController.view.fittingSize
        let panelX = screenRect.midX - panelSize.width / 2
        let panelY = screenRect.minY - panelSize.height - 4

        let panel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelSize.width, height: panelSize.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.level = .statusBar
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentViewController = hostingController
        panel.isMovable = false

        panel.orderFrontRegardless()
        popoverPanel = panel
        startEventMonitor()
    }

    private func closePopover() {
        popoverPanel?.orderOut(nil)
        popoverPanel = nil
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    private func openPreferences() {
        if preferencesWindow == nil {
            let root = PreferencesView(settings: settings)
            let hosting = NSHostingController(rootView: root)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.title = "DimmerFlow Settings"
            window.center()
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            preferencesWindow = window
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Menu Bar Popover

private struct MenuPopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var pomodoroTimer: PomodoroTimer
    let onSettings: () -> Void
    let onQuit: () -> Void

    init(settings: AppSettings, pomodoroTimer: PomodoroTimer?, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.settings = settings
        self.pomodoroTimer = pomodoroTimer ?? PomodoroTimer(settings: settings)
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // App Title
            Text("Dimmer Flow")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(.primary)

            // Quick Preset Switcher
            HStack(spacing: 6) {
                ForEach(DimPreset.allCases) { preset in
                    Button(action: { settings.applyPreset(preset) }) {
                        VStack(spacing: 4) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 15))
                            Text(preset.rawValue)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.currentPreset == preset
                                      ? Color.accentColor.opacity(0.2)
                                      : Color.secondary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Dim Toggle + Slider
            HStack(spacing: 8) {
                Toggle("", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text("Dimming")
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(settings.dimAmount * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            if settings.isEnabled {
                Slider(value: $settings.dimAmount, in: 0.05...1)
                    .controlSize(.small)
            }

            Divider()

            // Blur Toggle + Slider
            HStack(spacing: 8) {
                Toggle("", isOn: $settings.blurEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text("Blur")
                    .fontWeight(.medium)
                Spacer()
                if settings.blurEnabled {
                    Text("\(Int(settings.blurAmount * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            if settings.blurEnabled {
                Slider(value: $settings.blurAmount, in: 0...1)
                    .controlSize(.small)
            }

            // Pomodoro Section
            if settings.pomodoroEnabled {
                Divider()

                HStack(spacing: 8) {
                    Image(systemName: pomodoroTimer.phase == .breakTime ? "cup.and.saucer.fill" : "timer")
                        .foregroundStyle(pomodoroTimer.phase == .focus ? .red : pomodoroTimer.phase == .breakTime ? .green : .secondary)

                    if pomodoroTimer.isRunning {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pomodoroTimer.phase == .focus ? "Focus" : "Break")
                                .font(.caption.bold())
                            Text(pomodoroTimer.formattedTime)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Pomodoro")
                            .font(.caption.bold())
                    }

                    Spacer()

                    if pomodoroTimer.isRunning {
                        Button(action: { pomodoroTimer.stop() }) {
                            Image(systemName: "stop.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { pomodoroTimer.startFocus() }) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }

                    if pomodoroTimer.completedSessions > 0 {
                        Text("\(pomodoroTimer.completedSessions)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(.secondary.opacity(0.15)))
                    }
                }
            }

            Divider()

            HStack {
                Button(action: onSettings) {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onQuit) {
                    Text("Quit")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
