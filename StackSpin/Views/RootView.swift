import SwiftUI

struct RootView: View {
    @EnvironmentObject private var spotifyAuth: SpotifyAuthController
    @EnvironmentObject private var jobRunner: JobRunner
    @Environment(\.settingsStore) private var settingsStore

    var body: some View {
        TabView {
            BatchListView()
                .tabItem {
                    Label("Batch", systemImage: "square.stack.3d.up")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .sheet(isPresented: Binding(get: { !spotifyAuth.isAuthorized() }, set: { _ in })) {
            AuthView()
        }
    }
}
