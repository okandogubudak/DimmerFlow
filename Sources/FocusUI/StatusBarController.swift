import AppKit
import Combine
import SwiftUI
import FocusCore

@MainActor
public final class StatusBarController: NSObject {
    private let settings: AppSettings
    private let statusItem: NSStatusItem
    private let pomodoroMenuBarTimerController: PomodoroMenuBarTimerController
    private var popoverPanel: NSPanel?
    private var preferencesWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    public var pomodoroTimer: PomodoroTimer? {
        didSet {
            pomodoroMenuBarTimerController.setPomodoroTimer(pomodoroTimer)
        }
    }

    public init(settings: AppSettings) {
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.pomodoroMenuBarTimerController = PomodoroMenuBarTimerController(settings: settings)
        super.init()
        setupStatusItem()

        cancellable = settings.$isEnabled
            .combineLatest(settings.$dimAmount)
            .sink { [weak self] _, _ in
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
        let level = iconFillLevel()
        let image = drawMenuBarIcon(fillLevel: level)
        image.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.alphaValue = 1.0
        statusItem.button?.imagePosition = .imageOnly
    }

    private func iconFillLevel() -> CGFloat {
        guard settings.isEnabled else { return 0 }
        let percent = Int((max(0, min(1, settings.dimAmount)) * 100).rounded(.down))
        if percent <= 0 { return 0 }
        if percent <= 24 { return 0.25 }
        if percent <= 49 { return 0.5 }
        if percent <= 74 { return 0.75 }
        return 1.0
    }

    private func drawMenuBarIcon(fillLevel: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let inset: CGFloat = 2.3
        let rect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        if fillLevel > 0 {
            let fillPath = NSBezierPath()
            fillPath.move(to: center)
            fillPath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - (360 * fillLevel), clockwise: true)
            fillPath.close()
            NSColor.labelColor.setFill()
            fillPath.fill()
        }

        let strokePath = NSBezierPath(ovalIn: rect)
        strokePath.lineWidth = 1.3
        NSColor.labelColor.setStroke()
        strokePath.stroke()

        image.unlockFocus()
        return image
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
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.contentViewController = hostingController
        panel.isMovable = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

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
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )

            window.title = "DimmerFlow Preferences"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            preferencesWindow = window
        }

        if let window = preferencesWindow {
            centerWindowOnActiveScreen(window)
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerWindowOnActiveScreen(_ window: NSWindow) {
        let targetScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else {
            window.center()
            return
        }

        let frameBounds = screen.frame
        let frame = window.frame
        let origin = NSPoint(
            x: frameBounds.midX - frame.width / 2,
            y: frameBounds.midY - frame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

private struct MenuPopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var pomodoroTimer: PomodoroTimer
    @State private var isAdjustingSlider = false
    let onSettings: () -> Void
    let onQuit: () -> Void

    init(settings: AppSettings, pomodoroTimer: PomodoroTimer?, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.settings = settings
        self.pomodoroTimer = pomodoroTimer ?? PomodoroTimer(settings: settings)
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    var body: some View {
        let selectedPreset: DimPreset? = isAdjustingSlider ? nil : settings.currentPreset
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                )

            VStack(alignment: .leading, spacing: 10) {
                Text("DimmerFlow")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.primary)

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
                        }
                        .buttonStyle(GlassPresetButtonStyle(isSelected: selectedPreset == preset))
                    }
                }

                glassDivider

                HStack(spacing: 8) {
                    Text("Intensity")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(settings.dimAmount * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                GlassSlider(
                    value: dimSliderBinding,
                    range: 0...1,
                    onEditingChanged: { isAdjustingSlider = $0 }
                )

                glassDivider

                HStack(spacing: 8) {
                    Text("Blur")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(settings.blurAmount * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                GlassSlider(
                    value: blurSliderBinding,
                    range: 0...1,
                    onEditingChanged: { isAdjustingSlider = $0 }
                )

                if settings.pomodoroEnabled {
                    glassDivider

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pomodoroTimer.phaseTitle)
                                .font(.caption.bold())
                            Text(pomodoroTimer.formattedClockTime)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 92, alignment: .leading)

                        Spacer()

                        HStack(spacing: 6) {
                            Button(action: { pomodoroTimer.startFocus() }) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 10, height: 10)
                            }
                            .buttonStyle(GlassIconButtonStyle())
                            .disabled(pomodoroTimer.isRunning)

                            Button(action: { pomodoroTimer.stop() }) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 10, height: 10)
                            }
                            .buttonStyle(GlassIconButtonStyle())
                            .disabled(!pomodoroTimer.isRunning)
                        }
                        .frame(width: 56, alignment: .trailing)
                    }
                }

                glassDivider

                HStack(spacing: 8) {
                    Button(action: onSettings) {
                        Label("Preferences", systemImage: "gear")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(GlassTextButtonStyle())

                    Button(action: onQuit) {
                        Text("Quit")
                            .frame(width: 56)
                    }
                    .buttonStyle(GlassTextButtonStyle())
                }
                .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 260)
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 0.5)
    }

    private var dimSliderBinding: Binding<Double> {
        Binding(
            get: { settings.dimAmount },
            set: { newValue in
                if newValue > 0.001, !settings.isEnabled {
                    settings.isEnabled = true
                }
                settings.dimAmount = newValue
                if newValue <= 0.001 {
                    settings.isEnabled = false
                }
            }
        )
    }

    private var blurSliderBinding: Binding<Double> {
        Binding(
            get: { settings.blurAmount },
            set: { newValue in
                settings.blurAmount = newValue
                settings.blurEnabled = newValue > 0.001
            }
        )
    }
}

private struct GlassPresetButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(isSelected ? 0.82 : 0.56))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.34) : Color.white.opacity(0.22), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GlassTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(configuration.isPressed ? 0.68 : 0.54))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: ((Bool) -> Void)? = nil

    var body: some View {
        Slider(value: $value, in: range, onEditingChanged: { editing in
            onEditingChanged?(editing)
        })
            .tint(Color.white.opacity(0.9))
            .controlSize(.small)
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
                    .fill(.ultraThinMaterial.opacity(configuration.isPressed ? 0.68 : 0.54))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
