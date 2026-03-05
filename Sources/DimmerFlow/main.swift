import AppKit

await MainActor.run {
    let app = NSApplication.shared
    let delegate = AppController()
    app.delegate = delegate
    app.run()
}
