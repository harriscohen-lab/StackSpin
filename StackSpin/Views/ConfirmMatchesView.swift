import SwiftUI

struct ConfirmMatchesView: View {
    let candidates: [AlbumMatch]
    let onSelect: (AlbumMatch) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Confirm Album")
                .font(.system(size: 22, weight: .semibold))
            ForEach(candidates) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    HStack(spacing: 16) {
                        AsyncImage(url: candidate.artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.1)
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.title)
                                .font(.system(size: 17, weight: .semibold))
                            Text(candidate.artist)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                            if let year = candidate.year {
                                Text(year)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}
