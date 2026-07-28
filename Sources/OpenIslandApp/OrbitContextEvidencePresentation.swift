import Foundation
import OpenIslandCore

struct OrbitContextEvidencePresentation: Equatable {
    let title: String
    let detail: String
    let systemImage: String
    let pressure: OrbitContextEvidence.Pressure

    static func make(for evidence: OrbitContextEvidence) -> OrbitContextEvidencePresentation {
        let title: String
        let systemImage: String
        switch evidence.pressure {
        case .healthy:
            title = "Context healthy · \(percent(evidence.headroomPercent)) headroom"
            systemImage = "gauge.with.dots.needle.33percent"
        case .elevated:
            title = "Context filling · \(percent(evidence.headroomPercent)) headroom"
            systemImage = "gauge.with.dots.needle.67percent"
        case .critical:
            title = "Context critical · \(percent(evidence.headroomPercent)) headroom"
            systemImage = "gauge.with.dots.needle.100percent"
        case .stale:
            title = "Context evidence stale"
            systemImage = "clock.badge.exclamationmark"
        case .redactionRequired:
            title = "Context requires redaction"
            systemImage = "eye.slash.fill"
        case .unavailable:
            title = "Context evidence unavailable"
            systemImage = "questionmark.circle"
        }

        let strategy = switch evidence.strategy {
        case .none: "observed"
        case .cachePrefixStabilization: "stable prefix"
        case .losslessCompaction: "lossless compaction"
        case .reversibleRetrieval: "reversible retrieval"
        }
        let detail: String
        if evidence.pressure == .unavailable {
            detail = "No current context measurement · unknown · unavailable"
        } else {
            detail = [
                "\(compactTokens(evidence.budget.omittedTokens)) saved",
                "\(percent(evidence.cacheReadPercent)) cache",
                strategy,
                evidence.confidence.rawValue,
                evidence.freshness.rawValue,
            ].joined(separator: " · ")
        }

        return OrbitContextEvidencePresentation(
            title: title,
            detail: detail,
            systemImage: systemImage,
            pressure: evidence.pressure
        )
    }

    private static func compactTokens(_ value: Int) -> String {
        if value < 1_000 { return "\(value)" }
        let thousands = Double(value) / 1_000
        return thousands >= 10
            ? "\(Int(thousands.rounded()))K"
            : String(format: "%.1fK", thousands)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
