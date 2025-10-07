import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("No history yet")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("History")
        }
    }
}
