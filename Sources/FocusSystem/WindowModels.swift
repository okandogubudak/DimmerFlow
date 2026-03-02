import AppKit

public struct FocusContext: Sendable, Equatable {
    public let appPID: pid_t
    public let bundleID: String?
    public let focusedWindowID: CGWindowID?
    public let focusedScreenID: CGDirectDisplayID?
    public let isFullscreen: Bool
    public let windowFrame: CGRect?

    public init(
        appPID: pid_t,
        bundleID: String?,
        focusedWindowID: CGWindowID?,
        focusedScreenID: CGDirectDisplayID?,
        isFullscreen: Bool = false,
        windowFrame: CGRect? = nil
    ) {
        self.appPID = appPID
        self.bundleID = bundleID
        self.focusedWindowID = focusedWindowID
        self.focusedScreenID = focusedScreenID
        self.isFullscreen = isFullscreen
        self.windowFrame = windowFrame
    }
}

public struct WindowInfo {
    public let id: CGWindowID
    public let ownerPID: pid_t
    public let bounds: CGRect
    public let layer: Int
}