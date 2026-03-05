import AppKit
import Combine
import FocusCore
import FocusSystem
import FocusUI
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let permissionManager = PermissionManager.shared
    private let query = WindowServerQuery()
    private var focusMonitor: FocusMonitor?
    private var overlayCoordinator: OverlayCoordinator?
    private var statusBarController: StatusBarController?
    private var permissionWindowController: PermissionWindowController?
    private var pomodoroTimer: PomodoroTimer?
    private var keyMonitor: Any?
    private var idleTimer: Timer?
    private var isCurrentlyIdle = false
    private var cancellables = Set<AnyCancellable>()
    private var lastFocusedWindowID: CGWindowID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController(settings: settings)

        let shouldShowOnboarding = permissionManager.shouldShowOnboardingOnLaunch()
        if shouldShowOnboarding {
            permissionManager.markOnboardingShown()
            showPermissionOnboardingAndStart()
        } else {
            startCoreServicesIfPossible()
        }

        registerAutomationNotifications()
        applyLaunchArguments()
        observeLaunchAtLogin()
        observeShortcutChanges()
    }

    private func showPermissionOnboardingAndStart() {
        let controller = PermissionWindowController()
        permissionWindowController = controller
        controller.show(
            permissionManager: permissionManager,
            onRestart: { [weak self] in
                guard let self else { return }
                self.permissionWindowController?.close()
                self.restartApplication()
            },
            onLater: { [weak self] in
                guard let self else { return }
                self.permissionWindowController?.close()
                self.startCoreServicesIfPossible()
            }
        )
    }

    private func startCoreServicesIfPossible() {
        if !permissionManager.missingPermissions().isEmpty {
            permissionManager.requestMissingPermissions()
            permissionManager.openSystemSettingsForFirstMissing()
            return
        }

        if focusMonitor != nil, overlayCoordinator != nil { return }

        overlayCoordinator = OverlayCoordinator(settings: settings)
        let monitor = FocusMonitor(windowQuery: query)
        monitor.onFocusChange = { [weak self] context in
            guard let self else { return }
            self.lastFocusedWindowID = context.focusedWindowID
            self.overlayCoordinator?.updateFocus(context)
        }
        monitor.onFocusLost = { [weak self] in
            self?.overlayCoordinator?.handleNoFocusedWindow()
        }
        monitor.start()
        focusMonitor = monitor

        let pomodoro = PomodoroTimer(settings: settings)
        pomodoro.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            self.overlayCoordinator?.setPomodoroPhase(phase)
            if phase == .focus && !self.settings.isEnabled {
                self.settings.isEnabled = true
            }
        }
        pomodoroTimer = pomodoro
        statusBarController?.pomodoroTimer = pomodoro

        registerGlobalHotkeys()
        startIdleMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusMonitor?.stop()
        idleTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }


    private func registerGlobalHotkeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            self.handleGlobalKey(event)
        }
    }

    private func handleGlobalKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        let incShortcut = settings.shortcutIncrease
        let decShortcut = settings.shortcutDecrease
        let togShortcut = settings.shortcutToggle

        if keyCode == incShortcut.keyCode && mods.rawValue == incShortcut.modifierFlags.rawValue {
            settings.increaseDim()
        } else if keyCode == decShortcut.keyCode && mods.rawValue == decShortcut.modifierFlags.rawValue {
            settings.decreaseDim()
        } else if keyCode == togShortcut.keyCode && mods.rawValue == togShortcut.modifierFlags.rawValue {
            settings.isEnabled.toggle()
        }
    }

    private func observeShortcutChanges() {
        settings.$shortcutIncrease
            .merge(with: settings.$shortcutDecrease)
            .merge(with: settings.$shortcutToggle)
            .dropFirst(3)
            .sink { [weak self] _ in
                self?.registerGlobalHotkeys()
            }
            .store(in: &cancellables)
    }


    private func startIdleMonitor() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.checkIdleState()
            }
        }
    }

    private func checkIdleState() {
        guard settings.idleDimEnabled else {
            if isCurrentlyIdle {
                isCurrentlyIdle = false
                overlayCoordinator?.setIdleState(false)
            }
            return
        }

        let idle = systemIdleSeconds()
        let shouldBeIdle = idle >= settings.idleTimeout

        if shouldBeIdle != isCurrentlyIdle {
            isCurrentlyIdle = shouldBeIdle
            overlayCoordinator?.setIdleState(shouldBeIdle)
        }
    }

    private func systemIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }


    private func observeLaunchAtLogin() {
        settings.$launchAtLogin
            .dropFirst()
            .sink { [weak self] enabled in self?.updateLaunchAtLogin(enabled) }
            .store(in: &cancellables)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {}
        }
    }


    private func registerAutomationNotifications() {
        let center = DistributedNotificationCenter.default()
        let pairs: [(String, Selector)] = [
            ("enable",  #selector(enableFromAutomation)),
            ("disable", #selector(disableFromAutomation)),
            ("toggle",  #selector(toggleFromAutomation))
        ]
        for (name, sel) in pairs {
            center.addObserver(self, selector: sel, name: Notification.Name("com.dimmerflow.\(name)"), object: nil)
        }
    }

    private func applyLaunchArguments() {
        let args = Set(CommandLine.arguments)
        if args.contains("--enable")  { settings.isEnabled = true }
        if args.contains("--disable") { settings.isEnabled = false }
        if args.contains("--toggle")  { settings.isEnabled.toggle() }
    }

    @objc private func enableFromAutomation()  { settings.isEnabled = true }
    @objc private func disableFromAutomation() { settings.isEnabled = false }
    @objc private func toggleFromAutomation()  { settings.isEnabled.toggle() }

    private func restartApplication() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
