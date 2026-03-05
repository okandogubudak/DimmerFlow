import AppKit
import SwiftUI
import FocusSystem

@MainActor
public struct PermissionOnboardingView: View {
    private let permissionManager: PermissionManager
    private let onRestart: () -> Void
    private let onLater: () -> Void

    @State private var missing: [PermissionKind] = []

    public init(
        permissionManager: PermissionManager,
        onRestart: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        self.permissionManager = permissionManager
        self.onRestart = onRestart
        self.onLater = onLater
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DimmerFlow Permissions")
                .font(.title2.weight(.semibold))

            Text("DimmerFlow needs Accessibility permission to detect the active window. Please grant access and return here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if missing.isEmpty {
                Label("All permissions granted", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Missing: \(missing.map { $0.title }.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Request Permissions") {
                    permissionManager.requestMissingPermissions()
                    refresh()
                }
                Button("Open System Settings") {
                    permissionManager.openSystemSettingsForFirstMissing()
                }
                .disabled(missing.isEmpty)
                Button("Refresh") {
                    refresh()
                }
            }

            HStack {
                Spacer()
                Button("Continue") {
                    onLater()
                }
                .disabled(!missing.isEmpty)
                Button("Restart") {
                    onRestart()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!missing.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            permissionManager.requestMissingPermissions()
            permissionManager.openSystemSettingsForFirstMissing()
            refresh()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    @MainActor
    private func refresh() {
        missing = permissionManager.missingPermissions()
    }
}

@MainActor
public final class PermissionWindowController {
    private var window: NSWindow?

    public init() {}

    public func show(
        permissionManager: PermissionManager,
        onRestart: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        if window == nil {
            let root = PermissionOnboardingView(
                permissionManager: permissionManager,
                onRestart: onRestart,
                onLater: onLater
            )
            let hosting = NSHostingView(rootView: root)

            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 240),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            created.title = "Permissions"
            created.center()
            created.contentView = hosting
            created.isReleasedWhenClosed = false
            window = created
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.close()
    }
}
