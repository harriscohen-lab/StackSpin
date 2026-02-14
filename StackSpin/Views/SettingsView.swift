import SwiftUI

struct SettingsView: View {
    @Environment(\.settingsStore) private var settingsStore

    @State private var isShowingPlaylistPrompt = false
    @State private var playlistInput = ""

    var body: some View {
        Form {
            Section("Spotify") {
                MonoButton(title: "Choose Playlist") {
                    playlistInput = settingsStore.settings.spotifyPlaylistID ?? ""
                    isShowingPlaylistPrompt = true
                }
                if let id = settingsStore.settings.spotifyPlaylistID {
                    Text("Selected: \(id)")
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
                let trimmed = playlistInput.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsStore.update { $0.spotifyPlaylistID = trimmed.isEmpty ? nil : trimmed }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a Spotify playlist ID (for example, from spotify:playlist:<id> or open.spotify.com/playlist/<id>).")
        }
    }
}
