import Foundation

enum ProcessError: Error, LocalizedError {
    case failed(status: Int32, stderr: String)
    case notFound(command: String)

    var errorDescription: String? {
        switch self {
        case .failed(let status, let stderr):
            return "Process exited with status \(status): \(stderr)"
        case .notFound(let command):
            return "Command not found: \(command)"
        }
    }
}

// Thread-safe accumulator for pipe data to satisfy Swift 6 sendability checks.
private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.withLock { buffer.append(data) }
    }

    var string: String {
        lock.withLock { String(data: buffer, encoding: .utf8) ?? "" }
    }
}

struct ProcessRunner: Sendable {
    static func run(
        _ command: String,
        arguments: [String],
        extraEnv: [String: String] = [:],
        allowNonZeroExit: Bool = false
    ) async throws -> String {
        // Accept absolute paths directly; otherwise resolve via known locations.
        let resolved: String
        if command.hasPrefix("/") {
            resolved = command
        } else {
            resolved = try resolvedPath(for: command)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolved)
            process.arguments = arguments

            // Prepend Homebrew paths but keep the parent's PATH so tools like nvm,
            // pyenv, and user-local binaries are discoverable.
            var env = ProcessInfo.processInfo.environment
            let parentPath = env["PATH"] ?? ""
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(parentPath)"
            for (k, v) in extraEnv { env[k] = v }
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            let outAcc = DataAccumulator()
            let errAcc = DataAccumulator()
            let group  = DispatchGroup()

            // Read stdout chunks as they arrive to prevent 64KB pipe buffer overflow.
            group.enter()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    group.leave()
                } else {
                    outAcc.append(chunk)
                }
            }

            group.enter()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    group.leave()
                } else {
                    errAcc.append(chunk)
                }
            }

            process.terminationHandler = { p in
                group.notify(queue: .global(qos: .userInitiated)) {
                    if p.terminationStatus == 0 || allowNonZeroExit {
                        continuation.resume(returning: outAcc.string)
                    } else {
                        continuation.resume(throwing: ProcessError.failed(
                            status: p.terminationStatus,
                            stderr: errAcc.string
                        ))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func resolvedPath(for command: String) throws -> String {
        let candidates = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw ProcessError.notFound(command: command)
    }
}
