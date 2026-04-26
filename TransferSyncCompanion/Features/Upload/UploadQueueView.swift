import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct UploadQueueView: View {
    @Environment(UploadManager.self) private var uploadManager

    var body: some View {
        VStack(spacing: 0) {
            if let error = uploadManager.error {
                ErrorBanner(message: error) {
                    uploadManager.dismissError()
                }
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(uploadManager.items) { item in
                        UploadQueueItemRow(
                            item: item,
                            onCancel: {
                                Task { await uploadManager.cancelUpload(id: item.id) }
                            },
                            onRetry: (item.status == .failed || item.status == .exhausted) ? { [item] in
                                Task { await uploadManager.retryUpload(id: item.id) }
                            } : nil,
                            onExportPtx: item.status == .complete ? {
                                Task { await exportPtx(for: item) }
                            } : nil
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
    }

    private func exportPtx(for item: UploadItem) async {
        do {
            let (data, filename) = try await uploadManager.apiClient.downloadPtx(assetId: item.assetId)

            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = filename
                panel.allowedContentTypes = [.data]
                panel.canCreateDirectories = true

                guard panel.runModal() == .OK, let url = panel.url else { return }

                do {
                    try data.write(to: url)
                } catch {
                    uploadManager.error = "Failed to save PTX file: \(error.localizedDescription)"
                }
            }
        } catch {
            await MainActor.run {
                uploadManager.error = "Failed to export PTX: \(error.localizedDescription)"
            }
        }
    }
}
