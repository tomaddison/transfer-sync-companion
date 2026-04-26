# TransferSync Companion

A macOS menu bar app that auto-uploads files from local folders to a cloud service. Each watched folder is mapped to a destination in the service's workspace/project/folder hierarchy; any file dropped into that folder is uploaded to that destination automatically.

The remote hierarchy is fetched from a Supabase-authenticated REST API. Files are uploaded directly to S3 using short-lived presigned URLs minted by the backend.

<img width="1400" height="735" alt="hero" src="https://github.com/user-attachments/assets/8d607dc3-6f38-43b5-9baa-2fd6645ea0db" />

## Features

- **Browser-based auth** - Supabase OAuth with a CSRF-protected `transfersync://` callback URL. Tokens persisted in Keychain via the Supabase SDK.
- **Hierarchy picker** - Navigates the user's workspaces, projects, and folders from the backend to pick an upload destination for each watched local folder.
- **Folder watching** - Any number of local folders, each with its own file-extension filter.
- **Stable-write detection** - FSEvents triggers a debounced size-stability check before upload, so files still being written (e.g. a DAW bounce in progress) are not uploaded mid-write.
- **Direct-to-S3 uploads** - Presigned URLs from the backend, single PUT for small files, parallel multipart (10 MB parts, 3 concurrent) for large ones. Runs on a background `URLSession` so transfers survive app restart.
- **Finder badges** - Per-file upload status surfaced via a Finder Sync extension, with state shared over an App Group container and Darwin notifications.
- **Resilient retries** - Exponential backoff on failures; the upload log persists to disk and is restored on relaunch independently of auth state.

## Architecture

- **Menu bar app** - SwiftUI rendered inside a custom non-activating `NSPanel`, so opening it does not steal focus from the active app.
- **Finder Sync extension** - Separate target. Reads sync status from the shared App Group container and renders Finder badges on watched files.
- **IPC** - App Group shared `UserDefaults` for state, Darwin notifications for live updates between the two processes.
- **Upload pipeline** - `WatchedFolderManager` (FSEvents + debouncing) hands off to `UploadManager` (queue, retries, status), which calls `S3UploadService` (PUT or multipart), then notifies the backend via a `complete-upload` callback.
- **Config injection** - Per-build-config xcconfig files inject Supabase URL, anon key, and API base URL into Info.plist at build time. Real values are gitignored.

See [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md) for the full module layout.

## Tech

Swift, SwiftUI, AppKit (`NSPanel`, `NSStatusBar`), Supabase Swift SDK, Keychain, FSEvents, App Groups, Darwin notifications, multipart S3 uploads, `URLSession` background config, `SMAppService` (launch at login).

## Run locally

A backend is required that:
1. Authenticates users via Supabase.
2. Exposes REST endpoints to list the user's workspaces, the projects in a workspace, and the folders in a project.
3. Exposes an endpoint that returns a presigned S3 upload URL (single or multipart) for a given filename and destination.
4. Exposes a `complete-upload` endpoint to mark uploads done.

To run against a local backend:

1. Clone the repo.
2. Copy the xcconfig templates. The real ones are gitignored:
   ```
   cp Configs/Debug.example.xcconfig   Configs/Debug.xcconfig
   cp Configs/Staging.example.xcconfig Configs/Staging.xcconfig
   cp Configs/Release.example.xcconfig Configs/Release.xcconfig
   ```
3. Fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL`, and `WEB_BASE_URL` in `Debug.xcconfig` to point at the local stack.
4. Add `transfersync://auth/callback` to the Supabase project's allowed redirect URLs (Auth, URL Configuration).
5. Open `TransferSyncCompanion.xcodeproj` in Xcode and run the **Debug** scheme.

To build against staging or prod, edit the scheme (Product, Scheme, Edit Scheme, Run, Build Configuration) and pick **Staging** or **Release**, with matching values filled into the respective xcconfig file.

## Project structure

```
TransferSyncCompanion/         Main app (SwiftUI + AppKit)
  App/                         App entry, root view, menu bar, build-time constants
  Services/                    Side-effect singletons (connectivity, notifications)
  Networking/                  APIClient + Supabase wiring
  Features/                    Auth, Home, Settings, Upload, WatchedFolder
  Components/                  Reusable UI (button styles, loading, error banner, sizing)
  Extensions/                  Color and Font extensions
  Models/                      Domain types
TransferSyncFinderSync/        Finder Sync extension target
TransferSyncCompanionTests/    Unit tests
Shared/                        Code shared between app + extension
Configs/                       Per-build-config xcconfig files
Docs/                          ARCHITECTURE.md
```

## Notes

Real keys and project URLs live in gitignored `Configs/*.xcconfig` files. See `Configs/*.example.xcconfig` for the expected shape. The app will launch once the `REPLACE_ME` placeholders are replaced with the required values.
