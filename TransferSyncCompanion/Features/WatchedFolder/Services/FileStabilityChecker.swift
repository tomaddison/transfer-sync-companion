import Darwin
import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "FileStabilityChecker")

enum FileStabilityError: Error {
 case fileDisappeared
 case cancelled
 case timeout
}

/// Detects when a file has finished being written to disk using kqueue vnode events.
/// DAW bounces can take seconds to write; FSEvents fires on creation, not completion.
/// Uses DispatchSource (kqueue EVFILT_VNODE) to watch for write cessation, with
/// size-polling as a fallback if the file descriptor cannot be opened.
enum FileStabilityChecker {

 // MARK: - Public API

 /// Waits until the file has finished being written.
 ///
 /// Opens the file with `O_EVTONLY` and watches for kqueue write/extend events.
 /// When no write events have been received for `debounceInterval`, the file is
 /// considered stable. Falls back to size-polling if the fd cannot be opened.
 ///
 /// - Parameters:
 /// - path: Absolute file path to monitor.
 /// - debounceInterval: Seconds of write silence required. Default 1.0s.
 /// - timeout: Maximum wait time in seconds. Default 300s (5 minutes).
 /// - Returns: The final stable file size in bytes.
 static func waitForStableSize(
 at path: String,
 debounceInterval: TimeInterval = 1.0,
 timeout: TimeInterval = 300
 ) async throws -> Int {
 let fd = Darwin.open(path, O_EVTONLY)
 if fd == -1 {
 logger.warning("Cannot open O_EVTONLY fd for \(path) (errno \(errno)), falling back to polling")
 return try await waitForStableSizePolling(at: path)
 }

 logger.info("Using DispatchSource stability check for: \(path)")
 return try await waitForStableSizeDispatchSource(
 at: path,
 fd: fd,
 debounceInterval: debounceInterval,
 timeout: timeout
 )
 }

 // MARK: - DispatchSource Implementation

 /// Reference type that coordinates the DispatchSource, timers, and continuation
 /// on a serial queue. `@unchecked Sendable` is safe because all mutation happens
 /// exclusively on `queue`.
 private final class Monitor: @unchecked Sendable {
 enum State { case monitoring, resolved }

 let queue: DispatchQueue
 let fd: Int32
 let path: String
 let debounceInterval: TimeInterval

 var state: State = .monitoring
 var source: DispatchSourceFileSystemObject?
 var debounceTimer: DispatchSourceTimer?
 var timeoutTimer: DispatchSourceTimer?
 var continuation: CheckedContinuation<Int, Error>?

 init(fd: Int32, path: String, debounceInterval: TimeInterval) {
 self.queue = DispatchQueue(label: "tomaddison.transfersync.file-stability.\(fd)")
 self.fd = fd
 self.path = path
 self.debounceInterval = debounceInterval
 }

 /// Resume the continuation exactly once and clean up all resources.
 /// Must be called on `queue`.
 func finish(with result: Result<Int, Error>) {
 dispatchPrecondition(condition: .onQueue(queue))
 guard state == .monitoring else { return }
 state = .resolved
 debounceTimer?.cancel()
 timeoutTimer?.cancel()
 source?.cancel()
 Darwin.close(fd)
 continuation?.resume(with: result)
 continuation = nil
 }

 /// Reset the debounce timer. Called on each write/extend event and once at
 /// startup. Must be called on `queue`.
 func resetDebounceTimer() {
 dispatchPrecondition(condition: .onQueue(queue))
 debounceTimer?.cancel()
 let timer = DispatchSource.makeTimerSource(queue: queue)
 timer.schedule(deadline: .now() + debounceInterval)
 timer.setEventHandler { [self] in
 guard state == .monitoring else { return }
 guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
 let size = attrs[.size] as? Int else {
 logger.debug("File disappeared after debounce: \(self.path)")
 finish(with: .failure(FileStabilityError.fileDisappeared))
 return
 }
 logger.debug("File stable (no writes for \(self.debounceInterval)s) at \(size) bytes: \(self.path)")
 finish(with: .success(size))
 }
 debounceTimer = timer
 timer.resume()
 }

 /// Thread-safe cancellation entry point for `withTaskCancellationHandler`.
 func cancel() {
 queue.async { [self] in
 finish(with: .failure(CancellationError()))
 }
 }
 }

 private static func waitForStableSizeDispatchSource(
 at path: String,
 fd: Int32,
 debounceInterval: TimeInterval,
 timeout: TimeInterval
 ) async throws -> Int {
 let monitor = Monitor(fd: fd, path: path, debounceInterval: debounceInterval)

 return try await withTaskCancellationHandler {
 try await withCheckedThrowingContinuation { continuation in
 monitor.queue.async {
 monitor.continuation = continuation

 // File system event source
 let source = DispatchSource.makeFileSystemObjectSource(
 fileDescriptor: fd,
 eventMask: [.write, .extend, .delete, .rename, .revoke],
 queue: monitor.queue
 )
 monitor.source = source

 source.setEventHandler { [monitor] in
 guard monitor.state == .monitoring else { return }
 let event = source.data

 if event.contains(.delete) || event.contains(.rename) || event.contains(.revoke) {
 logger.debug("File disappeared during stability check: \(path)")
 monitor.finish(with: .failure(FileStabilityError.fileDisappeared))
 return
 }

 // .write or .extend - file is still being written
 logger.debug("Write event on \(path), resetting debounce timer")
 monitor.resetDebounceTimer()
 }

 // Overall timeout
 let timeoutTimer = DispatchSource.makeTimerSource(queue: monitor.queue)
 timeoutTimer.schedule(deadline: .now() + timeout)
 timeoutTimer.setEventHandler { [monitor] in
 logger.warning("Stability check timed out after \(timeout)s: \(path)")
 monitor.finish(with: .failure(FileStabilityError.timeout))
 }
 monitor.timeoutTimer = timeoutTimer
 timeoutTimer.resume()

 // Start watching and kick off initial debounce
 source.resume()
 monitor.resetDebounceTimer()
 }
 }
 } onCancel: {
 monitor.cancel()
 }
 }

 // MARK: - Polling Fallback

 /// Original size-polling implementation, kept as a fallback when O_EVTONLY fails.
 private static func waitForStableSizePolling(
 at path: String,
 pollInterval: TimeInterval = 0.5,
 requiredStablePolls: Int = 3
 ) async throws -> Int {
 var previousSize: Int?
 var stableCount = 0

 while true {
 try Task.checkCancellation()

 guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
 let currentSize = attrs[.size] as? Int else {
 throw FileStabilityError.fileDisappeared
 }

 if let prev = previousSize, currentSize == prev {
 stableCount += 1
 if stableCount >= requiredStablePolls {
 logger.debug("File stable (polling) at \(currentSize) bytes: \(path)")
 return currentSize
 }
 } else {
 stableCount = 1
 previousSize = currentSize
 }

 try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
 }
 }
}
