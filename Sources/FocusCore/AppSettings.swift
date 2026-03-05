import AppKit
import Combine
public struct AppProfile: Codable, Identifiable, Equatable {
    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String
    public var dimAmount: Double
    public var blurAmount: Double
    public var blurEnabled: Bool

    public init(bundleID: String, appName: String = "", dimAmount: Double = 0.5, blurAmount: Double = 0, blurEnabled: Bool = false) {
        self.bundleID = bundleID
        self.appName = appName
        self.dimAmount = dimAmount
        self.blurAmount = blurAmount
        self.blurEnabled = blurEnabled
    }
}
public enum AnimationCurve: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear    = "Linear"
    case easeIn    = "Ease In"
    case easeOut   = "Ease Out"
    case easeInOut = "Ease In Out"
    case spring    = "Spring"

    public var id: String { rawValue }

    public var caTimingFunction: CAMediaTimingFunction? {
        switch self {
        case .linear:    return CAMediaTimingFunction(name: .linear)
        case .easeIn:    return CAMediaTimingFunction(name: .easeIn)
        case .easeOut:   return CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
        case .spring:    return nil
        }
    }
}
public enum DimPreset: String, CaseIterable, Identifiable, Sendable {
    case off    = "Off"
    case light  = "Light"
    case medium = "Medium"
    case heavy  = "Heavy"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .off:    return "circle.dashed"
        case .light:  return "circle.lefthalf.filled"
        case .medium: return "circle.righthalf.filled"
        case .heavy:  return "circle.fill"
        }
    }

    public var dimAmount: Double {
        switch self {
        case .off:    return 0
        case .light:  return 0.25
        case .medium: return 0.50
        case .heavy:  return 0.75
        }
    }

    public var blurEnabled: Bool {
        false
    }

    public var blurAmount: Double {
        0
    }
}
public struct KeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultIncrease = KeyShortcut(keyCode: 47, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)
    public static let defaultDecrease = KeyShortcut(keyCode: 43, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)
    public static let defaultToggle   = KeyShortcut(keyCode: 44, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)
    public static let legacyDefaultIncrease = KeyShortcut(keyCode: 24, modifiers: NSEvent.ModifierFlags([.command, .option, .control]).rawValue)
    public static let legacyDefaultDecrease = KeyShortcut(keyCode: 27, modifiers: NSEvent.ModifierFlags([.command, .option, .control]).rawValue)
    public static let legacyDefaultToggle   = KeyShortcut(keyCode: 29, modifiers: NSEvent.ModifierFlags([.command, .option, .control]).rawValue)

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    public var displayString: String {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        let keyName = Self.keyCodeNames[keyCode] ?? "Key\(keyCode)"
        parts.append(keyName)
        return parts.joined()
    }

    private static let keyCodeNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: "Ö",
        44: ".", 45: "N", 46: "M", 47: "Ç", 48: "⇥", 49: "Space",
        50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    public static let idleTimeoutSteps: [Double] = [10, 30, 60, 90, 120]
    public static let allScheduleWeekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    @Published public var isEnabled: Bool { didSet { save() } }
    @Published public var dimAmount: Double { didSet { save() } }
    @Published public var blurEnabled: Bool { didSet { save() } }
    @Published public var blurAmount: Double { didSet { save() } }
    @Published public var dimMenuBar: Bool { didSet { save() } }
    @Published public var dimOtherDisplays: Bool { didSet { save() } }
    @Published public var fadeDuration: Double { didSet { save() } }
    @Published public var excludedBundleIDsRaw: String { didSet { save() } }
    @Published public var tintR: Double { didSet { save() } }
    @Published public var tintG: Double { didSet { save() } }
    @Published public var tintB: Double { didSet { save() } }
    @Published public var appProfiles: [AppProfile] { didSet { save() } }
    @Published public var animationCurve: AnimationCurve { didSet { save() } }
    @Published public var batteryAwareEnabled: Bool { didSet { save() } }
    @Published public var batteryDimReduction: Double { didSet { save() } }
    @Published public var batteryDisableBlur: Bool { didSet { save() } }
    @Published public var shortcutIncrease: KeyShortcut { didSet { save() } }
    @Published public var shortcutDecrease: KeyShortcut { didSet { save() } }
    @Published public var shortcutToggle: KeyShortcut { didSet { save() } }
    @Published public var launchAtLogin: Bool { didSet { save() } }
    @Published public var fullscreenAwareness: Bool { didSet { save() } }
    @Published public var idleDimEnabled: Bool { didSet { save() } }
    @Published public var idleTimeout: Double { didSet { save() } }
    @Published public var idleDimAmount: Double { didSet { save() } }
    @Published public var pomodoroEnabled: Bool { didSet { save() } }
    @Published public var pomodoroFocusMinutes: Double { didSet { save() } }
    @Published public var pomodoroBreakMinutes: Double { didSet { save() } }
    @Published public var pomodoroAutoDim: Bool { didSet { save() } }
    @Published public var pomodoroMenuBarTimerEnabled: Bool { didSet { save() } }
    @Published public var scheduleEnabled: Bool { didSet { save() } }
    @Published public var scheduleUseAllDays: Bool { didSet { save() } }
    @Published public var scheduleDays: [Int] { didSet { save() } }
    @Published public var scheduleStartHour: Int { didSet { save() } }
    @Published public var scheduleStartMinute: Int { didSet { save() } }
    @Published public var scheduleEndHour: Int { didSet { save() } }
    @Published public var scheduleEndMinute: Int { didSet { save() } }
    @Published public var searchPanelExclusion: Bool { didSet { save() } }

    private let ud = UserDefaults.standard

    private init() {
        isEnabled           = ud.object(forKey: "isEnabled") as? Bool ?? true
        dimAmount           = ud.object(forKey: "dimAmount") as? Double ?? 0.50
        blurEnabled         = ud.object(forKey: "blurEnabled") as? Bool ?? false
        blurAmount          = ud.object(forKey: "blurAmount") as? Double ?? 0
        dimMenuBar          = ud.object(forKey: "dimMenuBar") as? Bool ?? false
        dimOtherDisplays    = ud.object(forKey: "dimOtherDisplays") as? Bool ?? true
        fadeDuration        = ud.object(forKey: "fadeDuration") as? Double ?? 0.18
        excludedBundleIDsRaw = ud.string(forKey: "excludedBundleIDsRaw") ?? ""
        tintR               = ud.object(forKey: "tintR") as? Double ?? 0
        tintG               = ud.object(forKey: "tintG") as? Double ?? 0
        tintB               = ud.object(forKey: "tintB") as? Double ?? 0

        if let data = ud.data(forKey: "appProfiles"),
           let decoded = try? JSONDecoder().decode([AppProfile].self, from: data) {
            appProfiles = decoded
        } else {
            appProfiles = []
        }

        if let raw = ud.string(forKey: "animationCurve"),
           let curve = AnimationCurve(rawValue: raw) {
            animationCurve = curve
        } else {
            animationCurve = .easeOut
        }

        batteryAwareEnabled  = ud.object(forKey: "batteryAwareEnabled") as? Bool ?? false
        batteryDimReduction  = ud.object(forKey: "batteryDimReduction") as? Double ?? 0.5
        batteryDisableBlur   = ud.object(forKey: "batteryDisableBlur") as? Bool ?? true

        if let data = ud.data(forKey: "shortcutIncrease"),
           let s = try? JSONDecoder().decode(KeyShortcut.self, from: data) {
            shortcutIncrease = s
        } else { shortcutIncrease = .defaultIncrease }
        if let data = ud.data(forKey: "shortcutDecrease"),
           let s = try? JSONDecoder().decode(KeyShortcut.self, from: data) {
            shortcutDecrease = s
        } else { shortcutDecrease = .defaultDecrease }
        if let data = ud.data(forKey: "shortcutToggle"),
           let s = try? JSONDecoder().decode(KeyShortcut.self, from: data) {
            shortcutToggle = s
        } else { shortcutToggle = .defaultToggle }

        launchAtLogin       = ud.object(forKey: "launchAtLogin") as? Bool ?? false
        fullscreenAwareness = ud.object(forKey: "fullscreenAwareness") as? Bool ?? true
        idleDimEnabled      = ud.object(forKey: "idleDimEnabled") as? Bool ?? false
        let rawIdleTimeout = ud.object(forKey: "idleTimeout") as? Double ?? 10
        idleTimeout        = Self.idleTimeoutSteps.min(by: { abs($0 - rawIdleTimeout) < abs($1 - rawIdleTimeout) }) ?? 10
        idleDimAmount       = ud.object(forKey: "idleDimAmount") as? Double ?? 0.85

        pomodoroEnabled       = ud.object(forKey: "pomodoroEnabled") as? Bool ?? false
        pomodoroFocusMinutes  = ud.object(forKey: "pomodoroFocusMinutes") as? Double ?? 25
        pomodoroBreakMinutes  = ud.object(forKey: "pomodoroBreakMinutes") as? Double ?? 5
        pomodoroAutoDim       = ud.object(forKey: "pomodoroAutoDim") as? Bool ?? true
        pomodoroMenuBarTimerEnabled = ud.object(forKey: "pomodoroMenuBarTimerEnabled") as? Bool ?? true

        scheduleEnabled       = ud.object(forKey: "scheduleEnabled") as? Bool ?? false
        scheduleUseAllDays    = ud.object(forKey: "scheduleUseAllDays") as? Bool ?? true
        let loadedScheduleDays = (ud.array(forKey: "scheduleDays") as? [Int]) ?? Self.allScheduleWeekdays
        let normalizedScheduleDays = Set(loadedScheduleDays.filter { (1...7).contains($0) }).sorted()
        scheduleDays          = normalizedScheduleDays.isEmpty ? Self.allScheduleWeekdays : normalizedScheduleDays
        scheduleStartHour     = ud.object(forKey: "scheduleStartHour") as? Int ?? 9
        scheduleStartMinute   = ud.object(forKey: "scheduleStartMinute") as? Int ?? 0
        scheduleEndHour       = ud.object(forKey: "scheduleEndHour") as? Int ?? 17
        scheduleEndMinute     = ud.object(forKey: "scheduleEndMinute") as? Int ?? 0

        searchPanelExclusion  = ud.object(forKey: "searchPanelExclusion") as? Bool ?? true

        if shortcutIncrease == .legacyDefaultIncrease &&
            shortcutDecrease == .legacyDefaultDecrease &&
            shortcutToggle == .legacyDefaultToggle {
            shortcutIncrease = .defaultIncrease
            shortcutDecrease = .defaultDecrease
            shortcutToggle = .defaultToggle
        }
    }

    public var excludedBundleIDs: Set<String> {
        Set(
            excludedBundleIDsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    public var hasMultipleDisplays: Bool { NSScreen.screens.count > 1 }

    public var tintNSColor: NSColor {
        NSColor(red: tintR, green: tintG, blue: tintB, alpha: 1)
    }

    public func profile(for bundleID: String?) -> AppProfile? {
        guard let bid = bundleID else { return nil }
        return appProfiles.first(where: { $0.bundleID == bid })
    }

    public func addProfile(_ profile: AppProfile) {
        if let idx = appProfiles.firstIndex(where: { $0.bundleID == profile.bundleID }) {
            appProfiles[idx] = profile
        } else {
            appProfiles.append(profile)
        }
    }

    public func removeProfile(bundleID: String) {
        appProfiles.removeAll(where: { $0.bundleID == bundleID })
    }

    public static let searchPanelBundleIDs: Set<String> = [
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "com.runningwithcrayons.Alfred-5",
        "at.obdev.LaunchBar",
        "com.apple.inputmethod.EmojiFunctionRowItem"
    ]

    public var isWithinSchedule: Bool {
        guard scheduleEnabled else { return true }
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        if !scheduleUseAllDays && !Set(scheduleDays).contains(weekday) {
            return false
        }
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nowMinutes = hour * 60 + minute
        let startMinutes = scheduleStartHour * 60 + scheduleStartMinute
        let endMinutes = scheduleEndHour * 60 + scheduleEndMinute
        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }

    public func applyPreset(_ preset: DimPreset) {
        if preset == .off {
            isEnabled = false
            dimAmount = 0
            blurEnabled = false
            blurAmount = 0
        } else {
            isEnabled = true
            dimAmount = preset.dimAmount
            blurEnabled = preset.blurEnabled
            blurAmount = preset.blurAmount
        }
    }

    public var currentPreset: DimPreset? {
        if !isEnabled { return .off }
        return DimPreset.allCases.first(where: {
            $0 != .off &&
            abs($0.dimAmount - dimAmount) < 0.05 &&
            $0.blurEnabled == blurEnabled
        })
    }

    public func increaseDim(by step: Double = 0.05) {
        dimAmount = min(1.0, dimAmount + step)
    }

    public func decreaseDim(by step: Double = 0.05) {
        dimAmount = max(0.0, dimAmount - step)
    }

    private func save() {
        ud.set(isEnabled, forKey: "isEnabled")
        ud.set(dimAmount, forKey: "dimAmount")
        ud.set(blurEnabled, forKey: "blurEnabled")
        ud.set(blurAmount, forKey: "blurAmount")
        ud.set(dimMenuBar, forKey: "dimMenuBar")
        ud.set(dimOtherDisplays, forKey: "dimOtherDisplays")
        ud.set(fadeDuration, forKey: "fadeDuration")
        ud.set(excludedBundleIDsRaw, forKey: "excludedBundleIDsRaw")
        ud.set(tintR, forKey: "tintR")
        ud.set(tintG, forKey: "tintG")
        ud.set(tintB, forKey: "tintB")
        if let data = try? JSONEncoder().encode(appProfiles) {
            ud.set(data, forKey: "appProfiles")
        }
        ud.set(animationCurve.rawValue, forKey: "animationCurve")
        ud.set(batteryAwareEnabled, forKey: "batteryAwareEnabled")
        ud.set(batteryDimReduction, forKey: "batteryDimReduction")
        ud.set(batteryDisableBlur, forKey: "batteryDisableBlur")
        if let data = try? JSONEncoder().encode(shortcutIncrease) { ud.set(data, forKey: "shortcutIncrease") }
        if let data = try? JSONEncoder().encode(shortcutDecrease) { ud.set(data, forKey: "shortcutDecrease") }
        if let data = try? JSONEncoder().encode(shortcutToggle) { ud.set(data, forKey: "shortcutToggle") }
        ud.set(launchAtLogin, forKey: "launchAtLogin")
        ud.set(fullscreenAwareness, forKey: "fullscreenAwareness")
        ud.set(idleDimEnabled, forKey: "idleDimEnabled")
        ud.set(idleTimeout, forKey: "idleTimeout")
        ud.set(idleDimAmount, forKey: "idleDimAmount")
        ud.set(pomodoroEnabled, forKey: "pomodoroEnabled")
        ud.set(pomodoroFocusMinutes, forKey: "pomodoroFocusMinutes")
        ud.set(pomodoroBreakMinutes, forKey: "pomodoroBreakMinutes")
        ud.set(pomodoroAutoDim, forKey: "pomodoroAutoDim")
        ud.set(pomodoroMenuBarTimerEnabled, forKey: "pomodoroMenuBarTimerEnabled")
        ud.set(scheduleEnabled, forKey: "scheduleEnabled")
        ud.set(scheduleUseAllDays, forKey: "scheduleUseAllDays")
        ud.set(scheduleDays, forKey: "scheduleDays")
        ud.set(scheduleStartHour, forKey: "scheduleStartHour")
        ud.set(scheduleStartMinute, forKey: "scheduleStartMinute")
        ud.set(scheduleEndHour, forKey: "scheduleEndHour")
        ud.set(scheduleEndMinute, forKey: "scheduleEndMinute")
        ud.set(searchPanelExclusion, forKey: "searchPanelExclusion")
    }
}
