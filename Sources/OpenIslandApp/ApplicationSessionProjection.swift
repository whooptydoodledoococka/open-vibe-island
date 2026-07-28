import Foundation
import OpenIslandCore

/// Pure application read-model projection for the island session list.
///
/// AppModel remains the application owner. This module only ranks and buckets
/// already-reduced sessions; process monitoring remains an adapter supplied by
/// AppModel through the live attachment-key snapshot.
struct ApplicationSessionProjection {
    typealias SessionBuckets = (primary: [AgentSession], overflow: [AgentSession])

    static func buckets(
        sessions: [AgentSession],
        now: Date,
        completedStaleThreshold: IslandCompletedStaleThreshold,
        liveAttachmentKeysBySessionID: [String: String]
    ) -> SessionBuckets {
        let rankedSessions = sessions.sorted { lhs, rhs in
            let lhsScore = displayPriority(
                for: lhs,
                now: now,
                completedStaleThreshold: completedStaleThreshold
            )
            let rhsScore = displayPriority(
                for: rhs,
                now: now,
                completedStaleThreshold: completedStaleThreshold
            )

            if lhsScore == rhsScore {
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                return lhs.islandActivityDate > rhs.islandActivityDate
            }

            return lhsScore > rhsScore
        }

        var primary: [AgentSession] = []
        var claimedLiveAttachmentKeys: Set<String> = []

        for session in rankedSessions where session.isVisibleInIsland {
            guard !session.isSubagentSession else { continue }

            if let liveAttachmentKey = liveAttachmentKeysBySessionID[session.id] {
                guard claimedLiveAttachmentKeys.insert(liveAttachmentKey).inserted else {
                    continue
                }
            }

            primary.append(session)
        }

        let primaryIDs = Set(primary.map(\.id))
        let overflow = rankedSessions.filter {
            !primaryIDs.contains($0.id) && !$0.isSubagentSession
        }
        return (primary, overflow)
    }

    private static func displayPriority(
        for session: AgentSession,
        now: Date,
        completedStaleThreshold: IslandCompletedStaleThreshold
    ) -> Int {
        var score = 0
        let presence = session.islandPresence(at: now)

        if session.isProcessAlive {
            score += presence == .inactive ? 3_000 : 12_000
        } else if session.isDemoSession || session.phase.requiresAttention {
            score += 6_000
        }

        if session.phase.requiresAttention {
            score += 10_000
        }

        if session.currentToolName?.isEmpty == false {
            score += 6_000
        }

        if session.jumpTarget != nil {
            score += 4_000
        }

        switch session.phase {
        case .running:
            score += 2_000
        case .waitingForApproval:
            score += 1_500
        case .waitingForAnswer:
            score += 1_200
        case .completed:
            score += 600
        }

        if session.isStaleCompletedForIsland(
            at: now,
            threshold: completedStaleThreshold.seconds
        ) {
            score -= 900
        }

        let age = now.timeIntervalSince(session.islandActivityDate)
        switch age {
        case ..<120:
            score += 500
        case ..<900:
            score += 250
        case ..<3_600:
            score += 120
        case ..<21_600:
            score += 40
        default:
            break
        }

        return score
    }
}
