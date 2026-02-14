import SwiftUI

struct RootView: View {
    @EnvironmentObject private var spotifyAuth: SpotifyAuthController

    var body: some View {
        Group {
            if spotifyAuth.isAuthorized() {
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
            } else {
                AuthView()
            }
        }
    }
}
