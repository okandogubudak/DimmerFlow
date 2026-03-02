import AppKit
import ApplicationServices

public final class WindowServerQuery {
    private var cachedWindowID: CGWindowID?
    private var cachedPID: pid_t?

    public init() {}

    public func focusedWindowInfo(for pid: pid_t) -> WindowInfo? {
        let axBounds = focusedWindowBoundsAX(for: pid)
        let candidateWindows = windows(for: pid)
        guard !candidateWindows.isEmpty else { return nil }

        guard let axBounds else {
            return candidateWindows.first
        }

        let convertedAXBounds = convertAXRectToCocoaIfNeeded(axBounds)

        let match = candidateWindows.min { lhs, rhs in
            rectDistance(lhs.bounds, convertedAXBounds) < rectDistance(rhs.bounds, convertedAXBounds)
        }

        guard let match else { return candidateWindows.first }
        return WindowInfo(id: match.id, ownerPID: match.ownerPID, bounds: match.bounds, layer: match.layer)
    }

    public func focusedWindowBoundsAX(for pid: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )
        guard focusedResult == .success, let focusedWindow = focusedWindowRef else {
            return nil
        }

        let windowElement = focusedWindow as! AXUIElement

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXPositionAttribute as CFString,
            &positionRef
        )
        let sizeResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXSizeAttribute as CFString,
            &sizeRef
        )

        guard
            posResult == .success,
            sizeResult == .success,
            let positionRef,
            let sizeRef
        else {
            return nil
        }

        guard CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        let posValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        let gotPosition = AXValueGetValue(posValue, .cgPoint, &position)
        let gotSize = AXValueGetValue(sizeValue, .cgSize, &size)

        guard gotPosition, gotSize, size.width > 0, size.height > 0 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    public func isWindowFullscreen(for pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success else {
            return false
        }
        let windowElement = windowRef as! AXUIElement
        var fullscreenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, "AXFullScreen" as CFString, &fullscreenRef) == .success else {
            return false
        }
        return (fullscreenRef as? Bool) ?? false
    }

    private func windows(for pid: pid_t) -> [WindowInfo] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [WindowInfo] = []
        for info in infos {
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == pid,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let id = info[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else {
                continue
            }

            let bounds = CGRect(
                x: boundsDict["X"] ?? .zero,
                y: boundsDict["Y"] ?? .zero,
                width: boundsDict["Width"] ?? .zero,
                height: boundsDict["Height"] ?? .zero
            )

            guard !bounds.isEmpty else { continue }
            result.append(WindowInfo(id: id, ownerPID: ownerPID, bounds: bounds, layer: layer))
        }

        return result
    }

    public func displayID(containing rect: CGRect) -> CGDirectDisplayID? {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetDisplaysWithRect(rect, 16, &displayIDs, &count)
        return count > 0 ? displayIDs[0] : nil
    }

    private func rectDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private func convertAXRectToCocoaIfNeeded(_ rect: CGRect) -> CGRect {
        let allScreensFrame = NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }

        guard !allScreensFrame.isNull else { return rect }

        let flipped = CGRect(
            x: rect.origin.x,
            y: allScreensFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let containsOriginal = NSScreen.screens.contains { $0.frame.intersects(rect) }
        let containsFlipped = NSScreen.screens.contains { $0.frame.intersects(flipped) }

        if containsOriginal && !containsFlipped { return rect }
        if containsFlipped && !containsOriginal { return flipped }

        return containsFlipped ? flipped : rect
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}