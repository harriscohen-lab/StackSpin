import SwiftUI

struct AuthView: View {
    @Environment(\.spotifyAuth) private var spotifyAuth
    @State private var isSigningIn = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("StackSpin")
                .font(.system(size: 28, weight: .semibold))
            Text("Connect Spotify to add albums automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            MonoButton(title: isSigningIn ? "Signing In…" : "Sign in with Spotify", action: signIn)
                .disabled(isSigningIn)
            if let error {
                Text(error)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .padding(32)
    }

    private func signIn() {
        Task {
            isSigningIn = true
            do {
                try await spotifyAuth.signIn()
            } catch {
                self.error = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
