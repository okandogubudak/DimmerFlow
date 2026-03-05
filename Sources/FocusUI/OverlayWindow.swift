import AppKit
import QuartzCore
import FocusCore

final class OverlayWindow: NSWindow {
    private var effectView: NSVisualEffectView?
    private let dimView = NSView()
    private var lastDimAmount: CGFloat = -1
    private var lastBlurAmount: CGFloat = -1
    private var lastFrame: NSRect = .zero
    private var lastTintCGColor: CGColor?

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

        dimView.frame = container.bounds
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.cgColor
        dimView.alphaValue = 0

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
        effectView?.frame = bounds
        dimView.frame = bounds
    }

    func setBlurEnabled(_ enabled: Bool) {
        if enabled {
            ensureEffectView()
        }
        effectView?.isHidden = !enabled
    }

    func setBlurAmount(_ value: CGFloat, duration: Double, curve: AnimationCurve = .easeOut) {
        let v = max(0, min(1, value))
        guard abs(lastBlurAmount - v) > 0.002 else { return }
        lastBlurAmount = v
        if v > 0 { ensureEffectView() }
        guard let effectView else { return }
        animateOpacity(of: effectView, to: v, duration: duration, curve: curve, animationKey: "blurOpacity")
    }

    func setDimAmount(_ value: CGFloat, duration: Double, curve: AnimationCurve = .easeOut) {
        let v = max(0, min(1, value))
        guard abs(lastDimAmount - v) > 0.002 else { return }
        lastDimAmount = v
        animateOpacity(of: dimView, to: v, duration: duration, curve: curve, animationKey: "dimOpacity")
    }

    func resetAmountCache() {
        lastDimAmount = -1
        lastBlurAmount = -1
    }

    func setAppearanceColor(tintColor: NSColor, darkMode: Bool) {
        let newCGColor: CGColor
        if let c = tintColor.usingColorSpace(.sRGB),
           c.redComponent < 0.02, c.greenComponent < 0.02, c.blueComponent < 0.02 {
            newCGColor = NSColor.black.cgColor
        } else {
            newCGColor = tintColor.cgColor
        }
        guard lastTintCGColor == nil || newCGColor != lastTintCGColor! else { return }
        lastTintCGColor = newCGColor
        dimView.layer?.backgroundColor = newCGColor
    }

    private func ensureEffectView() {
        guard effectView == nil, let container = contentView else { return }
        let ev = NSVisualEffectView(frame: container.bounds)
        ev.autoresizingMask = [.width, .height]
        ev.wantsLayer = true
        ev.material = .hudWindow
        ev.blendingMode = .behindWindow
        ev.state = .active
        ev.alphaValue = 0
        container.addSubview(ev, positioned: .below, relativeTo: dimView)
        effectView = ev
    }

    private func animateOpacity(
        of view: NSView,
        to targetOpacity: CGFloat,
        duration: Double,
        curve: AnimationCurve,
        animationKey: String
    ) {
        guard let layer = view.layer else {
            view.alphaValue = targetOpacity
            return
        }

        let clampedDuration = max(0, duration)
        let fromOpacity = CGFloat(layer.presentation()?.opacity ?? layer.opacity)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = Float(targetOpacity)
        CATransaction.commit()

        guard clampedDuration > 0.01 else {
            layer.removeAnimation(forKey: animationKey)
            return
        }

        let animation: CAAnimation
        if curve == .spring {
            let spring = CASpringAnimation(keyPath: "opacity")
            spring.fromValue = fromOpacity
            spring.toValue = targetOpacity
            spring.mass = 1.0
            spring.stiffness = 180
            spring.damping = 19
            spring.initialVelocity = 0
            spring.duration = clampedDuration * 1.1
            animation = spring
        } else {
            let basic = CABasicAnimation(keyPath: "opacity")
            basic.fromValue = fromOpacity
            basic.toValue = targetOpacity
            basic.duration = clampedDuration
            basic.timingFunction = curve.caTimingFunction
            animation = basic
        }

        layer.removeAnimation(forKey: animationKey)
        layer.add(animation, forKey: animationKey)
    }

    private func adjustedFrame(for screen: NSScreen, dimMenuBar: Bool) -> NSRect {
        var frame = screen.frame
        let visible = screen.visibleFrame
        if !dimMenuBar {
            let menuBarH = frame.maxY - visible.maxY
            if menuBarH > 0 {
                frame.size.height -= menuBarH
            }
        }
        return frame
    }
}
