import Darwin
import Foundation

public struct OrbitExternalFeedLoaderPolicy: Codable, Equatable, Sendable {
    /// Conservative per-file byte ceiling. The loader never reads more than
    /// `maxBytes + 1` bytes and rejects anything larger. Defaults to the
    /// observation policy ceiling so loader and parser agree out of the box.
    public let maxBytes: Int

    public init(maxBytes: Int = OrbitExternalObservationPolicy().maxBytes) {
        self.maxBytes = max(1, maxBytes)
    }
}

public enum OrbitExternalFeedLoaderError: Error, Equatable, Sendable {
    case notAFileURL
    case symlink
    case directory
    case notRegularFile
    case missingOrUnreadable
    case exceedsMaxBytes
}

public enum OrbitExternalFeedLoadError: Error, Equatable, Sendable {
    case loader(OrbitExternalFeedLoaderError)
    case ingress(OrbitExternalObservationIngressError)
}

/// Compile-time contract for the loader boundary: caller-supplied explicit
/// file URLs only. The loader never discovers paths, scans directories,
/// launches processes, opens sockets, uses credentials, or executes actions.
public enum OrbitExternalFeedLoaderAuthority {
    public static let requiresExplicitFileURL = true
    public static let readsRegularFilesOnly = true
    public static let discoversPaths = false
    public static let ownsProcess = false
    public static let ownsNetwork = false
    public static let ownsSockets = false
    public static let usesCredentials = false
    public static let executesActions = false
}

/// Explicit-file feed loader. The caller authorizes one concrete local file
/// URL per call plus the feed kind it represents; the loader returns bounded
/// bytes and stays separate from the byte-only `OrbitExternalObservationHost`.
///
/// Enforcement:
/// - regular files only: symlinks, directories, sockets, FIFOs, and devices
///   are rejected (pre-checked via resource values, re-verified race-free with
///   `O_NOFOLLOW` + `fstat`);
/// - bounded read: at most `maxBytes + 1` bytes are ever read; files over the
///   limit fail closed, both via the pre-read size check and the read cap;
/// - the host keeps its own parser max-byte enforcement, one-owner, backoff,
///   watchdog, and emergency-stop policy — the loader changes none of it.
public enum OrbitExternalFeedLoader {
    /// Reads up to `policy.maxBytes` bytes from an explicit caller-authorized
    /// local file. The `feed` is part of the caller's explicit contract; the
    /// loader itself is byte-only and never inspects content.
    public static func load(
        feed: OrbitExternalFeedKind,
        fileURL: URL,
        policy: OrbitExternalFeedLoaderPolicy = OrbitExternalFeedLoaderPolicy()
    ) -> Result<Data, OrbitExternalFeedLoaderError> {
        _ = feed
        guard fileURL.isFileURL else { return .failure(.notAFileURL) }

        let resourceKeys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
            return .failure(.missingOrUnreadable)
        }
        if values.isSymbolicLink == true { return .failure(.symlink) }
        if values.isDirectory == true { return .failure(.directory) }
        if values.isRegularFile == false { return .failure(.notRegularFile) }

        let path = fileURL.path(percentEncoded: false)
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else {
            return .failure(errno == ELOOP ? .symlink : .missingOrUnreadable)
        }
        defer { close(fd) }

        var status = stat()
        guard fstat(fd, &status) == 0 else { return .failure(.missingOrUnreadable) }
        guard (status.st_mode & S_IFMT) == S_IFREG else { return .failure(.notRegularFile) }
        guard status.st_size <= Int64(policy.maxBytes) else { return .failure(.exceedsMaxBytes) }

        var data = Data()
        data.reserveCapacity(min(Int(status.st_size), policy.maxBytes))
        var buffer = [UInt8](repeating: 0, count: min(65_536, policy.maxBytes + 1))
        while data.count <= policy.maxBytes {
            let remaining = policy.maxBytes + 1 - data.count
            let readCount = buffer.withUnsafeMutableBytes { pointer -> Int in
                read(fd, pointer.baseAddress, min(pointer.count, remaining))
            }
            if readCount < 0 {
                if errno == EINTR { continue }
                return .failure(.missingOrUnreadable)
            }
            if readCount == 0 { break }
            data.append(contentsOf: buffer.prefix(readCount))
        }
        guard data.count <= policy.maxBytes else { return .failure(.exceedsMaxBytes) }
        return .success(data)
    }

    /// Loads an explicit caller-authorized file and hands the bounded bytes to
    /// the host's existing byte-only ingress exactly once. Loader failures
    /// never touch host runtime state; ingress failures (owner conflict,
    /// backoff, stopped, resource limit) are reported through the host's own
    /// policy unchanged.
    public static func ingestFromFile(
        feed: OrbitExternalFeedKind,
        fileURL: URL,
        host: inout OrbitExternalObservationHost,
        ownerID: String,
        now: Date = .now,
        policy: OrbitExternalFeedLoaderPolicy = OrbitExternalFeedLoaderPolicy()
    ) -> Result<OrbitExternalObservationReport, OrbitExternalFeedLoadError> {
        switch load(feed: feed, fileURL: fileURL, policy: policy) {
        case let .failure(error):
            return .failure(.loader(error))
        case let .success(data):
            switch host.ingest(feed: feed, data: data, ownerID: ownerID, now: now) {
            case let .success(report):
                return .success(report)
            case let .failure(error):
                return .failure(.ingress(error))
            }
        }
    }
}
