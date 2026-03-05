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
    private var previousBundleID: String?
    private var isIdle: Bool = false
    private var isPomodoroBreak: Bool = false
    private var isPomodoroRunning: Bool = false
    private var isOnBattery: Bool = false
    private var periodicTimer: Timer?

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
            .sink { [weak self] _ in self?.applyCurrentState() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appSettingsDidChange)
            .sink { [weak self] _ in self?.applyCurrentState() }
            .store(in: &cancellables)

        startPeriodicTimer()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    public func updateFocus(_ context: FocusContext) {
        if let currentBID = activeBundleID, currentBID != context.bundleID {
            previousBundleID = currentBID
        }

        activeDisplayID = context.focusedScreenID
        activeWindowID = context.focusedWindowID
        activeBundleID = context.bundleID
        activeIsFullscreen = context.isFullscreen
        applyCurrentState()
    }

    public func handleNoFocusedWindow() {
        if let prevBID = previousBundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleIdentifier == prevBID && $0.activationPolicy == .regular && !$0.isTerminated
           }) {
            app.activate()
            previousBundleID = nil
        }
        applyCurrentState()
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

    public func setPomodoroPhase(_ phase: PomodoroPhase) {
        let running = phase != .idle
        let onBreak = phase == .breakTime
        guard isPomodoroRunning != running || isPomodoroBreak != onBreak else { return }
        isPomodoroRunning = running
        isPomodoroBreak = onBreak
        applyCurrentState()
    }

    @objc private func rebuildWindowsNotification() { rebuildWindows() }
    @objc private func appearanceDidChange() { applyCurrentState() }

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
        if settings.scheduleEnabled && !settings.isWithinSchedule && !isPomodoroRunning {
            windows.values.forEach { $0.orderOut(nil) }
            return
        }

        let shouldBypass = activeBundleID.map { settings.excludedBundleIDs.contains($0) } ?? false

        let isSearchPanel = settings.searchPanelExclusion &&
            activeBundleID.map { AppSettings.searchPanelBundleIDs.contains($0) } ?? false

        let pomodoroForcesDimming = isPomodoroRunning && !isPomodoroBreak
        let enabled = (settings.isEnabled || pomodoroForcesDimming) && !shouldBypass && !isSearchPanel
        let darkMode = isDarkMode()
        let dur = settings.fadeDuration
        let tintColor = settings.tintNSColor
        let curve = settings.animationCurve

        if settings.fullscreenAwareness && activeIsFullscreen {
            windows.values.forEach { $0.orderOut(nil) }
            return
        }

        let pomodoroDisableDim = isPomodoroBreak && settings.pomodoroEnabled && settings.pomodoroAutoDim

        var effectiveDim: Double
        var effectiveBlur: Double
        var effectiveBlurEnabled: Bool

        if pomodoroDisableDim {
            effectiveDim = 0
            effectiveBlur = 0
            effectiveBlurEnabled = false
        } else if isPomodoroRunning {
            effectiveDim = settings.dimAmount
            effectiveBlur = settings.blurEnabled ? settings.blurAmount : 0
            effectiveBlurEnabled = settings.blurEnabled
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


    private func startPeriodicTimer() {
        checkBatteryState()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.checkBatteryState()
                self.applyCurrentState()
            }
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
