import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var flushHandler: (@MainActor () async -> Void)?
    var cleanupHandler: (@MainActor () -> Void)?
    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending, let flushHandler else {
            cleanupHandler?()
            return terminationPending ? .terminateLater : .terminateNow
        }

        terminationPending = true
        Task { @MainActor in
            cleanupHandler?()
            await flushHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
