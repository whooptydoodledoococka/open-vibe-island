import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitApprovalInboxProjectionTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test
    func focusedSessionWinsWithoutDroppingSecondaryRequests() {
        let firstPermission = PermissionRequest(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            title: "Write file",
            summary: "Edit requested",
            affectedPath: "/private/project/secret.swift",
            toolName: "Write"
        )
        let secondPermission = PermissionRequest(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            title: "Run tests",
            summary: "Command requested",
            affectedPath: "/private/project",
            toolName: "Bash"
        )
        let backgroundQuestion = QuestionPrompt(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            title: "Choose mode",
            options: ["Safe", "Fast"]
        )
        let focusedQuestion = QuestionPrompt(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            title: "Confirm scope",
            options: ["Once", "Cancel"]
        )

        var background = session(id: "background", tool: .codex, updatedAt: now.addingTimeInterval(-30))
        background.permissionRequests = [firstPermission, secondPermission]
        background.questionPrompts = [backgroundQuestion]
        var focused = session(id: "focused", tool: .claudeCode, updatedAt: now)
        focused.questionPrompts = [focusedQuestion]

        let output = OrbitApprovalInboxProjection.project(
            sessions: [background, focused],
            receipts: [],
            focusedSessionID: "focused"
        )

        #expect(output.primary?.requestID == focusedQuestion.id)
        #expect(output.primary?.stateVerb == "Answer required")
        #expect(output.primary?.adapter == AgentTool.claudeCode.rawValue)
        #expect(output.primary?.provenance == SessionOrigin.live.rawValue)
        #expect(output.pendingCount == 4)
        #expect(Set(output.orderedItems.map(\.requestID)) == Set([
            firstPermission.id,
            secondPermission.id,
            backgroundQuestion.id,
            focusedQuestion.id,
        ]))
        #expect(output.orderedItems.allSatisfy { !$0.scope.contains("/private/") })
    }

    @Test
    func permissionsUseStablePriorityWhenNoSessionIsFocused() {
        let newerQuestion = QuestionPrompt(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            title: "Question",
            options: ["A"]
        )
        let olderPermission = PermissionRequest(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            title: "Permission",
            summary: "Permission",
            affectedPath: "",
            toolName: "Read"
        )
        var questionSession = session(id: "question", tool: .openCode, updatedAt: now)
        questionSession.questionPrompts = [newerQuestion]
        var permissionSession = session(id: "permission", tool: .codex, updatedAt: now.addingTimeInterval(-60))
        permissionSession.permissionRequests = [olderPermission]

        let output = OrbitApprovalInboxProjection.project(
            sessions: [questionSession, permissionSession],
            receipts: [],
            focusedSessionID: nil
        )

        #expect(output.orderedItems.map(\.requestID) == [olderPermission.id, newerQuestion.id])
        #expect(output.primary?.scope == "Read")
    }

    @Test
    func latestReceiptResultRemainsVisibleAfterRequestLeavesInbox() {
        let requestID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let receiptID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let captured = OrbitReceipt(
            id: receiptID,
            sessionID: "complete",
            requestID: requestID,
            adapter: AgentTool.codex.rawValue,
            action: .permissionAllowedOnce,
            scope: "Write",
            status: .decisionCaptured,
            summary: "decision captured"
        )

        let output = OrbitApprovalInboxProjection.project(
            sessions: [],
            receipts: [captured, captured.with(status: .delivered)],
            focusedSessionID: nil
        )

        #expect(output.primary == nil)
        #expect(output.pendingCount == 0)
        #expect(output.latestReceipt?.id == receiptID)
        #expect(output.latestReceipt?.status == .delivered)
    }

    private func session(
        id: String,
        tool: AgentTool,
        updatedAt: Date
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "\(tool.displayName) · \(id)",
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Awaiting input",
            updatedAt: updatedAt
        )
        session.isProcessAlive = true
        return session
    }
}
