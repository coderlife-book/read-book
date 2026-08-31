import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var flushHandler: (@MainActor () async -> Void)?
    var cleanupHandler: (@MainActor () -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Reading progress is already persisted on a short debounce and when the
        // reader is hidden/backgrounded. Never hold macOS logout/restart hostage
        // to one final asynchronous write: if the app is unhealthy, terminate
        // immediately and accept at most a tiny amount of progress drift.
        cleanupHandler?()
        return .terminateNow
    }
}
