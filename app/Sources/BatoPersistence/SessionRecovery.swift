import Foundation
import Darwin

public struct AbnormalTermination: Equatable, Sendable {
    /// When the session that did not quit cleanly started.
    public let previousStart: Date
    /// False when that session never reached `confirmLaunch`, so the launch itself may be what fails.
    public let previousLaunchConfirmed: Bool
    /// Consecutive abnormal terminations without a confirmed launch between them, at least 1.
    public let consecutiveFailures: Int
    public var isRepeating: Bool { consecutiveFailures >= 2 }
}

public enum LaunchStatus: Equatable, Sendable {
    case clean
    case abnormal(AbnormalTermination)
    /// Another live Bato process owns the marker, so this launch neither judges nor claims it.
    case concurrent
}

/// Detects abnormal termination with a marker written at launch and removed on clean quit, and keeps
/// the previous recovery snapshot until a later launch is confirmed.
///
/// The session start is captured at launch into a pending slot; the recovery snapshot
/// (`BackupStore.lastSessionID`) is replaced only when `confirmLaunch` promotes it. A launch that
/// crashes before confirming never overwrites it, and nothing here relaunches or restores on its own, so a
/// crashing launch cannot loop.
public final class RecoveryCoordinator {
    private struct Marker: Codable {
        var processID: Int32
        var startedAt: Date
        var confirmed: Bool
        var failures: Int
    }

    private let markerURL: URL
    private let backups: BackupStore
    private let processID: Int32
    private let isProcessAlive: (Int32) -> Bool
    private let bootDate: () -> Date
    private let now: () -> Date
    private var marker: Marker?
    private var capturedSessionStart = false

    public init(directory: URL, backups: BackupStore, processID: Int32 = getpid(),
                isProcessAlive: @escaping (Int32) -> Bool = RecoveryCoordinator.processExists,
                bootDate: @escaping () -> Date = RecoveryCoordinator.systemBootDate,
                now: @escaping () -> Date = Date.init) {
        markerURL = directory.appendingPathComponent("session.marker")
        self.backups = backups
        self.processID = processID
        self.isProcessAlive = isProcessAlive
        self.bootDate = bootDate
        self.now = now
    }

    public static func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func systemBootDate() -> Date {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }

    /// Call once per launch, before the organization is read. An unreadable marker counts as abnormal.
    public func beginLaunch() -> LaunchStatus {
        let previous = readMarker()
        var status = LaunchStatus.clean
        var failures = 0
        switch previous {
        case .absent: break
        case .present(let old):
            // A recycled PID from before the last boot cannot be a live Bato.
            if old.processID != processID, old.startedAt >= bootDate(), isProcessAlive(old.processID) { return .concurrent }
            failures = old.confirmed ? 1 : old.failures + 1
            status = .abnormal(AbnormalTermination(previousStart: old.startedAt, previousLaunchConfirmed: old.confirmed,
                                                   consecutiveFailures: failures))
        case .unreadable:
            failures = 1
            status = .abnormal(AbnormalTermination(previousStart: .distantPast, previousLaunchConfirmed: false,
                                                   consecutiveFailures: 1))
        }
        let current = Marker(processID: processID, startedAt: now(), confirmed: false, failures: failures)
        marker = current
        // A marker that cannot be written only loses detection for this session.
        writeMarker(current)
        return status
    }

    /// Records the organization as this session found it. Call after it is loaded (and after any restore),
    /// before the user can edit it. The copy only becomes the recovery snapshot at `confirmLaunch`.
    @discardableResult
    public func captureSessionStart(organization: Data, files: [String: Data]) -> BackupError? {
        capturedSessionStart = false
        do { try backups.capturePendingSession(organization: organization, files: files) }
        catch { return (error as? BackupError) ?? .writeFailed }
        capturedSessionStart = true
        return nil
    }

    /// The launch worked: this session's start becomes the recovery snapshot, and today's daily backup is
    /// taken from `organization`. Call only after any recovery offer is resolved, because this replaces the
    /// snapshot the offer refers to. Every step is attempted; the first failure is returned.
    @discardableResult
    public func confirmLaunch(organization: Data?, files: [String: Data]) -> BackupError? {
        guard var current = marker else { return nil }
        current.confirmed = true
        current.failures = 0
        marker = current
        writeMarker(current)
        var failure: BackupError?
        if capturedSessionStart {
            do { try backups.promotePendingSession() }
            catch { failure = (error as? BackupError) ?? .writeFailed }
        }
        if let organization {
            do { try backups.captureDaily(organization: organization, files: files) }
            catch { failure = failure ?? (error as? BackupError) ?? .writeFailed }
        }
        backups.prune()
        return failure
    }

    /// Clean quit. Idempotent, and leaves another process's marker alone.
    public func endCleanly() {
        guard let current = marker, current.processID == processID else { return }
        try? FileManager.default.removeItem(at: markerURL)
        marker = nil
    }

    private enum MarkerRead { case absent, present(Marker), unreadable }

    private func readMarker() -> MarkerRead {
        var info = stat()
        guard lstat(markerURL.path, &info) == 0 else { return .absent }
        guard info.st_mode & S_IFMT == S_IFREG, let bytes = try? Data(contentsOf: markerURL) else { return .unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(Marker.self, from: bytes) else { return .unreadable }
        return .present(decoded)
    }

    private func writeMarker(_ marker: Marker) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let bytes = try? encoder.encode(marker) else { return }
        try? FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? bytes.write(to: markerURL, options: .atomic)
    }
}
