import Foundation

@MainActor
protocol DelayCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol DelayScheduling: AnyObject {
    func schedule(
        afterMilliseconds milliseconds: Int,
        action: @escaping @MainActor () -> Void
    ) -> any DelayCancellation
}

@MainActor
final class TaskDelayCancellation: DelayCancellation {
    private var task: Task<Void, Never>?

    init(_ task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class TaskDelayScheduler: DelayScheduling {
    func schedule(
        afterMilliseconds milliseconds: Int,
        action: @escaping @MainActor () -> Void
    ) -> any DelayCancellation {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskDelayCancellation(task)
    }
}
