import Foundation
import Testing
@testable import SuWuDu

@MainActor private final class FakeClaudeRunner: ClaudeCommandRunning {
    var requests: [ClaudeCommandRequest] = []
    var results: [ClaudeCommandResult]
    var suspendedLogin: CheckedContinuation<ClaudeCommandResult, Error>?
    var waitForLogin = false
    var cancelled: [UUID] = []
    var cancelAllCount = 0

    init(_ results: [ClaudeCommandResult] = []) { self.results = results }
    func run(_ request: ClaudeCommandRequest) async throws -> ClaudeCommandResult {
        requests.append(request)
        if waitForLogin, request.arguments.contains("login") {
            return try await withCheckedThrowingContinuation { suspendedLogin = $0 }
        }
        guard !results.isEmpty else { throw AppError.message("Missing test response") }
        return results.removeFirst()
    }
    func cancel(_ id: UUID) {
        cancelled.append(id)
        suspendedLogin?.resume(throwing: CancellationError()); suspendedLogin = nil
    }
    func cancelAll() {
        cancelAllCount += 1
        suspendedLogin?.resume(throwing: CancellationError()); suspendedLogin = nil
    }
}

@MainActor final class ClaudeClientTests {
    private let signedIn = ClaudeCommandResult(stdout: Data(#"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"pro","email":"person@example.test"}"#.utf8), exitCode: 0)
    private let disconnected = ClaudeCommandResult(stdout: Data(#"{"loggedIn":false,"authMethod":"none","apiProvider":"firstParty"}"#.utf8), exitCode: 1)
    private let answer = ClaudeCommandResult(stdout: Data(#"{"type":"result","subtype":"success","is_error":false,"structured_output":{"reply":"hello"}}"#.utf8), exitCode: 0)
    private let schema: [String: Any] = ["type": "object", "properties": ["reply": ["type": "string"]], "required": ["reply"], "additionalProperties": false]

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-client-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func client(_ runner: FakeClaudeRunner, directory: URL) -> ClaudeClient {
        ClaudeClient(executable: URL(fileURLWithPath: "/usr/bin/true"), applicationDirectory: directory,
            environment: ["HOME": directory.path, "ANTHROPIC_API_KEY": "must-not-inherit"], runner: runner)
    }

    @Test func subprocessEnvironmentExcludesPaidCredentialsAndInjection() {
        let directory = URL(fileURLWithPath: "/tmp/isolated-claude")
        let source = ["HOME": "/Users/test", "USER": "test", "PATH": "/malicious/bin", "LANG": "en_US.UTF-8",
            "ANTHROPIC_API_KEY": "secret", "ANTHROPIC_AUTH_TOKEN": "secret", "ANTHROPIC_PROFILE": "paid",
            "CLAUDE_CODE_OAUTH_TOKEN": "secret", "CLAUDE_CODE_USE_BEDROCK": "1", "AWS_PROFILE": "paid",
            "CLAUDE_CONFIG_DIR": "/other/config", "NODE_OPTIONS": "--require malicious.js", "BASH_ENV": "script",
            "ANTHROPIC_BASE_URL": "https://proxy.test", "OPENAI_API_KEY": "secret", "CLAUDE_CODE_SIMPLE": "1"]
        let result = ClaudeClient.environment(source, configDirectory: directory)
        #expect(result["HOME"] == "/Users/test")
        #expect(result["LANG"] == "en_US.UTF-8")
        #expect(result["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(result["CLAUDE_CONFIG_DIR"] == directory.path)
        #expect(result["CLAUDE_CODE_DISABLE_FAST_MODE"] == "1")
        #expect(result["DISABLE_UPDATES"] == "1")
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_USE_BEDROCK", "AWS_PROFILE", "NODE_OPTIONS", "BASH_ENV", "ANTHROPIC_BASE_URL", "OPENAI_API_KEY", "CLAUDE_CODE_SIMPLE"] {
            #expect(result[key] == nil)
        }
    }

    @Test func refreshingWithoutCredentialsIsNormalAndDoesNotStartLogin() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = FakeClaudeRunner([disconnected])
        let client = client(runner, directory: directory)
        try await client.refresh()
        #expect(!client.signedIn)
        #expect(client.account == "未连接 Claude 订阅")
        #expect(runner.requests.count == 1)
        #expect(runner.requests[0].arguments.suffix(3) == ["auth", "status", "--json"])
        #expect(!runner.requests[0].arguments.contains("login"))
    }

    @Test func loginUsesOfficialSubscriptionFlowAndThenChecksIdentity() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = FakeClaudeRunner([.init(stdout: Data(), exitCode: 0), signedIn])
        let client = client(runner, directory: directory)
        try await client.login()
        #expect(client.signedIn)
        #expect(client.account == "person@example.test")
        #expect(!client.loginPending)
        #expect(runner.requests.count == 2)
        #expect(runner.requests[0].arguments.suffix(3) == ["auth", "login", "--claudeai"])
        #expect(runner.requests[0].timeout == 300)
        #expect(runner.requests.allSatisfy { !$0.arguments.contains("--console") && !$0.arguments.contains("setup-token") })
        #expect(runner.requests[0].environment["CLAUDE_CONFIG_DIR"] == directory.appendingPathComponent("Claude").path)
        #expect(runner.requests[0].environment["ANTHROPIC_API_KEY"] == nil)
    }

    @Test func paidOrUnconfirmedIdentityStopsBeforeSendingPrompt() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let statuses = [
            #"{"loggedIn":true,"authMethod":"api_key","apiProvider":"firstParty"}"#,
            #"{"loggedIn":true,"authMethod":"api_key_helper","apiProvider":"firstParty"}"#,
            #"{"loggedIn":true,"authMethod":"oauth_token","apiProvider":"firstParty"}"#,
            #"{"loggedIn":true,"authMethod":"third_party","apiProvider":"bedrock"}"#,
            #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"vertex"}"#,
            #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":false}"#,
            #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"free"}"#,
            #"{"loggedIn":true,"authMethod":"claude.ai","configDirectory":"/somebody-else"}"#,
            #"{"loggedIn":true,"authMethod":"claude.ai","configDirectory":false}"#,
            #"{"loggedIn":1,"authMethod":"claude.ai"}"#,
            #"{"loggedIn":true,"authMethod":"future-unknown-login"}"#
        ]
        for status in statuses {
            let runner = FakeClaudeRunner([.init(stdout: Data(status.utf8), exitCode: 0)])
            let client = client(runner, directory: directory)
            await #expect(throws: (any Error).self) { try await client.structuredReply("private memo", instructions: "test", schema: schema) }
            #expect(!client.signedIn)
            #expect(runner.requests.count == 1)
            #expect(runner.requests[0].input.isEmpty)
        }
    }

    @Test func everyInferenceRechecksAuthenticationAndKeepsPromptOffArguments() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = FakeClaudeRunner([signedIn, answer, disconnected])
        let client = client(runner, directory: directory)
        #expect(try await client.structuredReply("private memo", instructions: "protocol", schema: schema) == #"{"reply":"hello"}"#)
        await #expect(throws: (any Error).self) { try await client.structuredReply("second memo", instructions: "protocol", schema: schema) }
        #expect(runner.requests.count == 3)
        #expect(runner.requests[0].arguments.contains("status"))
        #expect(runner.requests[2].arguments.contains("status"))
        let inference = runner.requests[1]
        #expect(!inference.arguments.contains("private memo"))
        #expect(String(decoding: inference.input, as: UTF8.self).contains("private memo"))
        #expect(inference.arguments.contains("--safe-mode"))
        #expect(!inference.arguments.contains("--bare"))
        #expect(inference.arguments.contains("--no-session-persistence"))
        #expect(inference.arguments.contains("--strict-mcp-config"))
        #expect(inference.arguments.contains("--disable-slash-commands"))
        let toolsIndex = try #require(inference.arguments.firstIndex(of: "--tools"))
        #expect(inference.arguments[toolsIndex + 1] == "")
        let settingsIndex = try #require(inference.arguments.firstIndex(of: "--setting-sources"))
        #expect(inference.arguments[settingsIndex + 1] == "")
        let schemaIndex = try #require(inference.arguments.firstIndex(of: "--json-schema"))
        let sentSchema = try JSONSerialization.jsonObject(with: Data(inference.arguments[schemaIndex + 1].utf8)) as? NSDictionary
        #expect(sentSchema == schema as NSDictionary)
        #expect(!inference.arguments.contains("--max-budget-usd"))
    }

    @Test func screenshotIsEncodedAsImageDataWithTextAndNoFileTool() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let screenshot = directory.appendingPathComponent("shot.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
        try bytes.write(to: screenshot)
        let input = try ClaudeClient.input(prompt: "describe", screenshot: screenshot)
        let object = try #require(JSONSerialization.jsonObject(with: input) as? [String: Any])
        #expect(object["type"] as? String == "user")
        let message = try #require(object["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["text"] as? String == "describe")
        #expect(content[1]["type"] as? String == "image")
        let source = try #require(content[1]["source"] as? [String: Any])
        #expect(source["media_type"] as? String == "image/png")
        #expect(source["data"] as? String == bytes.base64EncodedString())
        #expect(!String(decoding: input, as: UTF8.self).contains(screenshot.path))
        try Data("not an image".utf8).write(to: screenshot)
        #expect(throws: (any Error).self) { try ClaudeClient.input(prompt: "describe", screenshot: screenshot) }
    }

    @Test func resultParserRequiresOneSuccessfulStructuredResult() throws {
        let prefix = #"{"type":"system","subtype":"init"}"# + "\n"
        let good = String(decoding: answer.stdout, as: UTF8.self)
        #expect(try ClaudeClient.structuredOutput(.init(stdout: Data((prefix + good + "\n").utf8), exitCode: 0)) == #"{"reply":"hello"}"#)
        for raw in [
            "", prefix, good + "\n" + good,
            #"{"type":"result","subtype":"success","is_error":true,"structured_output":{"reply":"bad"}}"#,
            #"{"type":"result","subtype":"error_max_turns","is_error":false,"structured_output":{"reply":"bad"}}"#,
            #"{"type":"result","subtype":"success","is_error":0,"structured_output":{"reply":"bad"}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"{\"reply\":\"fallback\"}"}"#,
            #"{"type":"result","subtype":"success","is_error":false,"structured_output":[]}"#,
            good + "\nnot json", "```json\n" + good + "\n```"
        ] {
            #expect(throws: (any Error).self) { try ClaudeClient.structuredOutput(.init(stdout: Data(raw.utf8), exitCode: 0)) }
        }
        #expect(throws: (any Error).self) { try ClaudeClient.structuredOutput(.init(stdout: answer.stdout, exitCode: 1)) }
    }

    @Test func runtimeErrorsNeverEchoPrivateOutput() {
        let raw = #"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"rate_limit secret-memo-and-auth-token"}"#
        do {
            _ = try ClaudeClient.structuredOutput(.init(stdout: Data(raw.utf8), exitCode: 1))
            Issue.record("Expected a failure")
        } catch {
            #expect(!error.localizedDescription.contains("secret-memo-and-auth-token"))
            #expect(error.localizedDescription.contains("不会自动切换到 API"))
        }
    }

    @Test func cancellingBrowserLoginStopsOwnedProcessAndResetsState() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = FakeClaudeRunner()
        runner.waitForLogin = true
        let client = client(runner, directory: directory)
        let task = Task { try await client.login() }
        for _ in 0..<100 where runner.suspendedLogin == nil { await Task.yield() }
        #expect(client.loginPending)
        client.cancelLogin()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(runner.cancelled.count == 1)
        #expect(!client.loginPending)
        #expect(!client.signedIn)
        #expect(client.account == "已取消连接")
    }

    @Test func processRunnerCapturesBothPipesAndExitCode() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ClaudeProcessRunner()
        let request = ClaudeCommandRequest(id: UUID(), executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "cat; printf error >&2; exit 7"], environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: directory, input: Data("pipe input".utf8), timeout: 3)
        let result = try await runner.run(request)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "pipe input")
        #expect(String(decoding: result.stderr, as: UTF8.self) == "error")
        #expect(result.exitCode == 7)
    }

    @Test func processRunnerBoundsOutputAndTerminatesOnTimeout() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ClaudeProcessRunner()
        let flood = ClaudeCommandRequest(id: UUID(), executable: URL(fileURLWithPath: "/usr/bin/yes"),
            arguments: [], environment: [:], workingDirectory: directory, timeout: 3, outputLimit: 100)
        await #expect(throws: (any Error).self) { try await runner.run(flood) }
        let sleep = ClaudeCommandRequest(id: UUID(), executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"], environment: [:], workingDirectory: directory, timeout: 0.05)
        let start = Date()
        await #expect(throws: (any Error).self) { try await runner.run(sleep) }
        #expect(Date().timeIntervalSince(start) < 4)
    }

    @Test func processRunnerTaskCancellationStopsTheChild() async throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ClaudeProcessRunner()
        let request = ClaudeCommandRequest(id: UUID(), executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"], environment: [:], workingDirectory: directory, timeout: 20)
        let task = Task { try await runner.run(request) }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
