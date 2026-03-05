import AppKit
import ApplicationServices

@MainActor
public final class FocusMonitor {
    public var onFocusChange: ((FocusContext) -> Void)?
    public var onFocusLost: (() -> Void)?

    private let windowQuery: WindowServerQuery
    private var timer: Timer?
    private var axObserver: AXObserver?
    private var axAppElement: AXUIElement?
    private var currentPID: pid_t?
    private var currentWindowID: CGWindowID?
    private var currentScreenID: CGDirectDisplayID?
    private var currentBundleID: String?
    private var currentIsFullscreen: Bool = false
    private var hadFocusedWindow: Bool = false

    public init(windowQuery: WindowServerQuery) {
        self.windowQuery = windowQuery
    }

    public func start() {
        ensureAccessibilityPrompt()
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(
            self,
            selector: #selector(handleFrontAppChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        ws.addObserver(
            self,
            selector: #selector(handleFrontAppChange),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
        attachObserverForFrontApp()
        scheduleTimer()
        pollFocusedWindow()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        detachAXObserver()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleFrontAppChange() {
        attachObserverForFrontApp()
        pollFocusedWindow()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.pollFocusedWindow()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func pollFocusedWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let focusedWindow = windowQuery.focusedWindowInfo(for: app.processIdentifier)
        let displayID = focusedWindow.flatMap { windowQuery.displayID(containing: $0.bounds) }
        let bundleID = app.bundleIdentifier
        let isFullscreen = windowQuery.isWindowFullscreen(for: app.processIdentifier)
        if focusedWindow == nil && hadFocusedWindow {
            hadFocusedWindow = false
            onFocusLost?()
            return
        }

        hadFocusedWindow = (focusedWindow != nil)

        let hasChanged =
            currentPID != app.processIdentifier ||
            currentWindowID != focusedWindow?.id ||
            currentScreenID != displayID ||
            currentBundleID != bundleID ||
            currentIsFullscreen != isFullscreen

        guard hasChanged else { return }

        currentPID = app.processIdentifier
        currentWindowID = focusedWindow?.id
        currentScreenID = displayID
        currentBundleID = bundleID
        currentIsFullscreen = isFullscreen

        let context = FocusContext(
            appPID: app.processIdentifier,
            bundleID: bundleID,
            focusedWindowID: focusedWindow?.id,
            focusedScreenID: displayID,
            isFullscreen: isFullscreen,
            windowFrame: focusedWindow?.bounds
        )
        onFocusChange?(context)
    }

    private func attachObserverForFrontApp() {
        detachAXObserver()
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var createdObserver: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, axCallback, &createdObserver)
        guard result == .success, let createdObserver else { return }

        axObserver = createdObserver
        axAppElement = appElement

        let notifications: [CFString] = [
            kAXFocusedWindowChangedNotification as CFString,
            kAXMainWindowChangedNotification as CFString,
            kAXMovedNotification as CFString,
            kAXResizedNotification as CFString,
            kAXWindowMiniaturizedNotification as CFString,
            kAXWindowDeminiaturizedNotification as CFString
        ]

        for notification in notifications {
            AXObserverAddNotification(createdObserver, appElement, notification, Unmanaged.passUnretained(self).toOpaque())
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(createdObserver), .commonModes)
    }

    private func detachAXObserver() {
        guard let axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        self.axObserver = nil
        self.axAppElement = nil
    }

    nonisolated private let axCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let monitor = Unmanaged<FocusMonitor>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            monitor.pollFocusedWindow()
        }
    }

    private func ensureAccessibilityPrompt() {
        _ = AXIsProcessTrusted()
    }
}
