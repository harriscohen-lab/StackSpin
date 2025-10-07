import SwiftUI

struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .regular))
            .tracking(0.5)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
    }
}
