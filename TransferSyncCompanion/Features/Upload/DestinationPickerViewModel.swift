import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "DestinationPicker")

@Observable
@MainActor
final class DestinationPickerViewModel {
    // Selection state
    var selectedWorkspace: Workspace?
    var selectedProject: Project?
    var selectedFolder: Folder?
    var folderPath: [Folder] = []

    // Data
    private(set) var workspaces: [Workspace] = []
    private(set) var projects: [Project] = []
    private(set) var folders: [Folder] = []

    // Loading / error
    private(set) var isLoading = false
    private(set) var error: String?

    private let apiClient: any UploadAPIClient

    init(apiClient: any UploadAPIClient) {
        self.apiClient = apiClient
    }

    enum Step {
        case workspace
        case project
        case folder
    }

    var currentStep: Step {
        if selectedProject != nil { return .folder }
        if selectedWorkspace != nil { return .project }
        return .workspace
    }

    var stepTitle: String {
        switch currentStep {
        case .workspace: "Select Workspace"
        case .project: "Select Project"
        case .folder: "Select Destination"
        }
    }

    var canGoBack: Bool {
        selectedWorkspace != nil
    }

    /// The parentId to pass to /uploads/init. Falls back to the project's root asset ID.
    var destinationParentId: String? { selectedFolder?.id ?? selectedProject?.rootAssetId }

    var destinationLabel: String {
        if let folder = selectedFolder {
            return folder.name
        }
        if let project = selectedProject {
            return "\(project.name) (root)"
        }
        return ""
    }

    // MARK: - Load

    func loadWorkspaces() async {
        isLoading = true
        error = nil
        do {
            workspaces = try await apiClient.fetchWorkspaces()
        } catch {
            logger.error("Failed to load workspaces: \(error.localizedDescription)")
            self.error = "Failed to load workspaces"
        }
        isLoading = false
    }

    private func loadProjects(workspaceId: String) async {
        isLoading = true
        error = nil
        do {
            projects = try await apiClient.fetchProjects(workspaceId: workspaceId)
        } catch {
            logger.error("Failed to load projects: \(error.localizedDescription)")
            self.error = "Failed to load projects"
        }
        isLoading = false
    }

    private func loadFolders(projectId: String, parentId: String?) async {
        isLoading = true
        error = nil
        do {
            folders = try await apiClient.fetchFolders(projectId: projectId, parentId: parentId)
        } catch {
            logger.error("Failed to load folders: \(error.localizedDescription)")
            self.error = "Failed to load folders"
        }
        isLoading = false
    }

    // MARK: - Selection

    func selectWorkspace(_ workspace: Workspace) async {
        selectedWorkspace = workspace
        selectedProject = nil
        selectedFolder = nil
        folderPath = []
        projects = []
        folders = []
        await loadProjects(workspaceId: workspace.id)
    }

    func selectProject(_ project: Project) async {
        selectedProject = project
        selectedFolder = nil
        folderPath = []
        folders = []
        await loadFolders(projectId: project.id, parentId: nil)
    }

    func selectFolder(_ folder: Folder) async {
        guard let project = selectedProject else { return }
        selectedFolder = folder
        folderPath.append(folder)
        await loadFolders(projectId: project.id, parentId: folder.id)
    }

    func navigateBack() async {
        if folderPath.count > 1 {
            // Go up one folder level
            folderPath.removeLast()
            selectedFolder = folderPath.last
            await loadFolders(projectId: selectedProject!.id, parentId: selectedFolder?.id)
        } else if !folderPath.isEmpty {
            // Back to folder root
            folderPath.removeAll()
            selectedFolder = nil
            await loadFolders(projectId: selectedProject!.id, parentId: nil)
        } else if selectedProject != nil {
            // Back to project list
            selectedProject = nil
            folders = []
        } else {
            // Back to workspace list
            selectedWorkspace = nil
            projects = []
        }
    }
}
