import BackgroundTasks
import Foundation

final class BackgroundScheduler {
    private let taskIdentifier = "com.stackspin.process"
    var onProcessRequested: (@Sendable () async -> Bool)?

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            self.handle(task: task as! BGProcessingTask)
        }
    }

    func scheduleIfNeeded() async {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("Background scheduling failed: \(error)")
        }
    }

    private func handle(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        Task {
            let success = await onProcessRequested?() ?? true
            task.setTaskCompleted(success: success)
        }
    }
}
