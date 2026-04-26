import SwiftUI

/// Shared rendering for `DestinationPickerViewModel` - used by both the upload
/// destination picker and the watched-folder setup flow so the two stay visually
/// identical.
struct DestinationPickerList: View {
 @Bindable var viewModel: DestinationPickerViewModel

 var body: some View {
 if viewModel.isLoading {
 Spacer()
 ProgressView().scaleEffect(0.8)
 Spacer()
 } else if let error = viewModel.error {
 Spacer()
 Text(error)
 .font(Font.companion(size: 11))
 .foregroundStyle(Color.companionStatusRed)
 .multilineTextAlignment(.center)
 .padding(.horizontal, 16)
 Spacer()
 } else {
 ScrollView {
 LazyVStack(spacing: 4) {
 switch viewModel.currentStep {
 case .workspace:
 ForEach(viewModel.workspaces) { workspace in
 row(icon: "building.2", title: workspace.name) {
 await viewModel.selectWorkspace(workspace)
 }
 }

 case .project:
 ForEach(viewModel.projects) { project in
 row(icon: "folder", title: project.name) {
 await viewModel.selectProject(project)
 }
 }

 case .folder:
 if viewModel.folders.isEmpty {
 Text("No subfolders")
 .font(Font.companion(size: 11))
 .foregroundStyle(Color.companionMutedText.opacity(0.5))
 .padding(.vertical, 20)
 } else {
 ForEach(viewModel.folders) { folder in
 row(icon: "folder.fill", title: folder.name) {
 await viewModel.selectFolder(folder)
 }
 }
 }
 }
 }
 .padding(.horizontal, 16)
 .padding(.vertical, 8)
 }
 }
 }

 @ViewBuilder
 private func row(icon: String, title: String, action: @escaping () async -> Void) -> some View {
 Button {
 Task { await action() }
 } label: {
 PickerRowView(icon: icon, title: title)
 .background(Color.companionTabBar)
 .clipShape(RoundedRectangle(cornerRadius: 14))
 }
 .buttonStyle(.plain)
 }
}

/// Breadcrumb shared by the upload and watched-folder destination flows.
struct DestinationBreadcrumb: View {
 let viewModel: DestinationPickerViewModel

 var body: some View {
 HStack(spacing: 4) {
 Text(viewModel.selectedProject?.name ?? "")
 .font(Font.companion(size: 11))
 .foregroundStyle(Color.companionMutedText)

 if !viewModel.folderPath.isEmpty {
 ForEach(viewModel.folderPath) { folder in
 Image(systemName: "chevron.right")
 .font(.system(size: 8))
 .foregroundStyle(Color.companionMutedText.opacity(0.5))
 Text(folder.name)
 .font(Font.companion(size: 11))
 .foregroundStyle(Color.companionMutedText)
 }
 }

 Spacer()
 }
 .padding(.horizontal, 16)
 .padding(.vertical, 6)
 }
}
