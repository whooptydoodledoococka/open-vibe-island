import Foundation

public enum RuleSaveState: Equatable, Sendable {
    case idle
    case saved
    case failed(String)
}

func ruleSaveFailureMessage(_ error: any Error) -> String {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return message.isEmpty ? "Unable to save rules" : message
}
