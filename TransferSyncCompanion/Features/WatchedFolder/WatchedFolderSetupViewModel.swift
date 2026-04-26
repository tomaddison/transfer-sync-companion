import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "WatchedFolderSetup")

@Observable
@MainActor
final class WatchedFolderSetupViewModel {
 enum Step: Equatable {
 case selectDestination
 case selectLocalFolder
 }

 var currentStep: Step { computedStep }

 // Reuse the existing picker for workspace/project/folder selection
 let destinationPicker: DestinationPickerViewModel

 // Destination confirmation
 var destinationConfirmed = false

 // Local folder selection
 var selectedLocalFolderURL: URL?
 var selectedLocalFolderPath: String?
 var bookmarkData: Data?

 // Setup state
 var error: String?
 private(set) var isSelectingFolder = false

 private let existingPaths: Set<String>

 init(apiClient: any UploadAPIClient, existingWatchedPaths: Set<String>) {
 self.destinationPicker = DestinationPickerViewModel(apiClient: apiClient)
 self.existingPaths = existingWatchedPaths
 }

 var stepTitle: String {
 switch currentStep {
 case .selectDestination: destinationPicker.stepTitle
 case .selectLocalFolder: "Select Folder to Watch"
 }
 }

 var canGoBack: Bool {
 switch currentStep {
 case .selectDestination: destinationPicker.canGoBack
 case .selectLocalFolder: true
 }
 }

 private var computedStep: Step {
 if !destinationConfirmed { return .selectDestination }
 return .selectLocalFolder
 }

 // MARK: - Actions

 func loadWorkspaces() async {
 await destinationPicker.loadWorkspaces()
 }

 func confirmDestination() {
 guard destinationPicker.selectedProject != nil else { return }
 destinationConfirmed = true
 error = nil
 }

 func navigateBack() async {
 switch currentStep {
 case .selectLocalFolder:
 destinationConfirmed = false
 case .selectDestination:
 await destinationPicker.navigateBack()
 }
 }

 func selectLocalFolder(panelManager: MenuBarPanelManager?, onSuccess: @escaping (WatchedFolder) -> Void) {
 guard !isSelectingFolder else { return }
 isSelectingFolder = true
 error = nil

 panelManager?.suspendClickMonitoring()
 NSApp.activate()

 let panel = NSOpenPanel()
 panel.canChooseFiles = false
 panel.canChooseDirectories = true
 panel.allowsMultipleSelection = false
 panel.message = "Select a folder to watch for audio files"
 panel.prompt = "Watch This Folder"

 panel.begin { [weak self] response in
 Task { @MainActor in
 guard let self else { return }
 self.isSelectingFolder = false
 panelManager?.resumeClickMonitoring()
 panelManager?.show()

 guard response == .OK, let url = panel.url else { return }

 if self.existingPaths.contains(url.path) {
 self.error = "This folder is already being watched"
 return
 }

 do {
 let bookmark = try url.bookmarkData(
 options: .withSecurityScope,
 includingResourceValuesForKeys: nil,
 relativeTo: nil
 )
 self.selectedLocalFolderURL = url
 self.selectedLocalFolderPath = url.path
 self.bookmarkData = bookmark
 } catch {
 logger.error("Failed to create bookmark: \(error.localizedDescription)")
 self.error = "Failed to access folder"
 return
 }

 guard let folder = self.buildWatchedFolder() else {
 self.error = "Missing destination - please go back and pick one"
 return
 }
 onSuccess(folder)
 }
 }
 }

 /// Build the WatchedFolder model from current selections.
 func buildWatchedFolder() -> WatchedFolder? {
 guard let project = destinationPicker.selectedProject,
 let workspace = destinationPicker.selectedWorkspace,
 let localPath = selectedLocalFolderPath,
 let bookmark = bookmarkData else {
 return nil
 }

 return WatchedFolder(
 localPath: localPath,
 transfersyncProjectId: project.id,
 projectName: project.name,
 workspaceId: workspace.id,
 destinationFolderId: destinationPicker.destinationParentId,
 destinationFolderName: destinationPicker.destinationLabel,
 watchingSince: Date(),
 enabled: true,
 bookmarkData: bookmark
 )
 }
}
