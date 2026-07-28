@preconcurrency import AppKit
import Foundation

public struct JumpCommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public typealias JumpCommandRunner = @Sendable (URL, [String]) -> JumpCommandResult

public enum JumpRuntime {
    public static func isApplicationRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public static func runCommand(executable: URL, arguments: [String]) -> JumpCommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return JumpCommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return JumpCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outputData, encoding: .utf8) ?? "",
            stderr: String(data: errorData, encoding: .utf8) ?? ""
        )
    }

    public static func runAppleScript(_ script: String) -> Result<String, NoLocalHandleReason> {
        let result = runCommand(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script]
        )
        guard result.exitCode == 0 else {
            let lowered = result.stderr.lowercased()
            if lowered.contains("not authorized") || lowered.contains("not permitted") || lowered.contains("-1743") {
                return .failure(.permissionDeniedAppleEvents)
            }
            return .failure(.windowNotFound)
        }
        return .success(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func normalizedTTY(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.hasPrefix("/dev/") ? trimmed : "/dev/\(trimmed)"
    }

    static func normalizedPath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    static func records(in output: String, fieldSeparator: Character = "\u{1f}") -> [[String]] {
        output
            .split(whereSeparator: \.isNewline)
            .map { line in line.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init) }
    }
}
