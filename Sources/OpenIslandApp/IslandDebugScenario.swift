import CoreGraphics
import Foundation
import OpenIslandCore

struct IslandDebugSnapshot {
    let title: String
    let summary: String
    let previewHeight: CGFloat
    let notchStatus: NotchStatus
    let notchOpenReason: NotchOpenReason?
    let islandSurface: IslandSurface
    let sessions: [AgentSession]
    let selectedSessionID: String?
    var hermesGatewaySnapshot: HermesGatewaySnapshot? = nil
    var receipts: [OrbitReceipt] = []
    var contextEvidence: [OrbitContextEvidence] = []
    var efficiencyTelemetry: [OrbitEfficiencyTelemetry] = []
    var externalObservationReports: [OrbitExternalObservationReport] = []
}

enum IslandDebugScenario: String, CaseIterable, Identifiable {
    case closed
    case sessionList
    case approvalCard
    case questionCard
    case completionCard
    case longCompletionCard
    case staleHermes
    case unavailableHermes
    case multipleRequests
    case receiptDelivered
    case contextPressure
    case externalFeeds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed:
            "Closed Notch"
        case .sessionList:
            "Session List"
        case .approvalCard:
            "Approval Card"
        case .questionCard:
            "Question Card"
        case .completionCard:
            "Completion Card"
        case .longCompletionCard:
            "Long Completion Card"
        case .staleHermes:
            "Stale Hermes Evidence"
        case .unavailableHermes:
            "Unavailable Hermes Evidence"
        case .multipleRequests:
            "Multiple Requests"
        case .receiptDelivered:
            "Delivered Receipt"
        case .contextPressure:
            "Context Pressure"
        case .externalFeeds:
            "External Feed Status"
        }
    }

    var summary: String {
        switch self {
        case .closed:
            "Collapsed idle/running notch with live count and attention affordance."
        case .sessionList:
            "Manual expanded list with running, active, and inactive session rows."
        case .approvalCard:
            "Auto-expanded permission surface with approve and deny actions."
        case .questionCard:
            "Auto-expanded question surface with selectable answer buttons."
        case .completionCard:
            "Auto-expanded finished-task reminder surface after a turn completes."
        case .longCompletionCard:
            "Long finished-task reply stays inside the card and scrolls internally."
        case .staleHermes:
            "Hermes gateway and session metadata are visibly labeled stale."
        case .unavailableHermes:
            "Hermes gateway and session metadata are visibly labeled unavailable."
        case .multipleRequests:
            "One session retains multiple permissions and questions without overwrite."
        case .receiptDelivered:
            "Adapter delivery remains visibly distinct from source acknowledgement."
        case .contextPressure:
            "Metadata-only context headroom, savings, cache, freshness, and confidence."
        case .externalFeeds:
            "OpenCode and FreeBuff remain bounded, read-only, and inspection-only."
        }
    }

    func snapshot(at now: Date = .now) -> IslandDebugSnapshot {
        switch self {
        case .closed:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .sessionList:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .approvalCard:
            let session = DebugSessionFactory.approvalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 330,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .questionCard:
            let session = DebugSessionFactory.questionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 270,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .completionCard:
            let session = DebugSessionFactory.completionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .longCompletionCard:
            let session = DebugSessionFactory.longCompletionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 290,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .staleHermes:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                hermesGatewaySnapshot: HermesGatewaySnapshot(
                    gateway: .stale,
                    sessions: .stale,
                    detail: "Last successful local metadata refresh was 90 seconds ago."
                )
            )

        case .unavailableHermes:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id,
                hermesGatewaySnapshot: HermesGatewaySnapshot(
                    gateway: .unavailable,
                    sessions: .unavailable,
                    detail: "Local Hermes metadata is unavailable."
                )
            )

        case .multipleRequests:
            let session = DebugSessionFactory.multipleRequestSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 360,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .receiptDelivered:
            let session = DebugSessionFactory.receiptSession(now: now)
            let receipt = OrbitReceipt(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                createdAt: now,
                sessionID: session.id,
                requestID: UUID(uuidString: "50000000-0000-0000-0000-000000000002"),
                providerCorrelationID: "demo-correlation",
                adapter: AgentTool.codex.rawValue,
                action: .permissionAllowedOnce,
                scope: "Bash",
                status: .delivered,
                summary: "permission decision captured"
            )
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 260,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id,
                receipts: [receipt]
            )

        case .contextPressure:
            let sessions = DebugSessionFactory.listSessions(now: now)
            let report = OrbitContextBudgeter.assess(
                segments: [
                    OrbitContextSegment(provenanceID: "system", kind: .system, estimatedTokens: 18_000, priority: 10),
                    OrbitContextSegment(provenanceID: "tools", kind: .tool, estimatedTokens: 42_000, priority: 1),
                ],
                policy: OrbitContextBudgetPolicy(targetTokens: 36_000, reservedTokens: 4_000)
            )
            let evidence = OrbitContextEvidence(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
                sessionID: sessions[0].id,
                taskID: "task_demo_context",
                adapter: AgentTool.codex.rawValue,
                model: "demo-model",
                observedAt: now,
                freshness: .fresh,
                confidence: .estimated,
                strategy: .losslessCompaction,
                contextWindowTokens: 72_000,
                cachedContextTokens: 21_000,
                cacheWriteTokens: 2_000,
                budget: report,
                reversibleReferenceID: "blob_demo_context"
            )
            let telemetry = OrbitEfficiencyTelemetry(
                id: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!,
                sessionID: sessions[0].id,
                taskID: "task_demo_context",
                adapter: AgentTool.codex.rawValue,
                provider: "openai",
                model: "demo-model",
                route: "austin-router",
                observedAt: now,
                freshness: .fresh,
                confidence: .estimated,
                inputTokens: 60_000,
                outputTokens: 4_000,
                cachedInputTokens: 21_000,
                cacheWriteTokens: 2_000,
                retainedTokens: report.retainedTokens,
                omittedTokens: report.omittedTokens,
                toolCalls: 12,
                latencyMilliseconds: 8_400,
                approvalInterruptions: 1,
                retries: 1,
                failures: 0,
                completionQualityEvidence: 3
            )
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 480,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions[0].id,
                contextEvidence: [evidence],
                efficiencyTelemetry: [telemetry]
            )

        case .externalFeeds:
            let sessions = DebugSessionFactory.listSessions(now: now)
            let updatedMilliseconds = Int64(now.timeIntervalSince1970 * 1_000)
            let openCodeData = Data("[{\"id\":\"oc_fixture\",\"updated\":\(updatedMilliseconds)}]".utf8)
            let staleDate = ISO8601DateFormatter().string(from: now.addingTimeInterval(-120))
            let freeBuffData = Data("{\"agent\":\"freebuff\",\"updated_at\":\"\(staleDate)\"}".utf8)
            let openCode = try? OrbitExternalSessionObservationParser.parseOpenCodeJSON(
                openCodeData,
                now: now
            ).get()
            let freeBuff = try? OrbitExternalSessionObservationParser.parseFreeBuffManifest(
                freeBuffData,
                now: now
            ).get()
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 480,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions[0].id,
                externalObservationReports: [openCode, freeBuff].compactMap { $0 }
            )
        }
    }
}

private enum DebugSessionFactory {
    static func receiptSession(now: Date) -> AgentSession {
        var session = AgentSession(
            id: "session-receipt-delivered",
            title: "orbit · approval delivery",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Waiting for source acknowledgement",
            updatedAt: now
        )
        session.isProcessAlive = true
        return session
    }

    static func listSessions(now: Date) -> [AgentSession] {
        [
            runningSession(now: now),
            recentCompletedSession(now: now),
            inactiveSession(
                id: "session-claude-research",
                workspace: "claude-research",
                initialPrompt: "I care more about acquisition. I want to show my usage in another app in real time.",
                latestPrompt: "Why check Cursor's official docs? What does this have to do with Cursor?",
                assistant: "I would not choose by age. The oldest option is not automatically the lightest or best fit.",
                age: 27 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-personal",
                workspace: "Personal",
                initialPrompt: "[Image #1] I captured three screenshots of the models currently available in Cursor.",
                latestPrompt: "[Image #1] I captured three screenshots of the models currently available in Cursor.",
                assistant: "Strictly speaking, the model in this image is not the one this `voice-input` app should choose.",
                age: 32 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-open-agent-sdk",
                workspace: "open-agent-sdk",
                initialPrompt: "Okay, do you need to open a PR now?",
                latestPrompt: "Then just open a PR.",
                assistant: "The PR is ready:",
                age: 60 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-voice-input",
                workspace: "voice-input",
                initialPrompt: "Look at the voice-input repository, focusing on model selection.",
                latestPrompt: "Which model should it use, strictly speaking?",
                assistant: "For lightweight real-time use, do not map directly from Cursor's existing plans.",
                age: 78 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-agents",
                workspace: "agents",
                initialPrompt: "Give me your branch and worktree.",
                latestPrompt: "So do you need to restart first?",
                assistant: "Restarted. The new dev process is running.",
                age: 92 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-claude",
                workspace: "claude-code",
                initialPrompt: "Let's change the entire notch background to pure black first.",
                latestPrompt: "Remove the empty area below it.",
                assistant: "The expanded height now adapts to the content.",
                age: 118 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-hooks",
                workspace: "hooks",
                initialPrompt: "How should I monitor Claude Code usage in real time?",
                latestPrompt: "What if it is displayed in another app?",
                assistant: "There are several more direct paths already available in the code.",
                age: 130 * 60,
                now: now
            ),
        ]
    }

    static func notificationSessions(lead: AgentSession, now: Date) -> [AgentSession] {
        var sessions = listSessions(now: now)
        if sessions.isEmpty {
            return [lead]
        }
        sessions[0] = lead
        return sessions
    }

    static func runningSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-running",
            title: "Codex · orbit",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Reading IslandPanelView.swift and AppModel.swift",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "orbit",
                paneTitle: "codex ~/Personal/orbit",
                workingDirectory: "/Users/example/Personal/orbit",
                terminalSessionID: "ghostty-running"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Refactor DEV completely into a debug page. I need stable UI acceptance for these cards.",
                lastUserPrompt: "There were incorrect changes before too. You should redo them.",
                lastAssistantMessage: "Reading the current notch state and event routing, then splitting alert state out of the session list.",
                currentTool: "exec_command",
                currentCommandPreview: "sed -n '1,260p' Sources/OpenIslandApp/Views/SettingsView.swift"
            )
        )
    }

    static func recentCompletedSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-recent",
            title: "Codex · open-agent-sdk",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The session list now matches the original island more closely.",
            updatedAt: now.addingTimeInterval(-3 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-agent-sdk",
                paneTitle: "codex ~/Personal/open-agent-sdk",
                workingDirectory: "/Users/example/Personal/open-agent-sdk",
                terminalSessionID: "ghostty-recent"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Read this paper: https://arxiv.org/html/2603.28052",
                lastUserPrompt: "Read this paper: https://arxiv.org/html/2603.28052v1. It feels similar to the agent we are building.",
                lastAssistantMessage: "Finished. I extracted the key differences related to autoresearch."
            )
        )
    }

    static func inactiveSession(
        id: String,
        workspace: String,
        initialPrompt: String,
        latestPrompt: String,
        assistant: String,
        age: TimeInterval,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspace)",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: assistant,
            updatedAt: now.addingTimeInterval(-age),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "codex ~/Personal/\(workspace)",
                workingDirectory: "/Users/example/Personal/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: initialPrompt,
                lastUserPrompt: latestPrompt,
                lastAssistantMessage: assistant
            )
        )
    }

    static func approvalSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-approval",
            title: "Codex · orbit",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Allow exec_command to rewrite SettingsView.swift?",
            updatedAt: now.addingTimeInterval(-20),
            permissionRequest: PermissionRequest(
                title: "Approve file rewrite",
                summary: "Allow exec_command to rewrite SettingsView.swift?",
                affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny"
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "orbit",
                paneTitle: "codex ~/Personal/orbit",
                workingDirectory: "/Users/example/Personal/orbit",
                terminalSessionID: "ghostty-approval"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "I plan to keep filling in more capabilities.",
                lastUserPrompt: "I want to bring askUserQuestion and permission approval into our island too.",
                lastAssistantMessage: "The DEV page is ready to rewrite. File changes need approval.",
                currentTool: "exec_command",
                currentCommandPreview: "head -5000 /Users/example/Personal/claude-research/extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt"
            )
        )
    }

    static func questionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-question",
            title: "Codex · orbit",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Should this alert state collapse automatically?",
            updatedAt: now.addingTimeInterval(-18),
            questionPrompt: QuestionPrompt(
                title: "Which authentication method should we use?",
                questions: [
                    QuestionPromptItem(
                        question: "Which authentication method should we use?",
                        header: "Auth",
                        options: [
                            QuestionOption(label: "JWT tokens", description: "Stateless, scalable"),
                            QuestionOption(label: "Session cookies", description: "Traditional approach"),
                            QuestionOption(label: "OAuth 2.0", description: "Third-party auth"),
                            QuestionOption(label: "Other", description: "", allowsFreeform: true),
                        ]
                    )
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "orbit",
                paneTitle: "codex ~/Personal/orbit",
                workingDirectory: "/Users/example/Personal/orbit",
                terminalSessionID: "ghostty-question"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "The original product looks like one notch surface plus multiple content surfaces.",
                lastUserPrompt: "How should we approach this?",
                lastAssistantMessage: "I suggest splitting approvalCard, questionCard, and completionCard into independent surfaces."
            )
        )
    }

    static func multipleRequestSession(now: Date) -> AgentSession {
        var session = approvalSession(now: now)
        session.permissionRequests.append(
            PermissionRequest(
                title: "Approve package refresh",
                summary: "Allow Orbit to replace the local development bundle?",
                affectedPath: "~/Applications/Orbit Dev.app",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny"
            )
        )
        session.questionPrompts = [questionSession(now: now).questionPrompt].compactMap { $0 }
        session.summary = "Three requests are waiting for review."
        return session
    }

    static func completionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion",
            title: "Codex · orbit",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The DEV page now uses mock-driven card debug mode.",
            updatedAt: now.addingTimeInterval(-15),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "orbit",
                paneTitle: "codex ~/Personal/orbit",
                workingDirectory: "/Users/example/Personal/orbit",
                terminalSessionID: "ghostty-completion"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "This time I may actually need mocks so I can accept these cards' UI.",
                lastUserPrompt: "Can you refactor DEV completely into a debug page?",
                lastAssistantMessage: "The plan is written. How are your hooks firing?"
            )
        )
    }

    static func longCompletionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion-long",
            title: "Codex · orbit",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The README commit is complete. Long replies should now scroll inside the card.",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "orbit",
                paneTitle: "codex ~/Personal/orbit",
                workingDirectory: "/Users/example/Personal/orbit",
                terminalSessionID: "ghostty-completion-long"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Commit this README too, then paste the result here.",
                lastUserPrompt: "Also confirm the current worktree and verification status.",
                lastAssistantMessage: """
[README.md](/Users/example/Personal/orbit/README.md) changes were committed separately as `f196316`, with message `docs: update readme tagline`.

This pass did not run tests because it only changed copy. The worktree is clean, and `main` is currently `ahead 6` of `origin/main`.

If you want another pass, I recommend moving the work to an independent worktree so it does not conflict with parallel changes on shared `main`.

Next I will check the repository state, create a worktree and branch from `origin/main`, then continue the style work there and finish verification.
"""
            )
        )
    }
}
