import PhotosUI
import UIKit
import SwiftUI

struct BatchListView: View {
    @EnvironmentObject private var jobRunner: JobRunner
    @Environment(\.settingsStore) private var settingsStore
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 12) {
                    MonoButton(title: "Scan Barcode", action: {})
                    MonoButton(title: "Take Photo", action: {})
                    PhotosPicker(selection: $selectedPhotos, matching: .images) {
                        Text("Import")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                List {
                    ForEach(Array(jobRunner.jobs.enumerated()), id: \.offset) { _, job in
                        JobRow(job: job)
                    }
                }
                .listStyle(.plain)

                MonoButton(title: isProcessing ? "Processing…" : "Process All") {
                    processAll()
                }
                .disabled(isProcessing || jobRunner.jobs.isEmpty)
            }
            .padding()
            .navigationTitle("Batch")
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await handleSelection(newItems) }
        }
    }

    private func processAll() {
        Task {
            isProcessing = true
            await jobRunner.processAll(settings: settingsStore.settings)
            isProcessing = false
        }
    }

    private func handleSelection(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let placeholderID = UUID().uuidString
                jobRunner.enqueue(job: Job(photoLocalID: placeholderID), image: image)
            }
        }
        selectedPhotos = []
    }
}

private struct JobRow: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.chosenMBID ?? "Pending")
                    .font(.system(size: 17))
                Spacer()
                StatusBadge(text: job.state.rawValue)
            }
            if let error = job.errorDescription {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
