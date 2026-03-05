import AppKit
import Foundation
import Combine
import UserNotifications

public enum PomodoroPhase: String {
    case idle
    case focus
    case breakTime = "break"
}

@MainActor
public final class PomodoroTimer: ObservableObject {
    private let settings: AppSettings

    @Published public var phase: PomodoroPhase = .idle
    @Published public var remainingSeconds: Int = 0
    @Published public var completedSessions: Int = 0

    private var timer: Timer?

    public var onPhaseChange: ((PomodoroPhase) -> Void)?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var formattedTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    public var formattedClockTime: String {
        let sourceSeconds = phase == .idle ? Int(settings.pomodoroFocusMinutes * 60) : remainingSeconds
        let h = sourceSeconds / 3600
        let m = (sourceSeconds % 3600) / 60
        let s = sourceSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    public var phaseTitle: String {
        switch phase {
        case .focus:
            return "Focus"
        case .breakTime:
            return "Break"
        case .idle:
            return "Ready"
        }
    }

    public var isRunning: Bool { phase != .idle }

    public func startFocus() {
        phase = .focus
        remainingSeconds = Int(settings.pomodoroFocusMinutes * 60)
        onPhaseChange?(.focus)
        startTimer()
    }

    public func startBreak() {
        phase = .breakTime
        remainingSeconds = Int(settings.pomodoroBreakMinutes * 60)
        onPhaseChange?(.breakTime)
        startTimer()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        remainingSeconds = 0
        onPhaseChange?(.idle)
    }

    public func reset() {
        stop()
        completedSessions = 0
    }

    private func startTimer() {
        timer?.invalidate()
        let createdTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.tick()
            }
        }
        createdTimer.tolerance = 0.1
        RunLoop.main.add(createdTimer, forMode: .common)
        timer = createdTimer
    }

    private func tick() {
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        if remainingSeconds == 0 {
            timer?.invalidate()
            timer = nil
            handlePhaseEnd()
        }
    }

    private func handlePhaseEnd() {
        sendNotification()

        switch phase {
        case .focus:
            completedSessions += 1
            startBreak()
        case .breakTime:
            startFocus()
        case .idle:
            break
        }
    }

    private func sendNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        DispatchQueue.main.async {
            if let sound = NSSound(named: NSSound.Name("Glass")) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }

        let content = UNMutableNotificationContent()
        content.sound = .default

        switch phase {
        case .focus:
            content.title = "Focus Session Complete"
            content.body = "Time for a \(Int(settings.pomodoroBreakMinutes))-minute break!"
        case .breakTime:
            content.title = "Break Over"
            content.body = "Ready to focus again!"
        case .idle:
            return
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
