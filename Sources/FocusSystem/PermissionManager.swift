import AppKit
import ApplicationServices

public enum PermissionKind: CaseIterable {
    case accessibility

    public var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        }
    }
}

@MainActor
public final class PermissionManager {
    public static let shared = PermissionManager()

    private let defaults = UserDefaults.standard
    private let onboardingKey = "didShowPermissionOnboarding"

    private init() {}

    public func shouldShowOnboardingOnLaunch() -> Bool {
        !missingPermissions().isEmpty || !defaults.bool(forKey: onboardingKey)
    }

    public func markOnboardingShown() {
        defaults.set(true, forKey: onboardingKey)
    }

    public func missingPermissions() -> [PermissionKind] {
        PermissionKind.allCases.filter { !isGranted($0) }
    }

    public func isGranted(_ permission: PermissionKind) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        }
    }

    public func request(_ permission: PermissionKind) {
        switch permission {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    public func requestMissingPermissions() {
        for permission in missingPermissions() {
            request(permission)
        }
    }

    public func openSystemSettings(for permission: PermissionKind) {
        let urlString: String
        switch permission {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    public func openSystemSettingsForFirstMissing() {
        guard let first = missingPermissions().first else { return }
        openSystemSettings(for: first)
    }
}