import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "FSEventStream")

struct FSEvent {
    let path: String
    let flags: FSEventStreamEventFlags

    var isFile: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
    }

    var isCreated: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
    }

    var isRenamed: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
    }

    var isModified: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemModified) != 0
    }

    var isRemoved: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
    }

    var isRootChanged: Bool {
        flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0
    }
}

/// Wraps the C FSEvents API and vends events through an AsyncStream.
final class FSEventStreamWrapper: @unchecked Sendable {
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "tomaddison.transfersync.fsevents", qos: .utility)
    private var continuation: AsyncStream<FSEvent>.Continuation?
    private let path: String

    let events: AsyncStream<FSEvent>

    init(path: String) {
        self.path = path

        let (stream, cont) = AsyncStream<FSEvent>.makeStream()
        self.events = stream
        self.continuation = cont
    }

    func start() {
        let pathCF = path as CFString
        let pathsToWatch = [pathCF] as CFArray

        // Store a raw pointer to the continuation for the C callback.
        // The continuation is retained by self, so the pointer remains valid while self is alive.
        let continuationPtr = Unmanaged.passUnretained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: continuationPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            logger.error("Failed to create FSEventStream for path: \(self.path)")
            continuation?.finish()
            return
        }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        logger.info("FSEventStream started for: \(self.path)")
    }

    func stop() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
            logger.info("FSEventStream stopped for: \(self.path)")
        }
        continuation?.finish()
        continuation = nil
    }

    fileprivate func sendEvent(_ event: FSEvent) {
        logger.debug("FSEvent: \(event.path) flags=\(event.flags) isFile=\(event.isFile) created=\(event.isCreated) renamed=\(event.isRenamed) modified=\(event.isModified)")
        continuation?.yield(event)
    }

    deinit {
        stop()
    }
}

/// C callback bridging FSEvents to the AsyncStream continuation.
private func fsEventCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let wrapper = Unmanaged<FSEventStreamWrapper>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    // eventPaths is a CFArray of CFString when using kFSEventStreamCreateFlagUseCFTypes
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()

    for i in 0..<numEvents {
        let cfPath = unsafeBitCast(CFArrayGetValueAtIndex(paths, i), to: CFString.self)
        let path = cfPath as String
        let flags = eventFlags[i]
        let event = FSEvent(path: path, flags: flags)
        wrapper.sendEvent(event)
    }
}
