import SwiftUI
import UniformTypeIdentifiers

enum HomeTab: String, CaseIterable {
    case uploads = "Uploads"
    case watch = "Watched Folders"

    var index: Int {
        switch self {
        case .uploads: return 0
        case .watch: return 1
        }
    }
}

struct HomeView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(UploadManager.self) private var uploadManager
    @Environment(WatchedFolderManager.self) private var watchedFolderManager
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.panelManager) private var panelManager

    @State private var selectedTab: HomeTab = .uploads
    @State private var showDestinationPicker = false
    @State private var showSettings = false
    @State private var destinationPickerVM: DestinationPickerViewModel?
    @State private var isFilePickerOpen = false
    @State private var showLogoutConfirmation = false
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            if case .loggedIn(let user) = authManager.authState {
                LoggedInHeaderView(user: user, onSignOut: {
                    if uploadManager.items.contains(where: { !$0.status.isTerminal }) {
                        showLogoutConfirmation = true
                    } else {
                        performLogout()
                    }
                }, onSettings: {
                    showSettings = true
                })
            }

            if showSettings {
                SettingsView(onBack: { showSettings = false })
            } else {
                tabBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                if selectedTab == .uploads && !showDestinationPicker && uploadManager.items.contains(where: { $0.status.isTerminal }) {
                    HStack {
                        Spacer()
                        Button("Clear all") {
                            uploadManager.clearCompleted()
                        }
                        .font(Font.companion(size: 11))
                        .foregroundStyle(Color.companionMutedText)
                        .buttonStyle(.ghost)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        VStack(spacing: 0) { uploadsContent }
                            .frame(width: geo.size.width)
                        WatchedFolderListView()
                            .frame(width: geo.size.width)
                    }
                    .offset(x: -CGFloat(selectedTab.index) * geo.size.width)
                    .animation(.easeInOut(duration: 0.25), value: selectedTab)
                }
                .clipped()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            Task { await uploadManager.fetchUnresolvedCommentCounts() }
        }
        .alert("Sign out?", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("You have uploads in progress. Signing out will cancel them.")
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(Font.companion(size: 13, weight: selectedTab == tab ? .medium : .regular))
                        .foregroundStyle(selectedTab == tab ? .white : Color.companionMutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Capsule())
                        .background {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Color.companionActiveTab)
                                    .matchedGeometryEffect(id: "tab", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.companionTabBar)
        )
    }

    // MARK: - Uploads Tab

    @ViewBuilder
    private var uploadsContent: some View {
        if showDestinationPicker, let vm = destinationPickerVM {
            DestinationPickerView(viewModel: vm, onConfirm: {
                openFilePicker(vm: vm)
            }, onCancel: {
                showDestinationPicker = false
                destinationPickerVM = nil
            })
        } else if !uploadManager.items.isEmpty {
            UploadQueueView()

            Spacer()

            addButton(label: "Add Files") {
                startDestinationPicker()
            }
        } else {
            uploadsEmptyState
        }
    }

    private var uploadsEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            FileUploadDGI()

            Text("Select an upload destination to get started")
                .font(Font.companion(size: 13))
                .foregroundStyle(Color.companionMutedText)
                .multilineTextAlignment(.center)

            Button("Choose Destination", action: startDestinationPicker)
                .buttonStyle(.cta)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Shared Bottom Button

    private func addButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                Text(label)
            }
        }
        .buttonStyle(.cta)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Logout

    private func performLogout() {
        Task {
            watchedFolderManager.stopAll()
            await uploadManager.onLogout()
            await authManager.logout()
        }
    }

    // MARK: - File Picker

    private func startDestinationPicker() {
        let vm = DestinationPickerViewModel(apiClient: uploadManager.apiClient)
        destinationPickerVM = vm
        showDestinationPicker = true
        Task { await vm.loadWorkspaces() }
    }

    private func openFilePicker(vm: DestinationPickerViewModel) {
        guard !isFilePickerOpen else { return }
        guard let project = vm.selectedProject,
              let workspace = vm.selectedWorkspace else { return }

        isFilePickerOpen = true
        panelManager?.suspendClickMonitoring()

        NSApp.activate()

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = audioContentTypes
        panel.message = "Select audio files to upload to \(project.name)"

        panel.begin { response in
            Task { @MainActor in
                isFilePickerOpen = false
                panelManager?.resumeClickMonitoring()

                guard response == .OK, !panel.urls.isEmpty else { return }

                showDestinationPicker = false
                destinationPickerVM = nil

                panelManager?.show()

                await uploadManager.uploadFiles(
                    fileURLs: panel.urls,
                    projectId: project.id,
                    workspaceId: workspace.id,
                    parentFolderId: vm.destinationParentId
                )
            }
        }
    }

    private var audioContentTypes: [UTType] {
        [
            .wav, .aiff, .mp3,
            UTType("public.flac") ?? .audio,
            UTType("com.apple.m4a-audio") ?? .audio,
            UTType("org.xiph.ogg-audio") ?? .audio,
            UTType("org.opus-codec") ?? .audio,
            UTType("com.apple.coreaudio-format") ?? .audio,
        ]
    }
}
