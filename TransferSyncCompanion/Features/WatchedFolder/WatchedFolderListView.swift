import SwiftUI

struct WatchedFolderListView: View {
    @Environment(WatchedFolderManager.self) private var manager
    @Environment(UploadManager.self) private var uploadManager
    @Environment(\.panelManager) private var panelManager

    @State private var setupVM: WatchedFolderSetupViewModel?
    @State private var showSetup = false
    @State private var changeDestinationFolder: WatchedFolder?
    @State private var changeDestinationVM: DestinationPickerViewModel?

    var body: some View {
        if showSetup, let vm = setupVM {
            WatchedFolderSetupView(viewModel: vm, onConfirm: { folder in
                manager.store.add(folder)
                manager.startWatching(folder)
                showSetup = false
                setupVM = nil
            }, onCancel: {
                showSetup = false
                setupVM = nil
            })
        } else if let folder = changeDestinationFolder, let vm = changeDestinationVM {
            DestinationPickerView(viewModel: vm, confirmLabel: "Set Destination", onConfirm: {
                var updated = folder
                updated.destinationFolderId = vm.destinationParentId
                updated.destinationFolderName = vm.destinationLabel
                manager.store.update(updated)
                changeDestinationFolder = nil
                changeDestinationVM = nil
            }, onCancel: {
                changeDestinationFolder = nil
                changeDestinationVM = nil
            })
        } else {
            folderList
        }
    }

    @ViewBuilder
    private var folderList: some View {
        VStack(spacing: 0) {
            if manager.store.folders.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.store.folders) { folder in
                            WatchedFolderRow(
                                folder: folder,
                                syncStatuses: manager.syncStatuses[folder.localPath] ?? [],
                                onToggle: { enabled in
                                    var updated = folder
                                    updated.enabled = enabled
                                    manager.store.update(updated)
                                    if enabled {
                                        manager.startWatching(updated)
                                    } else {
                                        manager.stopWatching(localPath: folder.localPath)
                                    }
                                },
                                onRemove: {
                                    manager.stopWatching(localPath: folder.localPath)
                                    manager.historyStore.removeHistory(forWatchedFolder: folder.localPath)
                                    manager.store.remove(localPath: folder.localPath)
                                },
                                onChangeSource: {
                                    changeSourceFolder(for: folder)
                                },
                                onChangeDestination: {
                                    startDestinationChange(for: folder)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }

                Spacer()

                addButton
            }
        }
    }

    private var addButton: some View {
        Button(action: startSetup) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                Text("Add Watched Folder")
            }
        }
        .buttonStyle(.cta)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            FolderDGI()

            Text("Automatically upload new files added to a folder on your computer")
                .font(Font.companion(size: 13))
                .foregroundStyle(Color.companionMutedText)
                .multilineTextAlignment(.center)

            Button("Add Watched Folder", action: startSetup)
                .buttonStyle(.cta)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Actions

    private func startSetup() {
        let existingPaths = Set(manager.store.folders.map(\.localPath))
        let vm = WatchedFolderSetupViewModel(
            apiClient: uploadManager.apiClient,
            existingWatchedPaths: existingPaths
        )
        setupVM = vm
        showSetup = true
        Task { await vm.loadWorkspaces() }
    }

    private func startDestinationChange(for folder: WatchedFolder) {
        let vm = DestinationPickerViewModel(apiClient: uploadManager.apiClient)
        changeDestinationVM = vm
        changeDestinationFolder = folder
        Task {
            await vm.loadWorkspaces()
            if let ws = vm.workspaces.first(where: { $0.id == folder.workspaceId }) {
                await vm.selectWorkspace(ws)
                if let proj = vm.projects.first(where: { $0.id == folder.transfersyncProjectId }) {
                    await vm.selectProject(proj)
                }
            }
        }
    }

    private func changeSourceFolder(for folder: WatchedFolder) {
        panelManager?.suspendClickMonitoring()
        NSApp.activate()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the source folder for \(folder.projectName)"

        panel.begin { response in
            Task { @MainActor in
                panelManager?.resumeClickMonitoring()

                guard response == .OK, let url = panel.url else { return }

                // Create bookmark for security-scoped access
                guard let bookmarkData = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) else { return }

                manager.stopWatching(localPath: folder.localPath)
                manager.historyStore.removeHistory(forWatchedFolder: folder.localPath)
                manager.store.remove(localPath: folder.localPath)

                let newFolder = WatchedFolder(
                    localPath: url.path,
                    transfersyncProjectId: folder.transfersyncProjectId,
                    projectName: folder.projectName,
                    workspaceId: folder.workspaceId,
                    destinationFolderId: folder.destinationFolderId,
                    destinationFolderName: folder.destinationFolderName,
                    watchingSince: folder.watchingSince,
                    enabled: folder.enabled,
                    bookmarkData: bookmarkData
                )
                manager.store.add(newFolder)
                manager.startWatching(newFolder)
            }
        }
    }
}
