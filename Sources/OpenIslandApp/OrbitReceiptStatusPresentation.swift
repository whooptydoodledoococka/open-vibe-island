import Foundation
import OpenIslandCore

struct OrbitReceiptStatusPresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case pending
        case success
        case failure
    }

    let title: String
    let detail: String
    let systemImage: String
    let tone: Tone

    static func make(for receipt: OrbitReceipt) -> OrbitReceiptStatusPresentation {
        let action = switch receipt.action {
        case .permissionDenied: "Denied"
        case .permissionAllowedOnce: "Allowed once"
        case .permissionAllowedWithUpdates: "Permission updated"
        case .questionAnswered: "Answer submitted"
        case .sessionReplied: "Reply sent"
        case .sessionSteered: "Steer sent"
        case .sessionCancelled: "Cancel requested"
        }

        return switch receipt.status {
        case .decisionCaptured, .queued:
            OrbitReceiptStatusPresentation(
                title: "\(action) · decision captured",
                detail: "Not delivered to \(receipt.adapter) yet",
                systemImage: "checkmark.circle",
                tone: .neutral
            )
        case .deliveryPending:
            OrbitReceiptStatusPresentation(
                title: "\(action) · delivering",
                detail: "Waiting for \(receipt.adapter) to accept the action",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .pending
            )
        case .delivered, .sent:
            OrbitReceiptStatusPresentation(
                title: "\(action) · delivered",
                detail: "Source acknowledgement is still pending",
                systemImage: "paperplane.fill",
                tone: .pending
            )
        case .acknowledged:
            OrbitReceiptStatusPresentation(
                title: "\(action) · acknowledged",
                detail: "\(receipt.adapter) confirmed the correlated action",
                systemImage: "checkmark.seal.fill",
                tone: .success
            )
        case .rejected:
            OrbitReceiptStatusPresentation(
                title: "\(action) · rejected",
                detail: "The originating adapter rejected the action",
                systemImage: "xmark.octagon.fill",
                tone: .failure
            )
        case .expired:
            OrbitReceiptStatusPresentation(
                title: "\(action) · expired",
                detail: "The bound request expired before acknowledgement",
                systemImage: "clock.badge.exclamationmark",
                tone: .failure
            )
        case .disconnected:
            OrbitReceiptStatusPresentation(
                title: "\(action) · disconnected",
                detail: "The originating adapter disconnected",
                systemImage: "bolt.slash.fill",
                tone: .failure
            )
        case .deliveryFailed, .failed:
            OrbitReceiptStatusPresentation(
                title: "\(action) · delivery failed",
                detail: "Orbit did not receive adapter acceptance",
                systemImage: "exclamationmark.triangle.fill",
                tone: .failure
            )
        }
    }
}
