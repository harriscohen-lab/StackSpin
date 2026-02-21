import SwiftUI

struct SettingsView: View {
    @Environment(\.settingsStore) private var settingsStore
    @Environment(\.spotifyAuth) private var spotifyAuth

    @State private var isShowingPlaylistPrompt = false
    @State private var playlistInput = ""
    @State private var isReauthenticating = false
    @State private var spotifyMessage: String?

    private var spotifyAPI: SpotifyAPI {
        SpotifyAPI(authController: spotifyAuth)
    }

    var body: some View {
        Form {
            Section("Spotify") {
                MonoButton(title: "Choose Playlist") {
                    playlistInput = settingsStore.settings.spotifyPlaylistID ?? ""
                    isShowingPlaylistPrompt = true
                }
                MonoButton(title: isReauthenticating ? "Reconnecting Spotify…" : "Reconnect Spotify") {
                    reconnectSpotify()
                }
                .disabled(isReauthenticating)

                if let id = settingsStore.settings.spotifyPlaylistID {
                    Text("Selected: \(id)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let spotifyMessage {
                    Text(spotifyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Preferences") {
                Toggle("Add entire album", isOn: Binding(
                    get: { settingsStore.settings.addEntireAlbum },
                    set: { newValue in settingsStore.update { $0.addEntireAlbum = newValue } }
                ))
                Picker("Market", selection: Binding(
                    get: { settingsStore.settings.market },
                    set: { newValue in settingsStore.update { $0.market = newValue } }
                )) {
                    ForEach(["US", "GB", "DE", "FR", "JP"], id: \.self) { region in
                        Text(region)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Image match threshold")
                    Slider(value: Binding(
                        get: { settingsStore.settings.featureThreshold },
                        set: { newValue in settingsStore.update { $0.featureThreshold = newValue } }
                    ), in: 5...25)
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Choose Playlist", isPresented: $isShowingPlaylistPrompt) {
            TextField("Spotify playlist ID", text: $playlistInput)
            Button("Save") {
                let normalized = AppSettings.normalizedPlaylistID(from: playlistInput)
                settingsStore.update { $0.spotifyPlaylistID = normalized }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a Spotify playlist ID (for example, from spotify:playlist:<id> or open.spotify.com/playlist/<id>).")
        }
    }

    private func reconnectSpotify() {
        Task {
            isReauthenticating = true
            spotifyMessage = nil
            do {
                try await spotifyAuth.signIn()
                if let playlistID = settingsStore.settings.spotifyPlaylistID,
                   !playlistID.isEmpty {
                    let probe = try await spotifyAPI.probePlaylistWriteAccess(playlistID: playlistID)
                    if probe.canWrite {
                        spotifyMessage = "Reconnect successful; write capability confirmed. \(probe.details)"
                    } else {
                        spotifyMessage = "Reconnect succeeded, but write permissions still denied. Reconnect Spotify to refresh playlist write permissions. \(probe.details)"
                    }
                } else {
                    spotifyMessage = "Spotify account reconnected."
                }
            } catch let appError as AppError {
                switch appError {
                case .spotifyAuthCancelled:
                    spotifyMessage = "Spotify sign-in cancelled."
                case .spotifyPermissionsExpiredOrInsufficient:
                    spotifyMessage = "Reconnect succeeded, but write permissions are still missing. Reconnect Spotify to refresh playlist write permissions."
                default:
                    spotifyMessage = appError.localizedDescription
                }
            } catch {
                spotifyMessage = error.localizedDescription
            }
            isReauthenticating = false
        }
    }
}
