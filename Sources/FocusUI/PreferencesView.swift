import SwiftUI
import FocusCore

public struct PreferencesView: View {
    @ObservedObject private var settings: AppSettings
    @State private var selectedTab: SettingsTab = .general
    @State private var isAppActive: Bool = true

    public init(settings: AppSettings) {
        self.settings = settings
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general    = "General"
        case appearance = "Appearance"
        case profiles   = "Profiles"
        case focus      = "Focus"
        case shortcuts  = "Shortcuts"
        case advanced   = "Advanced"
        case about      = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general:    return "slider.horizontal.3"
            case .appearance: return "paintbrush"
            case .profiles:   return "app.dashed"
            case .focus:      return "timer"
            case .shortcuts:  return "keyboard"
            case .advanced:   return "gearshape.2"
            case .about:      return "info.circle"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case .general:    generalTab
                case .appearance: appearanceTab
                case .profiles:   profilesTab
                case .focus:      focusTab
                case .shortcuts:  shortcutsTab
                case .advanced:   advancedTab
                case .about:      aboutTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 620, height: 520)
        .background(backgroundMaterial)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { isAppActive = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { isAppActive = false }
        }
    }

    @ViewBuilder
    private var backgroundMaterial: some View {
        if isAppActive {
            Color(nsColor: .windowBackgroundColor)
        } else {
            if #available(macOS 14.0, *) {
                Color.clear.background(.ultraThinMaterial)
            } else {
                Color(nsColor: .windowBackgroundColor).opacity(0.85)
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Dimming") {
                Toggle("Enable Dimming", isOn: $settings.isEnabled)

                HStack {
                    Text("Intensity")
                    Slider(value: $settings.dimAmount, in: 0...1)
                    Text("\(Int(settings.dimAmount * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text("Transition")
                    Slider(value: $settings.fadeDuration, in: 0.02...0.6)
                    Text(String(format: "%.2fs", settings.fadeDuration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Picker("Animation Curve", selection: $settings.animationCurve) {
                    ForEach(AnimationCurve.allCases) { curve in
                        Text(curve.rawValue).tag(curve)
                    }
                }
            }

            Section("Blur") {
                Toggle("Enable Blur", isOn: $settings.blurEnabled)

                if settings.blurEnabled {
                    HStack {
                        Text("Blur Amount")
                        Slider(value: $settings.blurAmount, in: 0...1)
                        Text("\(Int(settings.blurAmount * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section("Quick Presets") {
                HStack(spacing: 8) {
                    ForEach(DimPreset.allCases) { preset in
                        Button(action: { settings.applyPreset(preset) }) {
                            VStack(spacing: 4) {
                                Image(systemName: preset.icon)
                                    .font(.title3)
                                Text(preset.rawValue)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.currentPreset == preset
                                          ? Color.accentColor.opacity(0.2)
                                          : Color.secondary.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section("Regions") {
                Toggle("Dim Menu Bar", isOn: $settings.dimMenuBar)
            }

            Section("Tint Color") {
                ColorPicker("Dim Tint", selection: tintBinding, supportsOpacity: false)
                Text("Overlay tint color. Default is black.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if settings.hasMultipleDisplays {
                Section("Multiple Displays") {
                    Toggle("Dim Other Displays", isOn: $settings.dimOtherDisplays)
                    Text("When enabled, non-active displays will be fully dimmed.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Profiles Tab

    @State private var showingAddProfile = false
    @State private var newProfileBundleID = ""
    @State private var newProfileAppName = ""

    private var profilesTab: some View {
        VStack(spacing: 0) {
            if settings.appProfiles.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Per-App Profiles")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Add custom dim and blur levels for specific apps.\nApps without a profile use the global settings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(settings.appProfiles.enumerated()), id: \.element.bundleID) { index, profile in
                        AppProfileRow(profile: Binding(
                            get: { self.settings.appProfiles[index] },
                            set: { self.settings.appProfiles[index] = $0 }
                        ), onDelete: {
                            settings.removeProfile(bundleID: profile.bundleID)
                        })
                    }
                }
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Button(action: addProfileFromRunningApps) {
                    Label("Add from Running Apps", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .font(.callout)

                Spacer()

                Button(action: { showingAddProfile = true }) {
                    Label("Add by Bundle ID", systemImage: "text.badge.plus")
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showingAddProfile) {
            addProfileSheet
        }
    }

    private var addProfileSheet: some View {
        VStack(spacing: 16) {
            Text("Add App Profile")
                .font(.headline)

            TextField("Bundle ID (e.g. com.apple.Terminal)", text: $newProfileBundleID)
                .textFieldStyle(.roundedBorder)

            TextField("App Name (optional)", text: $newProfileAppName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    newProfileBundleID = ""
                    newProfileAppName = ""
                    showingAddProfile = false
                }
                Spacer()
                Button("Add") {
                    let bid = newProfileBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !bid.isEmpty else { return }
                    let name = newProfileAppName.trimmingCharacters(in: .whitespacesAndNewlines)
                    settings.addProfile(AppProfile(
                        bundleID: bid,
                        appName: name.isEmpty ? bid : name,
                        dimAmount: settings.dimAmount,
                        blurAmount: settings.blurAmount,
                        blurEnabled: settings.blurEnabled
                    ))
                    newProfileBundleID = ""
                    newProfileAppName = ""
                    showingAddProfile = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addProfileFromRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let bid = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? bid
                return (bid, name)
            }
            .sorted(by: { $0.1 < $1.1 })

        let menu = NSMenu()
        for (bid, name) in apps {
            let exists = settings.appProfiles.contains(where: { $0.bundleID == bid })
            let item = NSMenuItem(title: "\(name) (\(bid))", action: exists ? nil : #selector(AppProfileMenuTarget.handleAddProfileFromMenu(_:)), keyEquivalent: "")
            item.target = AppProfileMenuTarget.shared
            item.representedObject = (bid, name, settings) as AnyObject
            if exists {
                item.isEnabled = false
                item.title += " ✓"
            }
            menu.addItem(item)
        }

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
        }
    }

    // MARK: - Focus Tab (Pomodoro + Schedule)

    private var focusTab: some View {
        Form {
            Section("Focus Sessions (Pomodoro)") {
                Toggle("Enable Pomodoro Timer", isOn: $settings.pomodoroEnabled)

                if settings.pomodoroEnabled {
                    HStack {
                        Text("Focus Duration")
                        Slider(value: $settings.pomodoroFocusMinutes, in: 5...90, step: 5)
                        Text("\(Int(settings.pomodoroFocusMinutes))m")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    HStack {
                        Text("Break Duration")
                        Slider(value: $settings.pomodoroBreakMinutes, in: 1...30, step: 1)
                        Text("\(Int(settings.pomodoroBreakMinutes))m")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    Toggle("Disable dimming during breaks", isOn: $settings.pomodoroAutoDim)
                    Text("When enabled, overlay is hidden during break periods.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Schedule") {
                Toggle("Enable Schedule", isOn: $settings.scheduleEnabled)

                if settings.scheduleEnabled {
                    HStack {
                        Text("Start")
                        Picker("", selection: $settings.scheduleStartHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        Text(":")
                        Picker("", selection: $settings.scheduleStartMinute) {
                            ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }

                    HStack {
                        Text("End")
                            .frame(width: 31, alignment: .leading)
                        Picker("", selection: $settings.scheduleEndHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        Text(":")
                        Picker("", selection: $settings.scheduleEndMinute) {
                            ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }

                    Text("Dimming will only be active between these times.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Shortcuts Tab

    @State private var recordingShortcut: ShortcutAction? = nil

    enum ShortcutAction: Equatable {
        case increase, decrease, toggle
    }

    private var shortcutsTab: some View {
        Form {
            Section("Keyboard Shortcuts") {
                Text("Click a shortcut to record a new key combination.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                shortcutRow(label: "Increase Dim", shortcut: settings.shortcutIncrease, action: .increase)
                shortcutRow(label: "Decrease Dim", shortcut: settings.shortcutDecrease, action: .decrease)
                shortcutRow(label: "Toggle Dimming", shortcut: settings.shortcutToggle, action: .toggle)
            }

            Section("Reset") {
                Button("Reset to Defaults") {
                    settings.shortcutIncrease = .defaultIncrease
                    settings.shortcutDecrease = .defaultDecrease
                    settings.shortcutToggle = .defaultToggle
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func shortcutRow(label: String, shortcut: KeyShortcut, action: ShortcutAction) -> some View {
        HStack {
            Text(label)
            Spacer()
            ShortcutRecorderButton(
                shortcut: shortcut,
                isRecording: recordingShortcut.map { $0 == action } == true,
                onStartRecording: { recordingShortcut = action },
                onRecorded: { newShortcut in
                    switch action {
                    case .increase: settings.shortcutIncrease = newShortcut
                    case .decrease: settings.shortcutDecrease = newShortcut
                    case .toggle:   settings.shortcutToggle = newShortcut
                    }
                    recordingShortcut = nil
                }
            )
        }
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            Section("System") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Fullscreen Awareness", isOn: $settings.fullscreenAwareness)
                Text("Hides overlay when the active app is in fullscreen.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Battery-Aware Mode") {
                Toggle("Enable Battery-Aware Mode", isOn: $settings.batteryAwareEnabled)

                if settings.batteryAwareEnabled {
                    HStack {
                        Text("Dim Reduction")
                        Slider(value: $settings.batteryDimReduction, in: 0.1...1)
                        Text("\(Int(settings.batteryDimReduction * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    Toggle("Disable Blur on Battery", isOn: $settings.batteryDisableBlur)
                    Text("Reduces dim intensity and optionally disables blur when running on battery to save energy.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Inactivity Auto-Dim") {
                Toggle("Dim After Inactivity", isOn: $settings.idleDimEnabled)

                if settings.idleDimEnabled {
                    HStack {
                        Text("Timeout")
                        Slider(value: $settings.idleTimeout, in: 30...600, step: 30)
                        Text(idleTimeoutLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }

                    HStack {
                        Text("Dim Intensity")
                        Slider(value: $settings.idleDimAmount, in: 0.3...1)
                        Text("\(Int(settings.idleDimAmount * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    Text("Increases dimming when you haven't interacted with the computer for the specified duration.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Excluded Apps") {
                TextField("Bundle IDs (comma separated)", text: $settings.excludedBundleIDsRaw)
                    .textFieldStyle(.roundedBorder)
                Text("e.g. com.apple.Spotlight, com.raycast.macos")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Search Panel Exclusion") {
                Toggle("Auto-pause for search panels", isOn: $settings.searchPanelExclusion)
                Text("Automatically pauses dimming when Spotlight, Raycast, or Alfred is active.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundStyle(.primary)

            Text("DimmerFlow")
                .font(.title.bold())

            Text("Version 1.0")
                .foregroundStyle(.secondary)

            Text("A lightweight focus dimmer for macOS.\nDims everything except your active window.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Divider()
                .frame(width: 200)

            Link("Okan Doğu BUDAK", destination: URL(string: "https://github.com/okandobudak")!)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bindings

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(red: settings.tintR, green: settings.tintG, blue: settings.tintB) },
            set: { newColor in
                if let ns = NSColor(newColor).usingColorSpace(.sRGB) {
                    settings.tintR = Double(ns.redComponent)
                    settings.tintG = Double(ns.greenComponent)
                    settings.tintB = Double(ns.blueComponent)
                }
            }
        )
    }

    private var idleTimeoutLabel: String {
        let mins = Int(settings.idleTimeout) / 60
        let secs = Int(settings.idleTimeout) % 60
        if mins > 0 && secs > 0 { return "\(mins)m \(secs)s" }
        if mins > 0 { return "\(mins)m" }
        return "\(secs)s"
    }
}

// MARK: - Shortcut Recorder

private struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: KeyShortcut
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onRecorded: (KeyShortcut) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: shortcut.displayString, target: context.coordinator, action: #selector(Coordinator.buttonClicked))
        button.bezelStyle = .recessed
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = isRecording ? "Press keys..." : shortcut.displayString
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor class Coordinator: NSObject {
        var parent: ShortcutRecorderButton
        nonisolated(unsafe) var keyMonitor: Any?

        init(parent: ShortcutRecorderButton) {
            self.parent = parent
        }

        @objc func buttonClicked() {
            if parent.isRecording {
                stopRecording()
            } else {
                parent.onStartRecording()
                startRecording()
            }
        }

        func startRecording() {
            stopRecording()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // Require at least one modifier key
                guard !mods.isEmpty else {
                    if event.keyCode == 53 { // Escape cancels
                        DispatchQueue.main.async { self.parent.onRecorded(self.parent.shortcut) }
                        self.stopRecording()
                        return nil
                    }
                    return event
                }
                let newShortcut = KeyShortcut(keyCode: event.keyCode, modifiers: mods.rawValue)
                DispatchQueue.main.async { self.parent.onRecorded(newShortcut) }
                self.stopRecording()
                return nil
            }
        }

        func stopRecording() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }
    }
}

// MARK: - App Profile Row

private struct AppProfileRow: View {
    @Binding var profile: AppProfile
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let icon = appIcon(for: profile.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.appName.isEmpty ? profile.bundleID : profile.appName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(profile.bundleID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Dim")
                    .font(.caption)
                    .frame(width: 30, alignment: .leading)
                Slider(value: $profile.dimAmount, in: 0.05...1)
                    .controlSize(.small)
                Text("\(Int(profile.dimAmount * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            HStack {
                Toggle("", isOn: $profile.blurEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                Text("Blur")
                    .font(.caption)
                if profile.blurEnabled {
                    Slider(value: $profile.blurAmount, in: 0...1)
                        .controlSize(.small)
                    Text("\(Int(profile.blurAmount * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Menu target helper

@MainActor
private final class AppProfileMenuTarget: NSObject {
    static let shared = AppProfileMenuTarget()

    @objc func handleAddProfileFromMenu(_ sender: NSMenuItem) {
        guard let tuple = sender.representedObject as? (String, String, AppSettings) else { return }
        let (bid, name, settings) = (tuple.0, tuple.1, tuple.2)
        settings.addProfile(AppProfile(
            bundleID: bid,
            appName: name,
            dimAmount: settings.dimAmount,
            blurAmount: settings.blurAmount,
            blurEnabled: settings.blurEnabled
        ))
    }
}
