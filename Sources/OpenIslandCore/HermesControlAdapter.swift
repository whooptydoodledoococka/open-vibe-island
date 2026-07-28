import Foundation

public enum HermesControlError: Error, Equatable, Sendable {
    case nonLoopbackURL
    case invalidIdentifier
    case invalidText
    case unauthorized
    case stale
    case rejected
    case unavailable
    case invalidResponse
    case resourceLimit
}

public enum HermesApprovalChoice: String, Codable, Sendable {
    case once
    case session
    case always
    case deny
}

public struct HermesPendingApproval: Decodable, Equatable, Sendable {
    public let approvalID: String?
    public let command: String?
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case approvalID = "approval_id"
        case command
        case description
    }
}

public struct HermesApprovalPendingResponse: Decodable, Equatable, Sendable {
    public let pending: HermesPendingApproval?
    public let pendingCount: Int?

    enum CodingKeys: String, CodingKey {
        case pending
        case pendingCount = "pending_count"
    }
}

public struct HermesApprovalRespondResponse: Decodable, Equatable, Sendable {
    public let ok: Bool?
    public let choice: HermesApprovalChoice?
    public let staleCleared: Bool?
    public let relayed: Bool?
    public let stale: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case choice
        case staleCleared = "stale_cleared"
        case relayed
        case stale
    }
}

public struct HermesSteerResponse: Decodable, Equatable, Sendable {
    public let accepted: Bool?
    public let fallback: String?
    public let streamID: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case accepted
        case fallback
        case streamID = "stream_id"
        case error
    }
}

public struct HermesCancelResponse: Decodable, Equatable, Sendable {
    public let ok: Bool?
    public let cancelled: Bool?
    public let streamID: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case cancelled
        case streamID = "stream_id"
        case error
    }
}

public struct HermesStreamStatusResponse: Decodable, Equatable, Sendable {
    public let active: Bool?
    public let streamID: String?
    public let replayAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case active
        case streamID = "stream_id"
        case replayAvailable = "replay_available"
    }
}

/// Cookie-authenticated, loopback-only control surface for Hermes WebUI.
///
/// Orbit never reads, persists, logs, or manufactures Hermes credentials.
/// The injected URLSession owns cookie handling, matching Hermes's documented
/// client contract. All identifiers and response bodies are bounded.
public actor HermesControlAdapter {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:8787")!

    private let baseURL: URL
    private let urlSession: URLSession
    private let maxResponseBytes: Int

    public init(
        baseURL: URL = HermesControlAdapter.defaultBaseURL,
        urlSession: URLSession = .shared,
        maxResponseBytes: Int = 256 * 1_024
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.maxResponseBytes = max(1_024, maxResponseBytes)
    }

    public func pendingApproval(
        sessionID: String
    ) async -> Result<HermesApprovalPendingResponse, HermesControlError> {
        guard let sessionID = Self.safeIdentifier(sessionID) else {
            return .failure(.invalidIdentifier)
        }
        return await get(
            path: "api/approval/pending",
            query: [URLQueryItem(name: "session_id", value: sessionID)]
        )
    }

    public func respondApproval(
        sessionID: String,
        approvalID: String?,
        choice: HermesApprovalChoice
    ) async -> Result<HermesApprovalRespondResponse, HermesControlError> {
        guard let sessionID = Self.safeIdentifier(sessionID) else {
            return .failure(.invalidIdentifier)
        }
        let safeApprovalID = approvalID.flatMap(Self.safeIdentifier)
        guard approvalID == nil || safeApprovalID != nil else {
            return .failure(.invalidIdentifier)
        }
        let body = ApprovalRespondRequest(
            sessionID: sessionID,
            choice: choice,
            approvalID: safeApprovalID
        )
        let result: Result<HermesApprovalRespondResponse, HermesControlError> =
            await post(path: "api/approval/respond", body: body)
        guard case let .success(response) = result else { return result }
        if response.stale == true { return .failure(.stale) }
        return response.ok == true ? result : .failure(.rejected)
    }

    public func steer(
        sessionID: String,
        text: String
    ) async -> Result<HermesSteerResponse, HermesControlError> {
        guard let sessionID = Self.safeIdentifier(sessionID) else {
            return .failure(.invalidIdentifier)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 4_096 else {
            return .failure(.invalidText)
        }
        let result: Result<HermesSteerResponse, HermesControlError> =
            await post(path: "api/chat/steer", body: SteerRequest(sessionID: sessionID, text: trimmed))
        guard case let .success(response) = result else { return result }
        return response.accepted == true ? result : .failure(.rejected)
    }

    public func cancel(
        streamID: String
    ) async -> Result<HermesCancelResponse, HermesControlError> {
        guard let streamID = Self.safeIdentifier(streamID) else {
            return .failure(.invalidIdentifier)
        }
        let result: Result<HermesCancelResponse, HermesControlError> = await get(
            path: "api/chat/cancel",
            query: [URLQueryItem(name: "stream_id", value: streamID)]
        )
        guard case let .success(response) = result else { return result }
        return response.ok == true && response.cancelled == true ? result : .failure(.rejected)
    }

    public func streamStatus(
        streamID: String
    ) async -> Result<HermesStreamStatusResponse, HermesControlError> {
        guard let streamID = Self.safeIdentifier(streamID) else {
            return .failure(.invalidIdentifier)
        }
        return await get(
            path: "api/chat/stream/status",
            query: [URLQueryItem(name: "stream_id", value: streamID)]
        )
    }

    private func get<Response: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async -> Result<Response, HermesControlError> {
        guard let request = request(path: path, query: query) else {
            return .failure(.nonLoopbackURL)
        }
        return await execute(request)
    }

    private func post<Body: Encodable, Response: Decodable & Sendable>(
        path: String,
        body: Body
    ) async -> Result<Response, HermesControlError> {
        guard var request = request(path: path) else {
            return .failure(.nonLoopbackURL)
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONEncoder().encode(body) else {
            return .failure(.invalidResponse)
        }
        request.httpBody = data
        return await execute(request)
    }

    private func execute<Response: Decodable & Sendable>(
        _ request: URLRequest
    ) async -> Result<Response, HermesControlError> {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            switch response.statusCode {
            case 200..<300:
                break
            case 401, 403:
                return .failure(.unauthorized)
            case 409:
                return .failure(.stale)
            default:
                return .failure(.unavailable)
            }
            guard data.count <= maxResponseBytes else {
                return .failure(.resourceLimit)
            }
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                return .failure(.invalidResponse)
            }
            return .success(decoded)
        } catch {
            return .failure(.unavailable)
        }
    }

    private func request(
        path: String,
        query: [URLQueryItem] = []
    ) -> URLRequest? {
        guard HermesGatewayAdapter.isLoopback(baseURL) else { return nil }
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { return nil }
        return URLRequest(url: url)
    }

    private static func safeIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 256 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        return trimmed.unicodeScalars.allSatisfy(allowed.contains) ? trimmed : nil
    }
}

private struct ApprovalRespondRequest: Encodable {
    let sessionID: String
    let choice: HermesApprovalChoice
    let approvalID: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case choice
        case approvalID = "approval_id"
    }
}

private struct SteerRequest: Encodable {
    let sessionID: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case text
    }
}
