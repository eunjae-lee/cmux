import Combine
import Foundation
#if DEBUG
import Bonsplit
#endif

// MARK: - Provider Configuration

struct WorkspaceProviderDefinition: Codable, Sendable {
    var id: String
    var name: String
    var list: String
    var create: String
    var destroy: String?
}

/// Metadata stored on a workspace to track its provider origin.
/// Used for calling the destroy command on workspace close.
struct WorkspaceProviderOrigin {
    var providerId: String
    var destroyCommand: String?
    var itemId: String
    var inputs: [String: String]
    var cwd: String?
}

// MARK: - Provider List Response

struct WorkspaceProviderListResponse: Codable {
    var items: [WorkspaceProviderItem]
}

struct WorkspaceProviderItem: Codable, Identifiable {
    var id: String
    var name: String
    var subtitle: String?
    var inputs: [WorkspaceProviderInput]?
}

struct WorkspaceProviderInput: Codable, Identifiable {
    var id: String
    var label: String
    var placeholder: String?
    var required: Bool?
    /// When set, this field auto-derives its value from another input by slugifying it.
    /// The value is the id of the source input (e.g. "session").
    /// User can still override the derived value.
    var deriveFrom: String?

    var isRequired: Bool { required ?? false }
}

// MARK: - Provider Create Response

struct WorkspaceProviderCreateResult: Codable {
    var title: String?
    var cwd: String?
    var color: String?
    var env: [String: String]?
    var layout: CmuxLayoutNode?
    var error: String?

    var isError: Bool { error != nil }
}

// MARK: - Provider Execution

enum WorkspaceProviderError: Error, LocalizedError {
    case listFailed(String)
    case listParseFailed(String)
    case createFailed(String)
    case createParseFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .listFailed(let msg): return "Provider list failed: \(msg)"
        case .listParseFailed(let msg): return "Failed to parse provider list: \(msg)"
        case .createFailed(let msg): return "Provider create failed: \(msg)"
        case .createParseFailed(let msg): return "Failed to parse provider create output: \(msg)"
        case .timeout: return "Provider command timed out"
        }
    }
}

@MainActor
final class WorkspaceProviderStore: ObservableObject {
    @Published private(set) var providers: [WorkspaceProviderDefinition] = []
    @Published private(set) var cachedItems: [String: [WorkspaceProviderItem]] = [:]

    func updateProviders(_ newProviders: [WorkspaceProviderDefinition]) {
        providers = newProviders
        // Clear cache for removed providers
        let validIds = Set(newProviders.map(\.id))
        cachedItems = cachedItems.filter { validIds.contains($0.key) }
    }

    /// Fetch items from a provider's list command. Caches the result.
    func fetchItems(for provider: WorkspaceProviderDefinition) async -> [WorkspaceProviderItem] {
        do {
            let items = try await WorkspaceProviderExecutor.runList(command: provider.list)
            cachedItems[provider.id] = items
            return items
        } catch {
            #if DEBUG
            dlog("workspace_provider.list.error provider=\(provider.id) error=\(error.localizedDescription)")
            #endif
            return cachedItems[provider.id] ?? []
        }
    }

    /// Run a provider's create command. Returns the workspace definition.
    /// Calls progressHandler with progress lines as they arrive.
    func create(
        provider: WorkspaceProviderDefinition,
        itemId: String,
        inputs: [String: String] = [:],
        progressHandler: @escaping (String) -> Void
    ) async throws -> WorkspaceProviderCreateResult {
        try await WorkspaceProviderExecutor.runCreate(
            command: provider.create,
            itemId: itemId,
            inputs: inputs,
            progressHandler: progressHandler
        )
    }
}

// MARK: - Shell Execution

enum WorkspaceProviderExecutor {
    private static let listTimeoutSeconds: Double = 5.0
    private static let createTimeoutSeconds: Double = 300.0

    static func runList(command: String) async throws -> [WorkspaceProviderItem] {
        let (stdout, stderr, exitCode) = try await runShellCommand(
            command: command,
            timeout: listTimeoutSeconds
        )

        guard exitCode == 0 else {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorkspaceProviderError.listFailed(msg.isEmpty ? "exit code \(exitCode)" : msg)
        }

        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw WorkspaceProviderError.listParseFailed("empty output")
        }

        do {
            let response = try JSONDecoder().decode(WorkspaceProviderListResponse.self, from: data)
            return response.items
        } catch {
            throw WorkspaceProviderError.listParseFailed(error.localizedDescription)
        }
    }

    static func runCreate(
        command: String,
        itemId: String,
        inputs: [String: String],
        progressHandler: @escaping (String) -> Void
    ) async throws -> WorkspaceProviderCreateResult {
        // Build args: --id <itemId> --input key=val ...
        var args = "\(command) --id \(shellEscape(itemId))"
        for (key, value) in inputs {
            args += " --input \(shellEscape("\(key)=\(value)"))"
        }

        let (stdout, stderr, exitCode) = try await runShellCommandStreaming(
            command: args,
            timeout: createTimeoutSeconds,
            lineHandler: { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("progress:") {
                    let msg = trimmed.dropFirst("progress:".count).trimmingCharacters(in: .whitespaces)
                    DispatchQueue.main.async { progressHandler(msg) }
                }
            }
        )

        guard exitCode == 0 else {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorkspaceProviderError.createFailed(msg.isEmpty ? "exit code \(exitCode)" : msg)
        }

        // Find the last non-progress JSON line
        let lines = stdout.components(separatedBy: .newlines)
        guard let jsonLine = lines.last(where: {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !t.hasPrefix("progress:") && t.hasPrefix("{")
        }) else {
            throw WorkspaceProviderError.createParseFailed("no JSON output found")
        }

        guard let data = jsonLine.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            throw WorkspaceProviderError.createParseFailed("invalid UTF-8")
        }

        do {
            let result = try JSONDecoder().decode(WorkspaceProviderCreateResult.self, from: data)
            if let error = result.error {
                throw WorkspaceProviderError.createFailed(error)
            }
            return result
        } catch let error as WorkspaceProviderError {
            throw error
        } catch {
            throw WorkspaceProviderError.createParseFailed("\(error.localizedDescription)\nRaw JSON line: \(jsonLine.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // MARK: - Shell Helpers

    static func runDestroy(origin: WorkspaceProviderOrigin) async {
        guard let destroy = origin.destroyCommand else { return }
        var args = "\(destroy) --id \(shellEscape(origin.itemId))"
        for (key, value) in origin.inputs {
            args += " --input \(shellEscape("\(key)=\(value)"))"
        }
        if let cwd = origin.cwd {
            args += " --cwd \(shellEscape(cwd))"
        }
        do {
            let (_, _, exitCode) = try await runShellCommand(command: args, timeout: 30)
            if exitCode != 0 {
                NSLog("[WorkspaceProvider] destroy command exited with code %d for item %@", exitCode, origin.itemId)
            }
        } catch {
            NSLog("[WorkspaceProvider] destroy command failed for item %@: %@", origin.itemId, error.localizedDescription)
        }
    }

    private static func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func resolveShell() -> String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private static func runShellCommand(
        command: String,
        timeout: Double
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: resolveShell())
            process.arguments = ["-l", "-c", command]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = ProcessInfo.processInfo.environment

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                process.terminate()
            }
            timer.resume()

            process.terminationHandler = { proc in
                timer.cancel()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.resume(returning: (stdout, stderr, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private static func runShellCommandStreaming(
        command: String,
        timeout: Double,
        lineHandler: @escaping (String) -> Void
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: resolveShell())
            process.arguments = ["-l", "-c", command]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = ProcessInfo.processInfo.environment

            var stdoutAccumulator = ""
            let stdoutLock = NSLock()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                stdoutLock.lock()
                stdoutAccumulator += str
                stdoutLock.unlock()
                // Deliver complete lines
                let lines = str.components(separatedBy: .newlines)
                for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lineHandler(line)
                }
            }

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                process.terminate()
            }
            timer.resume()

            process.terminationHandler = { proc in
                timer.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                // Read any remaining data
                let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: remaining, encoding: .utf8), !str.isEmpty {
                    stdoutLock.lock()
                    stdoutAccumulator += str
                    stdoutLock.unlock()
                }
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                stdoutLock.lock()
                let stdout = stdoutAccumulator
                stdoutLock.unlock()
                continuation.resume(returning: (stdout, stderr, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
