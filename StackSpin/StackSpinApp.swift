import SwiftUI

@main
struct StackSpinApp: App {
    @StateObject private var persistence: Persistence
    @StateObject private var jobRunner: JobRunner
    @StateObject private var settings: AppSettingsStore
    @StateObject private var auth: SpotifyAuthController

    init() {
        let persistence = Persistence.shared
        let auth = SpotifyAuthController()
        _persistence = StateObject(wrappedValue: persistence)
        _auth = StateObject(wrappedValue: auth)
        _settings = StateObject(wrappedValue: AppSettingsStore())
        _jobRunner = StateObject(wrappedValue: JobRunner(authController: auth, persistence: persistence))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.spotifyAuth, auth)
                .environment(\.settingsStore, settings)
                .environment(\.persistence, persistence)
                .environmentObject(jobRunner)
                .task {
                    await auth.restoreIfPossible()
                    await jobRunner.resumePendingJobs()
                }
        }
    }
}
