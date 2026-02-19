import Foundation

enum AppError: LocalizedError, Identifiable {
    case spotifyAuth
    case spotifyAuthCancelled
    case spotifyAuthStateMismatch
    case network(String)
    case parsing
    case noPlaylist
    case unknown

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .spotifyAuth:
            return "Please sign in with Spotify to continue."
        case .spotifyAuthCancelled:
            return "Spotify sign-in was cancelled."
        case .spotifyAuthStateMismatch:
            return "Spotify sign-in couldn’t be verified. Please try again."
        case .network(let message):
            return message
        case .parsing:
            return "We couldn't understand the response from the server."
        case .noPlaylist:
            return "Select a playlist before processing albums."
        case .unknown:
            return "Something went wrong. Try again."
        }
    }
}
