import SwiftUI

struct DestinationPickerView: View {
    @Bindable var viewModel: DestinationPickerViewModel
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(viewModel: DestinationPickerViewModel, confirmLabel: String = "Upload Here", onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.viewModel = viewModel
        self.confirmLabel = confirmLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if viewModel.canGoBack {
                    Button {
                        Task { await viewModel.navigateBack() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13))
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

            if viewModel.currentStep == .folder {
                DestinationBreadcrumb(viewModel: viewModel)
            }

            DestinationPickerList(viewModel: viewModel)

            if viewModel.selectedProject != nil {
                Button(confirmLabel, action: onConfirm)
                    .buttonStyle(.cta)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
        }
    }
}
