import AppKit
import Combine
import FocusCore
import FocusSystem
import IOKit.ps

@MainActor
public final class OverlayCoordinator {
    private let settings: AppSettings
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var activeDisplayID: CGDirectDisplayID?
    private var activeWindowID: CGWindowID?
    private var activeBundleID: String?
    private var activeIsFullscreen: Bool = false
    private var activeWindowFrame: CGRect?
    private var previousBundleID: String?
    private var isIdle: Bool = false
    private var isPomodoroBreak: Bool = false
    private var isOnBattery: Bool = false
    private var settingsWorkItem: DispatchWorkItem?
    private var scheduleTimer: Timer?
    private var batteryTimer: Timer?

    public init(settings: AppSettings) {
        self.settings = settings
        rebuildWindows()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildWindowsNotification),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        settings.objectWillChange
            .sink { [weak self] _ in self?.debouncedApply() }
            .store(in: &cancellables)

        startScheduleTimer()
        startBatteryMonitor()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    public func updateFocus(_ context: FocusContext) {
        // Track previous app for window close/minimize handling
        if let currentBID = activeBundleID, currentBID != context.bundleID {
            previousBundleID = currentBID
        }

        activeDisplayID = context.focusedScreenID
        activeWindowID = context.focusedWindowID
        activeBundleID = context.bundleID
        activeIsFullscreen = context.isFullscreen
        activeWindowFrame = context.windowFrame
        applyCurrentState()
    }

    /// Called when no focused window is detected (window closed/minimized)
    public func handleNoFocusedWindow() {
        // Switch to previous app if available
        if let prevBID = previousBundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleIdentifier == prevBID && $0.activationPolicy == .regular && !$0.isTerminated
           }) {
            app.activate()
            previousBundleID = nil
        } else {
            // No previous app — go to deactivated (fully dimmed) state
            activeWindowID = nil
            activeBundleID = nil
            activeWindowFrame = nil
            applyCurrentState()
        }
    }

    public func setIdleState(_ idle: Bool) {
        guard isIdle != idle else { return }
        isIdle = idle
        applyCurrentState()
    }

    public func setPomodoroBreak(_ onBreak: Bool) {
        guard isPomodoroBreak != onBreak else { return }
        isPomodoroBreak = onBreak
        applyCurrentState()
    }

    @objc private func rebuildWindowsNotification() { rebuildWindows() }
    @objc private func appearanceDidChange() { applyCurrentState() }

    private func debouncedApply() {
        settingsWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.applyCurrentState() }
        settingsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: item)
    }

    private func rebuildWindows() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            windows[displayID] = OverlayWindow(screen: screen)
        }

        applyCurrentState()
    }

    private func applyCurrentState() {
        // Schedule check: disable dimming outside schedule window
        if settings.scheduleEnabled && !settings.isWithinSchedule {
            windows.values.forEach { $0.orderOut(nil) }
            return
        }

        let shouldBypass = activeBundleID.map { settings.excludedBundleIDs.contains($0) } ?? false

        // Search panel exclusion
        let isSearchPanel = settings.searchPanelExclusion &&
            activeBundleID.map { AppSettings.searchPanelBundleIDs.contains($0) } ?? false

        let enabled = settings.isEnabled && !shouldBypass && !isSearchPanel
        let darkMode = isDarkMode()
        let dur = settings.fadeDuration
        let tintColor = settings.tintNSColor
        let curve = settings.animationCurve

        if settings.fullscreenAwareness && activeIsFullscreen {
            windows.values.forEach { $0.orderOut(nil) }
            return
        }

        // Pomodoro break: disable dimming during breaks if autoDim is on
        let pomodoroDisableDim = isPomodoroBreak && settings.pomodoroEnabled && settings.pomodoroAutoDim

        var effectiveDim: Double
        var effectiveBlur: Double
        var effectiveBlurEnabled: Bool

        if pomodoroDisableDim {
            effectiveDim = 0
            effectiveBlur = 0
            effectiveBlurEnabled = false
        } else if isIdle && settings.idleDimEnabled {
            effectiveDim = settings.idleDimAmount
            effectiveBlur = settings.blurEnabled ? settings.blurAmount : 0
            effectiveBlurEnabled = settings.blurEnabled
        } else if let profile = settings.profile(for: activeBundleID) {
            effectiveDim = profile.dimAmount
            effectiveBlur = profile.blurEnabled ? profile.blurAmount : 0
            effectiveBlurEnabled = profile.blurEnabled
        } else {
            effectiveDim = settings.dimAmount
            effectiveBlur = settings.blurEnabled ? settings.blurAmount : 0
            effectiveBlurEnabled = settings.blurEnabled
        }

        // Battery-aware mode: reduce dim/blur on battery
        if settings.batteryAwareEnabled && isOnBattery && !pomodoroDisableDim {
            effectiveDim *= settings.batteryDimReduction
            if settings.batteryDisableBlur {
                effectiveBlurEnabled = false
                effectiveBlur = 0
            } else {
                effectiveBlur *= settings.batteryDimReduction
            }
        }

        let animDuration = isIdle ? 1.0 : dur

        for (displayID, window) in windows {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { continue }

            window.updateFrame(for: screen, dimMenuBar: settings.dimMenuBar)
            window.level = .normal
            window.setBlurEnabled(effectiveBlurEnabled)
            window.setAppearanceColor(tintColor: tintColor, darkMode: darkMode)

            guard enabled, let activeWindowID else {
                window.orderOut(nil)
                continue
            }

            let isActiveDisplay = (displayID == activeDisplayID)

            if !isActiveDisplay && !settings.dimOtherDisplays {
                window.orderOut(nil)
                continue
            }

            if isActiveDisplay {
                window.order(.below, relativeTo: Int(activeWindowID))
            } else {
                window.orderFrontRegardless()
            }

            window.setDimAmount(CGFloat(effectiveDim), duration: animDuration, curve: curve)
            window.setBlurAmount(
                effectiveBlurEnabled ? CGFloat(effectiveBlur) : 0,
                duration: animDuration,
                curve: curve
            )
        }
    }

    // MARK: - Schedule Timer

    private func startScheduleTimer() {
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.applyCurrentState() }
        }
    }

    // MARK: - Battery Monitor

    private func startBatteryMonitor() {
        checkBatteryState()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkBatteryState() }
        }
    }

    private func checkBatteryState() {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] ?? []

        var onBattery = false
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let state = desc[kIOPSPowerSourceStateKey] as? String {
                if state == kIOPSBatteryPowerValue {
                    onBattery = true
                    break
                }
            }
        }

        if isOnBattery != onBattery {
            isOnBattery = onBattery
            applyCurrentState()
        }
    }

    private func isDarkMode() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
