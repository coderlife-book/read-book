import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var flushHandler: (@MainActor () async -> Void)?
    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending, let flushHandler else {
            return terminationPending ? .terminateLater : .terminateNow
        }

        terminationPending = true
        Task { @MainActor in
            await flushHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
