import Foundation
import Combine
import CoreFoundation
import Darwin

struct ClaudeCommandRequest {
    var id: UUID
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL
    var input: Data = Data()
    var timeout: TimeInterval
    var outputLimit: Int = 4_000_000
}

struct ClaudeCommandResult {
    var stdout: Data
    var stderr: Data = Data()
    var exitCode: Int32
}

@MainActor protocol ClaudeCommandRunning {
    func run(_ request: ClaudeCommandRequest) async throws -> ClaudeCommandResult
    func cancel(_ id: UUID)
    func cancelAll()
}

/// Runs the unmodified, bundled Claude Code CLI. Only the CLI handles OAuth credentials.
@MainActor final class ClaudeClient: ObservableObject {
    @Published var account = "尚未检查登录状态"
    @Published var signedIn = false
    @Published var loginPending = false

    private let executable: URL
    private let directory: URL
    private let inheritedEnvironment: [String: String]
    private let runner: ClaudeCommandRunning
    private var loginID: UUID?
    private var generation = UUID()

    init(executable: URL? = nil, applicationDirectory: URL? = nil,
         environment: [String: String]? = nil, runner: ClaudeCommandRunning? = nil) {
        self.executable = executable ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Claude/claude")
        directory = (applicationDirectory ?? DataStore.applicationDirectory).appendingPathComponent("Claude", isDirectory: true)
        inheritedEnvironment = environment ?? ProcessInfo.processInfo.environment
        self.runner = runner ?? ClaudeProcessRunner()
    }

    func refresh() async throws {
        guard !loginPending else { return }
        let expectedGeneration = generation
        do {
            let status = try await checkAccount(id: UUID())
            try Task.checkCancellation()
            guard generation == expectedGeneration else { throw CancellationError() }
            apply(status)
        } catch {
            if generation == expectedGeneration, !(error is CancellationError) {
                signedIn = false
                account = "尚未登录"
            }
            throw error
        }
    }

    func login() async throws {
        guard !loginPending else { return }
        let id = UUID()
        generation = UUID()
        loginID = id
        loginPending = true
        account = "等待浏览器授权"
        defer {
            if loginID == id { loginID = nil; loginPending = false }
        }
        do {
            // --claudeai is the official subscription login option; never use --console or setup-token.
            let result = try await run(id: id, arguments: ["auth", "login", "--claudeai"], timeout: 300)
            try Task.checkCancellation()
            guard loginID == id else { throw CancellationError() }
            guard result.exitCode == 0 else { throw AppError.message("Claude 登录未完成，请重新连接。") }
            let status = try await checkAccount(id: id)
            try Task.checkCancellation()
            guard loginID == id else { throw CancellationError() }
            apply(status)
            guard status.connected else { throw AppError.message("尚未完成 Claude 登录授权，请重新登录。") }
        } catch {
            if loginID == id {
                signedIn = false
                account = error is CancellationError ? "已取消登录" : "尚未登录"
            }
            throw error
        }
    }

    func cancelLogin() {
        guard let id = loginID else { return }
        loginID = nil
        generation = UUID()
        runner.cancel(id)
        loginPending = false
        signedIn = false
        account = "已取消登录"
    }

    func logout() async throws {
        shutdown()
        let expectedGeneration = generation
        let result = try await run(id: UUID(), arguments: ["auth", "logout"], timeout: 30)
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
        guard result.exitCode == 0 else { throw AppError.message("Claude 退出登录失败，请重试。") }
        signedIn = false
        account = "已退出登录"
    }

    func shutdown() {
        cancelLogin()
        generation = UUID()
        runner.cancelAll()
    }

    func structuredReply(_ prompt: String, instructions: String, schema: [String: Any],
                         screenshot: URL? = nil) async throws -> String {
        try Task.checkCancellation()
        guard !loginPending else { throw AppError.message("请先完成 Claude 浏览器授权。") }
        let id = UUID(), expectedGeneration = generation
        let status: ClaudeAccountStatus
        do { status = try await checkAccount(id: id) }
        catch {
            if generation == expectedGeneration, !(error is CancellationError) {
                signedIn = false; account = "尚未登录"
            }
            throw error
        }
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
        apply(status)
        guard status.connected else { throw AppError.message("请先在设置中登录 Claude。") }
        let input = try Self.input(prompt: prompt, screenshot: screenshot)
        let schemaData = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        guard schemaData.count <= 200_000, instructions.utf8.count <= 100_000 else {
            throw AppError.message("Claude 请求内容过长，请缩短后重试。")
        }
        let arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--tools", "", "--disallowedTools", "mcp__*", "--strict-mcp-config",
            "--mcp-config", "{\"mcpServers\":{}}", "--disable-slash-commands",
            "--permission-mode", "dontAsk", "--permission-prompts", "none", "--no-session-persistence",
            "--system-prompt", instructions, "--json-schema", String(decoding: schemaData, as: UTF8.self)
        ]
        let result = try await run(id: id, arguments: arguments, input: input, timeout: 180)
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
        return try Self.structuredOutput(result)
    }

    private func apply(_ status: ClaudeAccountStatus) {
        signedIn = status.connected
        account = status.label
    }

    private func checkAccount(id: UUID) async throws -> ClaudeAccountStatus {
        let result = try await run(id: id, arguments: ["auth", "status", "--json"], timeout: 30)
        return try ClaudeAccountStatus.parse(result, configDirectory: directory)
    }

    private func run(id: UUID, arguments: [String], input: Data = Data(), timeout: TimeInterval) async throws -> ClaudeCommandResult {
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppError.message("此构建缺少 Claude 运行组件，请重新构建或更新 Mac 开发版。")
        }
        let workspace = directory.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // safe-mode retains subscription OAuth while excluding user/project customizations. bare does not.
        let common = ["--safe-mode", "--setting-sources", "", "--settings", "{\"disableAllHooks\":true,\"autoMemoryEnabled\":false,\"fastMode\":false}"]
        return try await runner.run(ClaudeCommandRequest(id: id, executable: executable, arguments: common + arguments,
            environment: Self.environment(inheritedEnvironment, configDirectory: directory),
            workingDirectory: workspace, input: input, timeout: timeout))
    }

    static func environment(_ source: [String: String], configDirectory: URL) -> [String: String] {
        // An allowlist also excludes future API/provider overrides, shell startup files, and injected runtimes.
        let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TZ", "__CF_USER_TEXT_ENCODING"]
        var result = source.filter { allowed.contains($0.key) }
        result["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        result["CLAUDE_CONFIG_DIR"] = configDirectory.path
        result["XDG_CONFIG_HOME"] = configDirectory.appendingPathComponent("Configuration", isDirectory: true).path
        result["DISABLE_UPDATES"] = "1"
        result["DISABLE_TELEMETRY"] = "1"
        result["DISABLE_ERROR_REPORTING"] = "1"
        result["CLAUDE_CODE_DISABLE_FAST_MODE"] = "1"
        result["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        result["CLAUDE_CODE_DISABLE_FILE_MENTIONS"] = "1"
        return result
    }

    static func input(prompt: String, screenshot: URL?) throws -> Data {
        guard prompt.utf8.count <= 2_000_000 else { throw AppError.message("发送给 Claude 的内容过长，请缩短后重试。") }
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let screenshot {
            let attributes = try FileManager.default.attributesOfItem(atPath: screenshot.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= 5_000_000 else {
                throw AppError.message("截图过大，请缩小后重试。")
            }
            let bytes = try Data(contentsOf: screenshot)
            guard bytes.count <= 5_000_000 else { throw AppError.message("截图过大，请缩小后重试。") }
            let mediaType: String
            if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { mediaType = "image/jpeg" }
            else if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { mediaType = "image/png" }
            else { throw AppError.message("Claude 截图需要 PNG 或 JPEG 格式。") }
            content.append(["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": bytes.base64EncodedString()]])
        }
        var data = try JSONSerialization.data(withJSONObject: ["type": "user", "message": ["role": "user", "content": content], "parent_tool_use_id": NSNull(), "session_id": ""])
        guard data.count <= 9_000_000 else { throw AppError.message("Claude 请求内容过大，请缩短文字或缩小截图。") }
        data.append(0x0A)
        return data
    }

    static func structuredOutput(_ result: ClaudeCommandResult) throws -> String {
        guard result.stdout.count <= 4_000_000 else { throw AppError.message("Claude 回复过长，请缩短请求后重试。") }
        guard result.exitCode == 0 else { throw responseError(result.stdout + result.stderr) }
        var final: [String: Any]?
        for line in result.stdout.split(separator: 0x0A) where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = message["type"] as? String else {
                throw AppError.message("Claude 返回格式无效，请重试。")
            }
            if type == "result" {
                guard final == nil else { throw AppError.message("Claude 返回了重复结果，请重试。") }
                final = message
            }
        }
        guard let final else { throw AppError.message("Claude 没有返回完整结果，请重试。") }
        guard final["subtype"] as? String == "success", Self.boolean(final["is_error"]) == false else {
            throw responseError(result.stdout)
        }
        guard let output = final["structured_output"] as? [String: Any], JSONSerialization.isValidJSONObject(output) else {
            throw AppError.message("Claude 未返回约定的结构化结果，请重试。")
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        guard data.count <= 200_000 else { throw AppError.message("Claude 回复过长，请缩短请求后重试。") }
        return String(decoding: data, as: UTF8.self)
    }

    private static func responseError(_ data: Data) -> Error {
        // Never surface raw subprocess output: it may contain private prompts, auth URLs, or credentials.
        let text = String(decoding: data.prefix(4_000_000), as: UTF8.self).lowercased()
        if ["rate_limit", "rate limit", "usage limit", "exceeded", "out of extra usage"].contains(where: text.contains) {
            return AppError.message("Claude 订阅额度暂不可用，请稍后重试。不会自动切换到 API。")
        }
        if ["authentication", "not logged in", "login expired", "unauthorized", "invalid api key"].contains(where: text.contains) {
            return AppError.message("Claude 授权已失效，请在设置中重新连接。不会自动切换到 API。")
        }
        return AppError.message("Claude 请求未完成，请重试。不会自动切换到 API。")
    }

    fileprivate static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

@MainActor private struct ClaudeAccountStatus {
    var connected: Bool
    var label: String

    static func parse(_ result: ClaudeCommandResult, configDirectory: URL) throws -> Self {
        guard result.stdout.count <= 64_000,
              let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              let loggedIn = ClaudeClient.boolean(object["loggedIn"]), let method = object["authMethod"] as? String else {
            throw AppError.message("无法确认 Claude 登录方式，请重新连接。")
        }
        if let value = object["configDirectory"] {
            guard let reportedDirectory = value as? String,
                  URL(fileURLWithPath: reportedDirectory).standardizedFileURL.path == configDirectory.standardizedFileURL.path else {
                throw AppError.message("Claude 登录配置不匹配，请重新连接。")
            }
        }
        let providerValid = object["apiProvider"] == nil || object["apiProvider"] as? String == "firstParty"
        guard method == "none" || method == "claude.ai", providerValid else {
            throw AppError.message("此连接仅接受 Claude 订阅登录，未发送请求，也不会使用 API 凭据。")
        }
        if !loggedIn, method == "none", result.exitCode == 0 || result.exitCode == 1 {
            return Self(connected: false, label: "尚未登录")
        }
        guard loggedIn, method == "claude.ai", result.exitCode == 0 else {
            throw AppError.message("无法确认 Claude 订阅登录，请重新连接。")
        }
        if let plan = object["subscriptionType"], !(plan is NSNull) {
            guard let plan = plan as? String, ["pro", "max", "team", "enterprise"].contains(plan.lowercased()) else {
                throw AppError.message("此账号未显示受支持的 Claude 订阅，请使用支持 Claude Code 的订阅账号。")
            }
        }
        let email = (object["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(connected: true, label: email.isEmpty ? "已连接 Claude" : String(email.prefix(254)))
    }
}

@MainActor final class ClaudeProcessRunner: ClaudeCommandRunning {
    private var operations: [UUID: ClaudeProcessOperation] = [:]

    func run(_ request: ClaudeCommandRequest) async throws -> ClaudeCommandResult {
        try Task.checkCancellation()
        let operation = ClaudeProcessOperation(request)
        operations[request.id] = operation
        defer { operations.removeValue(forKey: request.id) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start { continuation.resume(with: $0) }
            }
        } onCancel: {
            operation.stop(CancellationError())
        }
    }

    func cancel(_ id: UUID) { operations[id]?.stop(CancellationError()) }
    func cancelAll() { for operation in operations.values { operation.stop(CancellationError()) } }
}

/// Pipe I/O and waiting happen off the main actor. Each process has bounded output and a kill deadline.
private final class ClaudeProcessOperation: @unchecked Sendable {
    private let request: ClaudeCommandRequest
    private let process = Process()
    private let lock = NSLock()
    private var stdout = Data(), stderr = Data()
    private var failure: Error?
    private var started = false, finished = false

    init(_ request: ClaudeCommandRequest) { self.request = request }

    func start(_ completion: @escaping (Result<ClaudeCommandResult, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { self.execute(completion) }
    }

    func stop(_ error: Error) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if failure == nil { failure = error }
        let running = started && process.isRunning
        if running { process.terminate() }
        lock.unlock()
        if running {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
                lock.lock(); defer { lock.unlock() }
                if started, !finished, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    private func execute(_ completion: @escaping (Result<ClaudeCommandResult, Error>) -> Void) {
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.workingDirectory
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        lock.lock()
        if let failure { finished = true; lock.unlock(); completion(.failure(failure)); return }
        do { try process.run(); started = true; lock.unlock() }
        catch { finished = true; lock.unlock(); completion(.failure(AppError.message("无法启动 Claude 运行组件，请更新 Mac 开发版。"))); return }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        let reads = DispatchGroup()
        drain(output.fileHandleForReading, isError: false, group: reads)
        drain(errors.fileHandleForReading, isError: true, group: reads)
        DispatchQueue.global(qos: .userInitiated).async { [request] in
            let handle = input.fileHandleForWriting
            _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? handle.write(contentsOf: request.input)
            try? handle.close()
        }
        let timeout = DispatchWorkItem { [self] in stop(AppError.message("Claude 请求超时，请重试。")) }
        DispatchQueue.global().asyncAfter(deadline: .now() + request.timeout, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        if reads.wait(timeout: .now() + 2) == .timedOut {
            stop(AppError.message("Claude 未正常结束输出，请重试。"))
        }
        lock.lock()
        finished = true
        let result: Result<ClaudeCommandResult, Error>
        if let failure { result = .failure(failure) }
        else { result = .success(ClaudeCommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)) }
        lock.unlock()
        completion(result)
    }

    private func drain(_ handle: FileHandle, isError: Bool, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { try? handle.close(); group.leave() }
            while let chunk = try? handle.read(upToCount: 32_768), !chunk.isEmpty {
                lock.lock()
                let limit = isError ? 64_000 : request.outputLimit
                let count = isError ? stderr.count : stdout.count
                let exceedsLimit = chunk.count > limit - count
                let kept = chunk.prefix(max(0, limit - count))
                if isError { stderr.append(contentsOf: kept) } else { stdout.append(contentsOf: kept) }
                lock.unlock()
                if exceedsLimit { stop(AppError.message("Claude 输出过长，请缩短请求后重试。")) }
            }
        }
    }
}
