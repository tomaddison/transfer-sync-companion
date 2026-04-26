import SwiftUI

struct WatchedFolderSetupView: View {
    @Bindable var viewModel: WatchedFolderSetupViewModel
    @Environment(\.panelManager) private var panelManager
    let onConfirm: (WatchedFolder) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if viewModel.canGoBack {
                    Button {
                        Task { await viewModel.navigateBack() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.ghostIcon)
                }

                Text(viewModel.stepTitle)
                    .font(Font.companion(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button("Cancel") { onCancel() }
                    .font(Font.companion(size: 11))
                    .foregroundStyle(Color.companionMutedText)
                    .buttonStyle(.ghost)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            switch viewModel.currentStep {
            case .selectDestination:
                destinationContent

            case .selectLocalFolder:
                localFolderContent
            }
        }
    }

    // MARK: - Destination Step

    @ViewBuilder
    private var destinationContent: some View {
        let picker = viewModel.destinationPicker

        if picker.currentStep == .folder {
            DestinationBreadcrumb(viewModel: picker)
        }

        DestinationPickerList(viewModel: picker)

        if picker.selectedProject != nil {
            Button("Choose Destination") {
                viewModel.confirmDestination()
            }
            .buttonStyle(.cta)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    // MARK: - Local Folder Step

    @ViewBuilder
    private var localFolderContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(Color.companionMutedText)

            VStack(spacing: 4) {
                if let project = viewModel.destinationPicker.selectedProject {
                    Text("Uploading to: \(project.name)")
                        .font(Font.companion(size: 13))
                        .foregroundStyle(Color.companionMutedText)
                }
                Text(viewModel.destinationPicker.destinationLabel)
                    .font(Font.companion(size: 11))
                    .foregroundStyle(Color.companionMutedText.opacity(0.7))
            }

            Text("Choose the folder where your\nDAW bounces audio files.")
                .font(Font.companion(size: 13))
                .foregroundStyle(Color.companionMutedText)
                .multilineTextAlignment(.center)

            if let error = viewModel.error {
                Text(error)
                    .font(Font.companion(size: 11))
                    .foregroundStyle(Color.companionStatusRed)
            }

            Button("Choose Folder") {
                viewModel.selectLocalFolder(panelManager: panelManager, onSuccess: onConfirm)
            }
            .buttonStyle(.cta)
            .disabled(viewModel.isSelectingFolder)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
