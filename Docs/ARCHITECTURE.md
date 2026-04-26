# Architecture

The macOS target is organised by feature. Shell-level wiring lives in `App/`, side-effect singletons in `Services/`, network code in `Networking/`, reusable views in `Components/`, and cross-cutting helpers in `Extensions/`. Code shared between the main app and the Finder Sync extension lives in the top-level `Shared/` directory.

```
TransferSyncCompanion/
├── App/                            # App shell
│   ├── TransferSyncCompanionApp.swift  # Entry point, environment objects
│   ├── ContentView.swift               # Auth-state router
│   ├── FinderSyncGate.swift            # Permission gate for the Finder Sync extension
│   ├── MenuBarPanelManager.swift       # Non-activating NSPanel host
│   ├── MenuBarPanel.swift              # NSPanel subclass
│   ├── MenuBarIconManager.swift        # NSStatusItem icon and click handling
│   └── AppConstants.swift              # Build-time config injection (Supabase, API base URL)
│
├── Services/                       # Side-effect singletons
│   ├── ConnectivityManager.swift   # Network reachability
│   └── NotificationManager.swift   # macOS user notifications
│
├── Networking/                     # REST client and Supabase wiring
│   ├── APIClient.swift             # Core HTTP client
│   ├── APIClient+*.swift           # Per-resource extensions (Uploads, Folders, Projects, ...)
│   ├── APIError.swift
│   ├── SupabaseClientFactory.swift
│   └── UploadAPIClient.swift       # Protocol surface that UploadManager depends on
│
├── Models/                         # Domain types decoded from the API
│
├── Components/                     # Reusable SwiftUI views
│   ├── CompanionTheme.swift        # Numeric sizing constants
│   ├── CTAButtonStyle.swift
│   ├── GhostButtonStyle.swift
│   ├── DarkMenu.swift
│   ├── ErrorBanner.swift
│   ├── EmptyStateGraphics.swift
│   └── LoadingView.swift
│
├── Extensions/
│   ├── Color+Companion.swift       # Named colour palette + hex init
│   └── Font+Companion.swift        # Typography helper
│
├── Features/
│   ├── Auth/                       # Login flow, AuthManager, auth state
│   ├── Home/                       # Logged-in home view (tabs, header)
│   ├── Settings/                   # Preferences screen and store
│   ├── Upload/                     # Destination picker, upload queue UI, UploadManager + S3 service
│   └── WatchedFolder/              # FSEvents watcher, file stability check, auto-stack matcher, list UI
│
├── Resources/Fonts/                # Bundled fonts
├── Assets.xcassets/
└── Info.plist

TransferSyncFinderSync/             # Finder Sync extension target (separate process)
Shared/                             # Code shared between the main app and the extension
TransferSyncCompanionTests/         # Unit tests
Configs/                            # Per-build-config xcconfig files (real ones gitignored)
```

## Process model

Two processes coordinate over an App Group container:

- **Main app.** SwiftUI rendered inside a non-activating `NSPanel`. Owns auth, the upload queue, FSEvents watching, and writes per-file sync status into shared `UserDefaults`.
- **Finder Sync extension.** A separate target launched by Finder. Reads sync status from the shared container and renders Finder badges on watched files.

Live updates between the two processes use Darwin notifications; status state is persisted in App Group `UserDefaults` via `SyncStatusStore` (in `Shared/`).

## Upload pipeline

`WatchedFolderManager` (FSEvents + debouncing + stability check) hands off to `UploadManager` (queue, retries, status), which calls `S3UploadService` (single PUT or parallel multipart), then notifies the backend via a `complete-upload` callback. Backend status transitions arrive over Supabase Realtime via `RealtimeManager`.
