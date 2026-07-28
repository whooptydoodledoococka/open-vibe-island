import Foundation
import Testing
@testable import OpenIslandCore

@Suite(.serialized)
struct HermesControlAdapterTests {
    @Test
    func pendingApprovalUsesVerifiedHermesRouteAndDecodes() async throws {
        let adapter = makeAdapter { request in
            #expect(request.url?.path == "/api/approval/pending")
            #expect(request.url?.query == "session_id=session-1")
            return response(
                request,
                status: 200,
                json: #"{"pending":{"approval_id":"approval-1","command":"swift test","description":"Run tests"},"pending_count":1}"#
            )
        }

        let result = await adapter.pendingApproval(sessionID: "session-1")
        let payload = try result.get()

        #expect(payload.pending?.approvalID == "approval-1")
        #expect(payload.pendingCount == 1)
    }

    @Test
    func approvalResponseBindsSessionApprovalAndChoice() async throws {
        let adapter = makeAdapter { request in
            #expect(request.url?.path == "/api/approval/respond")
            #expect(request.httpMethod == "POST")
            return response(
                request,
                status: 200,
                json: #"{"ok":true,"choice":"once","relayed":true}"#
            )
        }

        let result = await adapter.respondApproval(
            sessionID: "session-1",
            approvalID: "approval-1",
            choice: .once
        )

        #expect(try result.get().relayed == true)
    }

    @Test
    func steerCancelAndStatusUseDocumentedRoutes() async throws {
        let adapter = makeAdapter { request in
            switch request.url?.path {
            case "/api/chat/steer":
                return response(request, status: 200, json: #"{"accepted":true,"stream_id":"stream-1"}"#)
            case "/api/chat/cancel":
                #expect(request.url?.query == "stream_id=stream-1")
                return response(request, status: 200, json: #"{"ok":true,"cancelled":true,"stream_id":"stream-1"}"#)
            case "/api/chat/stream/status":
                return response(request, status: 200, json: #"{"active":false,"stream_id":"stream-1","replay_available":true}"#)
            default:
                return response(request, status: 404, json: #"{}"#)
            }
        }

        #expect(try await adapter.steer(sessionID: "session-1", text: "Focus on tests.").get().accepted == true)
        #expect(try await adapter.cancel(streamID: "stream-1").get().cancelled == true)
        #expect(try await adapter.streamStatus(streamID: "stream-1").get().active == false)
    }

    @Test
    func staleUnauthorizedAndMalformedResponsesFailClosed() async {
        let stale = makeAdapter { request in response(request, status: 409, json: #"{"stale":true}"#) }
        #expect(await stale.respondApproval(
            sessionID: "session-1",
            approvalID: "approval-1",
            choice: .deny
        ) == .failure(.stale))

        let unauthorized = makeAdapter { request in response(request, status: 401, json: #"{}"#) }
        #expect(await unauthorized.pendingApproval(sessionID: "session-1") == .failure(.unauthorized))

        let malformed = makeAdapter { request in response(request, status: 200, json: #"{"pending":"wrong"}"#) }
        #expect(await malformed.pendingApproval(sessionID: "session-1") == .failure(.invalidResponse))
    }

    @Test
    func nonLoopbackInvalidIdentityAndOversizedResponseFailClosed() async {
        let remote = HermesControlAdapter(baseURL: URL(string: "https://example.invalid")!)
        #expect(await remote.pendingApproval(sessionID: "session-1") == .failure(.nonLoopbackURL))

        let local = makeAdapter(
            handler: { request in
                let data = Data(repeating: 0x61, count: 2_048)
                return (HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!, data)
            },
            maxResponseBytes: 1_024
        )
        #expect(await local.pendingApproval(sessionID: "../private") == .failure(.invalidIdentifier))
        #expect(await local.pendingApproval(sessionID: "session-1") == .failure(.resourceLimit))
        #expect(await local.steer(sessionID: "session-1", text: "   ") == .failure(.invalidText))
    }

    private func makeAdapter(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data),
        maxResponseBytes: Int = 256 * 1_024
    ) -> HermesControlAdapter {
        HermesMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HermesMockURLProtocol.self]
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        return HermesControlAdapter(
            urlSession: URLSession(configuration: configuration),
            maxResponseBytes: maxResponseBytes
        )
    }

    private func response(
        _ request: URLRequest,
        status: Int,
        json: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(json.utf8)
        )
    }
}

private final class HermesMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
