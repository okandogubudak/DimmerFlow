import AppKit
import FocusCore

final class OverlayWindow: NSWindow {
    private let effectView = NSVisualEffectView()
    private let dimView = NSView()
    private var lastDimAmount: CGFloat = -1
    private var lastBlurAmount: CGFloat = -1
    private var lastFrame: NSRect = .zero

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .normal
        alphaValue = 1.0
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSView(frame: screen.frame)
        container.wantsLayer = true

        effectView.frame = container.bounds
        effectView.autoresizingMask = [.width, .height]
        effectView.wantsLayer = true
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.alphaValue = 0

        dimView.frame = container.bounds
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0

        container.addSubview(effectView)
        container.addSubview(dimView)
        contentView = container
    }

    func updateFrame(for screen: NSScreen, dimMenuBar: Bool) {
        let frame = adjustedFrame(for: screen, dimMenuBar: dimMenuBar)
        guard frame != lastFrame else { return }
        lastFrame = frame
        setFrame(frame, display: false)
        let bounds = NSRect(origin: .zero, size: frame.size)
        contentView?.frame = bounds
        effectView.frame = bounds
        dimView.frame = bounds
    }

    func setBlurEnabled(_ enabled: Bool) {
        effectView.isHidden = !enabled
    }

    func setBlurAmount(_ value: CGFloat, duration: Double, curve: AnimationCurve = .easeOut) {
        let v = max(0, min(1, value))
        guard abs(lastBlurAmount - v) > 0.002 else { return }
        lastBlurAmount = v
        animate(duration: duration, curve: curve) { self.effectView.animator().alphaValue = v }
    }

    func setDimAmount(_ value: CGFloat, duration: Double, curve: AnimationCurve = .easeOut) {
        let v = max(0, min(1, value))
        guard abs(lastDimAmount - v) > 0.002 else { return }
        lastDimAmount = v
        animate(duration: duration, curve: curve) { self.dimView.animator().alphaValue = v }
    }

    func resetAmountCache() {
        lastDimAmount = -1
        lastBlurAmount = -1
    }

    func setAppearanceColor(tintColor: NSColor, darkMode: Bool) {
        // True black: use NSColor.black directly (no gray offset)
        if let c = tintColor.usingColorSpace(.sRGB),
           c.redComponent < 0.02, c.greenComponent < 0.02, c.blueComponent < 0.02 {
            dimView.layer?.backgroundColor = NSColor.black.cgColor
        } else {
            dimView.layer?.backgroundColor = tintColor.cgColor
        }
    }

    private func animate(duration: Double, curve: AnimationCurve = .easeOut, changes: @escaping () -> Void) {
        if curve == .spring && duration > 0.01 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = max(0, duration * 1.4)
                ctx.allowsImplicitAnimation = true
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 1.8, 0.6, 0.8)
                changes()
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = max(0, duration)
                ctx.allowsImplicitAnimation = true
                if duration > 0.01, let tf = curve.caTimingFunction {
                    ctx.timingFunction = tf
                }
                changes()
            }
        }
    }

    private func adjustedFrame(for screen: NSScreen, dimMenuBar: Bool) -> NSRect {
        var frame = screen.frame
        let visible = screen.visibleFrame

        // Only exclude menu bar area when dimMenuBar is off
        if !dimMenuBar {
            let menuBarH = frame.maxY - visible.maxY
            if menuBarH > 0 {
                frame.size.height -= menuBarH
            }
        }

        // Cover dock area — no dock exclusion (dock dim removed)
        return frame
    }
}
