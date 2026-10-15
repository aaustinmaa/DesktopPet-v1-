import Foundation
import Testing
@testable import SuWuDu

@MainActor private final class ModelClaudeRunner: ClaudeCommandRunning {
    var requests: [ClaudeCommandRequest] = []
    var status = #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"pro","email":"model@example.test"}"#
    var entries = ClaudeModelTests.entries
    var catalogFails = false

    func run(_ request: ClaudeCommandRequest) async throws -> ClaudeCommandResult {
        requests.append(request)
        if request.arguments.contains("status") { return .init(stdout: Data(status.utf8), exitCode: 0) }
        if request.arguments.contains("login") || request.arguments.contains("logout") {
            return .init(stdout: Data(), exitCode: 0)
        }
        let input = try #require(JSONSerialization.jsonObject(with: request.input) as? [String: Any])
        if input["type"] as? String == "control_request" {
            if catalogFails { return .init(stdout: Data("private-error-token".utf8), exitCode: 1) }
            return try ClaudeModelTests.catalog(entries, requestID: #require(input["request_id"] as? String))
        }
        return .init(stdout: Data(#"{"type":"result","subtype":"success","is_error":false,"structured_output":{"reply":"hello"}}"#.utf8), exitCode: 0)
    }
    func cancel(_ id: UUID) {}
    func cancelAll() {}
}

@MainActor struct ClaudeModelTests {
    static let entries: [[String: Any]] = [
        ["value": "default", "displayName": "Default (recommended)", "resolvedModel": "claude-sonnet-test", "supportsEffort": true, "supportedEffortLevels": ["low", "high"]],
        ["value": "opus", "displayName": "Opus", "resolvedModel": "claude-opus-test", "supportsEffort": true, "supportedEffortLevels": ["low", "medium", "high", "xhigh", "max", "ultracode"]],
        ["value": "haiku", "displayName": "Haiku", "supportsEffort": false]
    ]

    static func catalog(_ entries: [[String: Any]], requestID: String = "test-models") throws -> ClaudeCommandResult {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "control_response", "response": [
                "subtype": "success", "request_id": requestID, "response": ["models": entries]
            ]
        ])
        return .init(stdout: data, exitCode: 0)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-model-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func client(_ runner: ModelClaudeRunner, at directory: URL) -> ClaudeClient {
        ClaudeClient(executable: URL(fileURLWithPath: "/usr/bin/true"), applicationDirectory: directory,
            environment: ["HOME": directory.path, "ANTHROPIC_API_KEY": "must-not-use"], runner: runner)
    }

    private let schema: [String: Any] = ["type": "object", "properties": ["reply": ["type": "string"]], "required": ["reply"], "additionalProperties": false]

    @Test func catalogUsesRuntimeModelsAndEachModelsEffortCapabilities() throws {
        var result = try Self.catalog(Self.entries)
        result.stdout = Data(#"{"type":"system","subtype":"ui_invalidate"}"#.utf8) + Data([0x0A]) + result.stdout
        let models = try ClaudeModel.parseCatalog(result, requestID: "test-models")
        #expect(models.map(\.id) == ["", "opus", "haiku"])
        #expect(models[0].name == "默认")
        #expect(models[0].efforts == ["low", "high"])
        #expect(models[1].efforts == ["low", "medium", "high", "xhigh", "max"])
        #expect(models[2].efforts.isEmpty)
    }

    @Test func paidAndUnavailableVariantsAreNotOfferedAsSubscriptionModels() throws {
        let excluded: [[String: Any]] = [
            ["value": "fable", "displayName": "Fable"],
            ["value": "best", "displayName": "Best", "resolvedModel": "claude-fable-test"],
            ["value": "best-unknown", "displayName": "Unknown", "requiresUsageCredits": true],
            ["value": "sonnet[1m]", "displayName": "Sonnet extended"],
            ["value": "unavailable", "displayName": "Unavailable", "disabled": true]
        ]
        let models = try ClaudeModel.parseCatalog(Self.catalog(Self.entries + excluded), requestID: "test-models")
        #expect(models.map(\.id) == ["", "opus", "haiku"])
        let unsafeDefault: [[String: Any]] = [["value": "default", "displayName": "Default", "resolvedModel": "claude-fable-test"]]
        let safe = try ClaudeModel.parseCatalog(Self.catalog(unsafeDefault + [Self.entries[1]]), requestID: "test-models")
        #expect(safe.map(\.id) == ["opus"])
    }

    @Test func catalogRejectsBadResponsesWithoutLeakingRuntimeDetails() throws {
        let valid = try Self.catalog(Self.entries)
        let badResults = [
            ClaudeCommandResult(stdout: valid.stdout, exitCode: 1),
            try Self.catalog(Self.entries, requestID: "other"),
            ClaudeCommandResult(stdout: valid.stdout + Data([0x0A]) + valid.stdout, exitCode: 0),
            ClaudeCommandResult(stdout: Data(#"{"type":"control_response","response":{"subtype":"error","request_id":"test-models","error":"secret-token"}}"#.utf8), exitCode: 0),
            ClaudeCommandResult(stdout: Data(repeating: 0x20, count: 1_000_001), exitCode: 0),
            try Self.catalog([]),
            try Self.catalog([Self.entries[0], Self.entries[0]]),
            try Self.catalog([["value": "--model", "displayName": "Invalid"]]),
            try Self.catalog([["value": "opus", "displayName": "Opus", "supportsEffort": 1]]),
            try Self.catalog([["value": "opus", "displayName": "Opus", "supportedEffortLevels": "high"]]),
            try Self.catalog([["value": "opus", "displayName": "Opus", "requiresUsageCredits": "true"]])
        ]
        for result in badResults {
            do {
                _ = try ClaudeModel.parseCatalog(result, requestID: "test-models")
                Issue.record("Expected invalid catalog rejection")
            } catch {
                #expect(!error.localizedDescription.contains("secret-token"))
            }
        }
    }

    @Test func refreshingModelsUsesOnlyTheInitializeControlRequest() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ModelClaudeRunner(), client = client(runner, at: directory)
        try await client.refresh()
        #expect(client.signedIn)
        #expect(client.models.count == 3)
        #expect(runner.requests.count == 2)
        let request = runner.requests[1]
        let input = try #require(JSONSerialization.jsonObject(with: request.input) as? [String: Any])
        #expect(input["type"] as? String == "control_request")
        #expect((input["request"] as? [String: Any])?["subtype"] as? String == "initialize")
        #expect(input["message"] == nil)
        #expect(!request.arguments.contains("--json-schema"))
        #expect(!request.arguments.contains("--model"))
        #expect(request.environment["ANTHROPIC_API_KEY"] == nil)
    }

    @Test func explicitModelAndEffortAreValidatedThenForwardedToTheOfficialCLI() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ModelClaudeRunner(), client = client(runner, at: directory)
        _ = try await client.structuredReply("memo", instructions: "protocol", schema: schema, model: "opus", effort: "xhigh")
        #expect(runner.requests.count == 3)
        let arguments = runner.requests[2].arguments
        #expect(arguments[try #require(arguments.firstIndex(of: "--model")) + 1] == "opus")
        #expect(arguments[try #require(arguments.firstIndex(of: "--effort")) + 1] == "xhigh")
        #expect(!arguments.contains("--fallback-model"))
    }

    @Test func defaultModelEffortUsesTheDefaultEntryCapabilities() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ModelClaudeRunner(), client = client(runner, at: directory)
        _ = try await client.structuredReply("memo", instructions: "protocol", schema: schema, effort: "high")
        #expect(!runner.requests[2].arguments.contains("--model"))
        #expect(runner.requests[2].arguments.contains("--effort"))
        await #expect(throws: (any Error).self) {
            try await client.structuredReply("memo", instructions: "protocol", schema: schema, effort: "xhigh")
        }
        #expect(runner.requests.count == 4)
    }

    @Test func defaultSelectionsValidateCatalogWithoutOverridingRuntimeDefaults() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ModelClaudeRunner(), client = client(runner, at: directory)
        _ = try await client.structuredReply("memo", instructions: "protocol", schema: schema, model: "", effort: "")
        #expect(runner.requests.count == 3)
        #expect(!runner.requests[2].arguments.contains("--model"))
        #expect(!runner.requests[2].arguments.contains("--effort"))
    }

    @Test func unsafeOrMissingDefaultStopsBeforeInference() async throws {
        let defaults: [[String: Any]] = [
            ["value": "default", "displayName": "Default", "resolvedModel": "claude-fable-test"],
            ["value": "default", "displayName": "Default", "requiresUsageCredits": true],
            ["value": "default", "displayName": "Default", "disabled": true],
            ["value": "haiku", "displayName": "Haiku"]
        ]
        for defaultEntry in defaults {
            let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
            let runner = ModelClaudeRunner(), client = client(runner, at: directory)
            runner.entries = [defaultEntry, Self.entries[1]]
            await #expect(throws: (any Error).self) {
                try await client.structuredReply("private memo", instructions: "protocol", schema: schema)
            }
            #expect(runner.requests.count == 2)
            #expect(!runner.requests.contains { String(decoding: $0.input, as: UTF8.self).contains("private memo") })
        }
    }

    @Test func invalidOrUnavailableSelectionsStopBeforeInference() async throws {
        for (model, effort) in [("unknown", ""), ("fable", ""), ("opus", "ultracode"), ("haiku", "high")] {
            let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
            let runner = ModelClaudeRunner(), client = client(runner, at: directory)
            await #expect(throws: (any Error).self) {
                try await client.structuredReply("private memo", instructions: "protocol", schema: schema, model: model, effort: effort)
            }
            #expect(runner.requests.count == 2)
            #expect(!runner.requests.contains { String(decoding: $0.input, as: UTF8.self).contains("private memo") })
        }
    }

    @Test func previouslyRefreshedCatalogIsReusedAndClearedOnSignOut() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ModelClaudeRunner(), client = client(runner, at: directory)
        try await client.refresh()
        _ = try await client.structuredReply("memo", instructions: "protocol", schema: schema, model: "opus")
        #expect(runner.requests.count == 4)
        #expect(!runner.requests[3].arguments.contains("--effort"))
        try await client.logout()
        #expect(client.models.isEmpty)
        #expect(!client.signedIn)
    }

    @Test func catalogFailuresPreserveSuccessfulAuthentication() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ModelClaudeRunner(), client = client(runner, at: directory)
        try await client.refresh()
        runner.catalogFails = true
        await #expect(throws: (any Error).self) { try await client.refresh() }
        #expect(client.signedIn)
        #expect(client.account == "model@example.test")
        #expect(client.models.isEmpty)
        await #expect(throws: (any Error).self) { try await client.login() }
        #expect(client.signedIn)
        #expect(!client.loginPending)
        #expect(client.models.isEmpty)
    }

    @Test func missingAuthenticationClearsModelsAndSkipsCatalog() async throws {
        let directory = try directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let runner = ModelClaudeRunner(), client = client(runner, at: directory)
        try await client.refresh()
        runner.status = #"{"loggedIn":false,"authMethod":"none"}"#
        try await client.refresh()
        #expect(client.models.isEmpty)
        #expect(!client.signedIn)
        #expect(runner.requests.count == 3)
    }
}
