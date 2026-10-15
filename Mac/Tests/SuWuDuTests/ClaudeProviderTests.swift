import Foundation
import Testing
@testable import SuWuDu

@MainActor final class ClaudeProviderTests {
    private var settings: Settings {
        var value = Settings()
        value.provider = "claude"
        value.petName = "沈青"
        return value
    }
    private var memo: FocusMemoExtractionRequest {
        .init(sourceText: "CS341 - 8\nBuild personal website\n20\nNexo project",
              referenceDate: Date(timeIntervalSince1970: 1_792_000_000), timeZoneIdentifier: "America/Toronto")
    }
    private var matching: FocusMatchRequest {
        .init(instruction: "第一颗补课 10 分钟、网站 15 分钟", tasks: [
            .init(id: "course", title: "CS341"), .init(id: "site", title: "个人网站")
        ], sessions: [
            .init(id: "session-1", startedAt: Date(timeIntervalSince1970: 1_792_000_000),
                  completedAt: Date(timeIntervalSince1970: 1_792_001_500), notes: "补课、网站")
        ], timeZoneIdentifier: "America/Toronto")
    }

    @Test func chatUsesSubscriptionStructuredContractContextAndImage() async throws {
        let fixture = try Fixture(output: ["reply": "继续加油。", "emotion": "happy", "action": "heart"])
        defer { fixture.remove() }
        let image = fixture.directory.appendingPathComponent("screen.jpg")
        try Data([0xff, 0xd8, 0xff, 0xe0]).write(to: image)
        let reply = try await fixture.service.reply(text: "看看进度", context: "上次做到第二章", settings: settings,
                                                    screenshot: image, memoryReply: nil)
        #expect(reply.text == "继续加油。")
        #expect(reply.state == .heart)
        let request = try #require(fixture.runner.inferences.first)
        #expect(try request.value(after: "--system-prompt") == AIService.instructions("沈青"))
        #expect(try request.schema == NSDictionary(dictionary: AIService.companionSchema))
        let content = try request.content
        #expect((content.first?["text"] as? String)?.contains("上次做到第二章") == true)
        #expect((content.first?["text"] as? String)?.contains("看看进度") == true)
        #expect(content.last?["type"] as? String == "image")
        #expect((content.last?["source"] as? [String: Any])?["media_type"] as? String == "image/jpeg")
        #expect(fixture.runner.statusChecks == 1)
    }

    @Test func malformedStructuredChatNeverFallsBackToDisplayingJSON() async throws {
        let fixture = try Fixture(output: [:])
        defer { fixture.remove() }
        let invalidOutputs: [[String: Any]] = [
            [:], ["reply": "missing fields"],
            ["reply": " ", "emotion": "happy", "action": "none"],
            ["reply": "hello", "emotion": "unknown", "action": "none"],
            ["reply": "hello", "emotion": "happy", "action": "execute"],
            ["reply": "hello", "emotion": "happy", "action": "none", "extra": "value"]
        ]
        for output in invalidOutputs {
            fixture.runner.output = output
            let error = await errorText { _ = try await fixture.service.reply(text: "hello", context: "", settings: settings, screenshot: nil, memoryReply: nil) }
            #expect(error.contains("Claude 聊天回复格式无效"))
        }
    }

    @Test func memoUsesExistingInstructionsAndSchemaThenLocalValidation() async throws {
        let fixture = try Fixture(output: ["tasks": [[
            "title": "CS341", "estimatedPomodoros": 8, "dueDate": NSNull(), "dueTime": NSNull(),
            "notes": "", "sourceExcerpt": "CS341 - 8"
        ]]])
        defer { fixture.remove() }
        let proposals = try await fixture.service.extractMemoTasks(memo, settings: settings)
        #expect(proposals.count == 1)
        #expect(proposals.first?.estimatedPomodoros == 8)
        let request = try #require(fixture.runner.inferences.first)
        #expect(try request.value(after: "--system-prompt") == FocusMemoExtraction.instructions)
        #expect(try request.schema == NSDictionary(dictionary: FocusMemoExtraction.schema))
        #expect(try request.content.count == 1)
        #expect(try request.content.first?["text"] as? String == FocusMemoExtraction.prompt(memo))
        fixture.runner.output = ["tasks": [["title": "Invented", "estimatedPomodoros": 1]]]
        await #expect(throws: (any Error).self) { try await fixture.service.extractMemoTasks(memo, settings: settings) }
        #expect(fixture.runner.statusChecks == 2)
    }

    @Test func matchingUsesExistingSnapshotAndRejectsUnknownTaskIDs() async throws {
        let fixture = try Fixture(output: ["matches": [["sessionID": "session-1", "allocations": [
            ["taskID": "course", "share": 0.4], ["taskID": "site", "share": 0.6]
        ], "reason": "10 / 15 分钟"]]])
        defer { fixture.remove() }
        let proposals = try await fixture.service.matchFocusTasks(matching, settings: settings)
        #expect(proposals.count == 1)
        #expect(proposals.first?.allocations == [.init(taskID: "course", share: 0.4), .init(taskID: "site", share: 0.6)])
        let request = try #require(fixture.runner.inferences.first)
        #expect(try request.value(after: "--system-prompt") == FocusTaskMatching.instructions)
        #expect(try request.schema == NSDictionary(dictionary: FocusTaskMatching.schema(for: matching)))
        #expect(try request.content.count == 1)
        #expect(try request.content.first?["text"] as? String == FocusTaskMatching.prompt(matching))
        fixture.runner.output = ["matches": [["sessionID": "session-1", "allocations": [
            ["taskID": "unknown", "share": 1]
        ], "reason": "invented"]]]
        await #expect(throws: (any Error).self) { try await fixture.service.matchFocusTasks(matching, settings: settings) }
        #expect(fixture.runner.statusChecks == 2)
    }

    @Test func everyFeatureRejectsAPIAuthenticationBeforeInference() async throws {
        let fixture = try Fixture(output: [:])
        defer { fixture.remove() }
        fixture.runner.status = ["loggedIn": true, "authMethod": "api_key", "apiProvider": "firstParty"]
        let a = await errorText { _ = try await fixture.service.reply(text: "hello", context: "", settings: settings, screenshot: nil, memoryReply: nil) }
        let b = await errorText { _ = try await fixture.service.extractMemoTasks(memo, settings: settings) }
        let c = await errorText { _ = try await fixture.service.matchFocusTasks(matching, settings: settings) }
        for error in [a, b, c] { #expect(error.contains("仅接受 Claude 订阅")) }
        #expect(fixture.runner.statusChecks == 3)
        #expect(fixture.runner.inferences.isEmpty)
    }

    @Test func quotaFailurePropagatesWithoutChangingProviderOrRetryingElsewhere() async throws {
        let fixture = try Fixture(output: [:])
        defer { fixture.remove() }
        fixture.runner.failure = "rate_limit_error"
        let a = await errorText { _ = try await fixture.service.reply(text: "hello", context: "", settings: settings, screenshot: nil, memoryReply: nil) }
        let b = await errorText { _ = try await fixture.service.extractMemoTasks(memo, settings: settings) }
        let c = await errorText { _ = try await fixture.service.matchFocusTasks(matching, settings: settings) }
        for error in [a, b, c] { #expect(error.contains("Claude 订阅额度")); #expect(error.contains("不会自动切换到 API")) }
        #expect(fixture.runner.statusChecks == 3)
        #expect(fixture.runner.inferences.count == 3)
        #expect(settings.provider == "claude")
    }

    @Test func providerSurvivesSettingsRoundTripAndOldSettingsNeedNoMigration() throws {
        for provider in ["claude", "codex", "openai", "offline"] {
            var original = Settings()
            original.provider = provider
            original.normalize()
            var restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(original))
            restored.normalize()
            #expect(restored == original)
            #expect(restored.provider == provider)
        }
    }

    private func errorText(_ body: () async throws -> Void) async -> String {
        do { try await body(); Issue.record("Expected a Claude-specific failure"); return "" }
        catch { return error.localizedDescription }
    }

    @MainActor private final class Fixture {
        let directory: URL
        let runner: ProviderRunner
        let service: AIService
        init(output: [String: Any]) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-provider-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            runner = ProviderRunner(output: output)
            service = AIService(claude: ClaudeClient(executable: URL(fileURLWithPath: "/usr/bin/true"),
                applicationDirectory: directory, environment: ["HOME": directory.path], runner: runner))
        }
        func remove() { service.claude.shutdown(); try? FileManager.default.removeItem(at: directory) }
    }
}

@MainActor private final class ProviderRunner: ClaudeCommandRunning {
    var requests: [ClaudeCommandRequest] = []
    var output: [String: Any]
    var failure: String?
    var status: [String: Any] = ["loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty", "subscriptionType": "pro"]
    var statusChecks: Int { requests.filter { $0.arguments.contains("status") }.count }
    var inferences: [ClaudeCommandRequest] { requests.filter { $0.arguments.contains("-p") } }
    init(output: [String: Any]) { self.output = output }
    func run(_ request: ClaudeCommandRequest) async throws -> ClaudeCommandResult {
        requests.append(request)
        if request.arguments.contains("status") {
            return .init(stdout: try JSONSerialization.data(withJSONObject: status), exitCode: 0)
        }
        let result: [String: Any]
        if let failure { result = ["type": "result", "subtype": "error_during_execution", "is_error": true, "errors": [failure]] }
        else { result = ["type": "result", "subtype": "success", "is_error": false, "structured_output": output] }
        return .init(stdout: try JSONSerialization.data(withJSONObject: result), exitCode: failure == nil ? 0 : 1)
    }
    func cancel(_ id: UUID) { }
    func cancelAll() { }
}

private extension ClaudeCommandRequest {
    func value(after flag: String) throws -> String {
        let index = try #require(arguments.firstIndex(of: flag))
        return try #require(arguments.dropFirst(index + 1).first)
    }
    var schema: NSDictionary {
        get throws { try #require(JSONSerialization.jsonObject(with: Data(value(after: "--json-schema").utf8)) as? NSDictionary) }
    }
    var content: [[String: Any]] {
        get throws {
            let message = try #require(JSONSerialization.jsonObject(with: input) as? [String: Any])
            let body = try #require(message["message"] as? [String: Any])
            return try #require(body["content"] as? [[String: Any]])
        }
    }
}
