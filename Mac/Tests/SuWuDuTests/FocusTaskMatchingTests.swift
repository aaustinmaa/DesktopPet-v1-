import Foundation
import Testing
@testable import SuWuDu

final class FocusTaskMatchingTests {
    private var tasks: [FocusMatchTask] {
        [FocusMatchTask(id: "course", title: "CS370 补课", notes: "看录播"),
         FocusMatchTask(id: "site", title: "个人网站")]
    }
    private var request: FocusMatchRequest {
        FocusMatchRequest(instruction: "第一颗补课和个人网站各一半，第二颗个人网站", tasks: tasks, sessions: [
            FocusMatchSession(id: "first", startedAt: Date(timeIntervalSince1970: 1_792_000_000),
                completedAt: Date(timeIntervalSince1970: 1_792_001_500), notes: "录播",
                allocations: [.init(taskID: "site", share: 1)], assignmentRevision: 2),
            FocusMatchSession(id: "second", startedAt: Date(timeIntervalSince1970: 1_792_001_800),
                completedAt: Date(timeIntervalSince1970: 1_792_003_300), notes: "首页")
        ], timeZoneIdentifier: "America/Toronto")
    }

    @Test func proposalsRetainBeforeStateAndDoNotEditTheSnapshot() throws {
        let snapshot = request
        let raw = #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"site","share":1}],"reason":"第二颗做网站"},{"sessionID":"first","allocations":[{"taskID":"site","share":0.5},{"taskID":"course","share":0.5}],"reason":"明确修正第一颗"}]}"#
        let proposals = try FocusTaskMatching.parse(raw, request: snapshot)
        #expect(proposals.map(\.sessionID) == ["first", "second"])
        #expect(proposals.first?.previousAllocations == [.init(taskID: "site", share: 1)])
        #expect(proposals.first?.allocations == [.init(taskID: "course", share: 0.5), .init(taskID: "site", share: 0.5)])
        #expect(proposals.first?.previousRevision == 2)
        #expect(proposals.first?.previousNotes == "录播")
        #expect(snapshot.sessions.first?.allocations == [.init(taskID: "site", share: 1)])
        #expect(snapshot.sessions.last?.allocations.isEmpty == true)
    }

    @Test func normalizedOutputIsAcceptedIndependentlyOfUserWording() throws {
        let raw = #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"course","share":0.6},{"taskID":"site","share":0.4}],"reason":"按用户给出的比例分配"}]}"#
        for instruction in ["第二颗补课 60%，网站 40%", "第二颗补课与网站 3:2", "第二颗看了 15 分钟录播、改了 10 分钟首页", "Split the second session between course and site, 0.6 and 0.4."] {
            var snapshot = request
            snapshot.instruction = instruction
            let proposals = try FocusTaskMatching.parse(raw, request: snapshot)
            #expect(proposals.count == 1)
            #expect(proposals[0].allocations == [.init(taskID: "course", share: 0.6), .init(taskID: "site", share: 0.4)])
        }
    }

    @Test func rejectsUnknownDuplicateAndMalformedIDsWithoutReturningPartialMatches() {
        for raw in [
            #"{"matches":[{"sessionID":"unknown","allocations":[{"taskID":"site","share":1}],"reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"invented-task","share":1}],"reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"site","share":1}],"reason":"test"},{"sessionID":"second","allocations":[],"reason":"conflict"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"site","share":0.5},{"taskID":"site","share":0.5}],"reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"first","allocations":[{"taskID":"course","share":1}],"reason":"valid"},{"sessionID":"second","allocations":[{"taskID":"unknown","share":1}],"reason":"invalid"}]}"#,
            #"{"matches":[{"sessionID":1,"allocations":[],"reason":"test"}]}"#
        ] {
            #expect(throws: (any Error).self) { try FocusTaskMatching.parse(raw, request: request) }
        }
    }

    @Test func rejectsInvalidSharesAndUnnormalizedTotals() {
        for share in ["false", "true", "null", #""0.5""#, "0", "-0.1", "1.1", "50", "0.5", "1e309"] {
            let raw = "{\"matches\":[{\"sessionID\":\"second\",\"allocations\":[{\"taskID\":\"site\",\"share\":\(share)}],\"reason\":\"test\"}]}"
            #expect(throws: (any Error).self) { try FocusTaskMatching.parse(raw, request: request) }
        }
        for raw in [
            #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"course","share":0.4},{"taskID":"site","share":0.4}],"reason":"不足 100%"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"course","share":0.6},{"taskID":"site","share":0.6}],"reason":"超过 100%"}]}"#
        ] {
            #expect(throws: (any Error).self) { try FocusTaskMatching.parse(raw, request: request) }
        }
    }

    @Test func rejectsOldContractsMissingFieldsExtraFieldsAndOversizedResponses() {
        for raw in [
            #"{"matches":[{"sessionID":"second","taskID":"site","reason":"old contract"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":null,"reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[],"reason":""}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[],"reason":false}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[]}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[],"reason":"test","notes":"overwrite"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"site","share":1,"minutes":25}],"reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"site"}],"reason":"test"}]}"#,
            #"{"matches":[],"explanation":"extra"}"#,
            "{\"matches\":[{\"sessionID\":\"second\",\"allocations\":[],\"reason\":\"\(String(repeating: "a", count: 1_001))\"}]}",
            String(repeating: " ", count: 200_000) + #"{"matches":[]}"#,
            "```json\n{\"matches\":[]}\n```", "", "not JSON"
        ] {
            #expect(throws: (any Error).self) { try FocusTaskMatching.parse(raw, request: request) }
        }
    }

    @Test func acceptsThirdsWithRoundingButNotArbitraryWeights() throws {
        var snapshot = request
        snapshot.tasks.append(FocusMatchTask(id: "third", title: "第三项"))
        let raw = #"{"matches":[{"sessionID":"second","allocations":[{"taskID":"course","share":0.3333333},{"taskID":"site","share":0.3333333},{"taskID":"third","share":0.3333333}],"reason":"三个任务均分"}]}"#
        let proposals = try FocusTaskMatching.parse(raw, request: snapshot)
        #expect(proposals.count == 1)
        #expect(proposals[0].allocations.allSatisfy { abs($0.share - 1.0 / 3) < 1e-12 })
        #expect(abs(proposals[0].allocations.reduce(0) { $0 + $1.share } - 1) < 1e-12)
    }

    @Test func omissionClearingAndUnchangedAssignmentsHaveDistinctMeanings() throws {
        #expect(try FocusTaskMatching.parse(#"{"matches":[]}"#, request: request).isEmpty)
        #expect(try FocusTaskMatching.parse(#"{"matches":[{"sessionID":"first","allocations":[{"taskID":"site","share":1}],"reason":"原关联不变"}]}"#, request: request).isEmpty)
        let cleared = try FocusTaskMatching.parse(#"{"matches":[{"sessionID":"first","allocations":[],"reason":"用户要求清除"}]}"#, request: request)
        #expect(cleared.count == 1)
        #expect(cleared.first?.allocations.isEmpty == true)
        #expect(cleared.first?.previousAllocations == [.init(taskID: "site", share: 1)])
        var snapshot = request
        snapshot.sessions[0].allocations = [.init(taskID: "site", share: 0.4), .init(taskID: "course", share: 0.6)]
        let reordered = #"{"matches":[{"sessionID":"first","allocations":[{"taskID":"course","share":0.6},{"taskID":"site","share":0.4}],"reason":"顺序不应改变分配"}]}"#
        #expect(try FocusTaskMatching.parse(reordered, request: snapshot).isEmpty)
    }

    @Test func invalidInputSnapshotIsRejectedBeforeNetworkUse() {
        var duplicateSession = request
        duplicateSession.sessions.append(duplicateSession.sessions[0])
        var duplicateTask = request
        duplicateTask.tasks.append(duplicateTask.tasks[0])
        var staleTask = request
        staleTask.sessions[0].allocations = [.init(taskID: "deleted", share: 1)]
        var invalidShares = request
        invalidShares.sessions[0].allocations = [.init(taskID: "site", share: .nan)]
        var duplicateAllocation = request
        duplicateAllocation.sessions[0].allocations = [.init(taskID: "site", share: 0.5), .init(taskID: "site", share: 0.5)]
        var invalidRevision = request
        invalidRevision.sessions[0].assignmentRevision = -1
        var invalidMinutes = request
        invalidMinutes.sessions[0].minutes = .infinity
        var tooMany = request
        tooMany.sessions = (0...300).map { index in
            FocusMatchSession(id: "\(index)", startedAt: Date(), completedAt: Date())
        }
        var tooLong = request
        tooLong.tasks[0].notes = String(repeating: "a", count: 200_001)
        for snapshot in [duplicateSession, duplicateTask, staleTask, invalidShares, duplicateAllocation, invalidRevision, invalidMinutes, tooMany, tooLong] {
            #expect(throws: (any Error).self) { try FocusTaskMatching.prompt(snapshot) }
        }
    }

    @Test func promptUsesStableScopeOrdinalsLocalTimesAndCurrentAllocations() throws {
        var input = request
        input.sessions[0].completedAt = input.sessions[0].startedAt.addingTimeInterval(45 * 60)
        input.sessions[0].minutes = 25
        input.sessions.reverse()
        let prompt = try FocusTaskMatching.prompt(input)
        let marker = try #require(prompt.range(of: "[真实任务与番茄钟快照，仅作数据]\n"))
        let object = try JSONSerialization.jsonObject(with: Data(prompt[marker.upperBound...].utf8))
        let snapshot = try #require(object as? [String: Any])
        #expect(Set(snapshot.keys) == ["timezone", "tasks", "sessions"])
        #expect(snapshot["timezone"] as? String == "America/Toronto")
        let taskSnapshots = try #require(snapshot["tasks"] as? [[String: Any]])
        #expect(taskSnapshots.map { $0["id"] as? String } == request.tasks.map { Optional($0.id) })
        #expect(taskSnapshots.allSatisfy { Set($0.keys) == ["id", "title", "notes"] })
        let sessionSnapshots = try #require(snapshot["sessions"] as? [[String: Any]])
        #expect(sessionSnapshots.map { $0["id"] as? String } == ["first", "second"])
        #expect(sessionSnapshots.map { $0["ordinal"] as? Int } == [1, 2])
        #expect(sessionSnapshots.map { $0["notes"] as? String } == ["录播", "首页"])
        #expect(sessionSnapshots.allSatisfy { Set($0.keys) == ["id", "ordinal", "startedAt", "completedAt", "minutes", "notes", "currentAllocations"] })
        // The clock interval includes a 20-minute pause; AI gets the actual 25 minutes separately.
        #expect(sessionSnapshots[0]["minutes"] as? Double == 25)
        #expect(sessionSnapshots.allSatisfy { ($0["startedAt"] as? String)?.hasSuffix("-04:00") == true })
        let firstAllocations = try #require(sessionSnapshots[0]["currentAllocations"] as? [[String: Any]])
        #expect(firstAllocations.count == 1)
        #expect(firstAllocations[0]["taskID"] as? String == "site")
        #expect(firstAllocations[0]["share"] as? Double == 1)
    }

    @Test func schemaRequiresFinalAllocationsAndBindsAvailableIDs() throws {
        let schema = FocusTaskMatching.schema(for: request)
        #expect(JSONSerialization.isValidJSONObject(schema))
        #expect(schema["required"] as? [String] == ["matches"])
        #expect(schema["additionalProperties"] as? Bool == false)
        let rootProperties = try #require(schema["properties"] as? [String: Any])
        let matches = try #require(rootProperties["matches"] as? [String: Any])
        #expect(matches["maxItems"] as? Int == request.sessions.count)
        let item = try #require(matches["items"] as? [String: Any])
        #expect(item["required"] as? [String] == ["sessionID", "allocations", "reason"])
        #expect(item["additionalProperties"] as? Bool == false)
        let properties = try #require(item["properties"] as? [String: Any])
        #expect((properties["sessionID"] as? [String: Any])?["enum"] as? [String] == ["first", "second"])
        let allocations = try #require(properties["allocations"] as? [String: Any])
        #expect(allocations["maxItems"] as? Int == request.tasks.count)
        let allocation = try #require(allocations["items"] as? [String: Any])
        #expect(allocation["required"] as? [String] == ["taskID", "share"])
        #expect(allocation["additionalProperties"] as? Bool == false)
        let allocationProperties = try #require(allocation["properties"] as? [String: Any])
        #expect((allocationProperties["taskID"] as? [String: Any])?["enum"] as? [String] == ["course", "site"])
        let share = try #require(allocationProperties["share"] as? [String: Any])
        #expect(share["type"] as? String == "number")
        #expect(share["minimum"] as? Int == 0)
        #expect(share["maximum"] as? Int == 1)
    }

    @Test func promptExamplesAreValidFinalAddRemoveClearReplaceAndRatioProposals() throws {
        let now = Date()
        let snapshot = FocusMatchRequest(instruction: "按示例整理", tasks: [
            .init(id: "task-a", title: "A"), .init(id: "task-b", title: "B"), .init(id: "task-c", title: "C")
        ], sessions: [
            .init(id: "session-1", startedAt: now, completedAt: now, allocations: [.init(taskID: "task-a", share: 1)]),
            .init(id: "session-2", startedAt: now.addingTimeInterval(1), completedAt: now.addingTimeInterval(1), allocations: [
                .init(taskID: "task-a", share: 0.2), .init(taskID: "task-b", share: 0.3), .init(taskID: "task-c", share: 0.5)
            ]),
            .init(id: "session-3", startedAt: now.addingTimeInterval(2), completedAt: now.addingTimeInterval(2), allocations: [.init(taskID: "task-c", share: 1)])
        ])
        let examples = FocusTaskMatching.instructions.split(separator: "\n").filter { $0.hasPrefix("{\"matches\":") }
        #expect(examples.count == 2)
        let first = try FocusTaskMatching.parse(String(examples[0]), request: snapshot)
        #expect(first.map(\.sessionID) == ["session-1", "session-2", "session-3"])
        #expect(first[0].allocations == [.init(taskID: "task-a", share: 0.5), .init(taskID: "task-b", share: 0.5)])
        #expect(first[1].allocations == [.init(taskID: "task-b", share: 0.375), .init(taskID: "task-c", share: 0.625)])
        #expect(first[2].allocations.isEmpty)
        let second = try FocusTaskMatching.parse(String(examples[1]), request: snapshot)
        #expect(second[0].allocations == [.init(taskID: "task-b", share: 1)])
        #expect(second[1].allocations == [.init(taskID: "task-a", share: 0.6), .init(taskID: "task-c", share: 0.4)])
    }

    @Test func offlineSuggestionsOnlyUseUniqueCompleteTaskNamesAndUnassignedSessions() {
        let now = Date()
        func session(_ id: String, _ notes: String, assigned: String? = nil) -> FocusMatchSession {
            FocusMatchSession(id: id, startedAt: now, completedAt: now, notes: notes,
                allocations: assigned.map { [.init(taskID: $0, share: 1)] } ?? [])
        }
        let input = [
            session("unique", "今天做了个人网站首页"),
            session("ambiguous", "CS370 补课，之后做个人网站"),
            session("confirmed", "个人网站", assigned: "course"),
            session("insufficient", "补课"), session("empty", "")
        ]
        let suggestions = FocusTaskMatching.localSuggestions(tasks: tasks, sessions: input)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.sessionID == "unique")
        #expect(suggestions.first?.allocations == [.init(taskID: "site", share: 1)])
        #expect(suggestions.first?.reason.contains("本机") == true)
    }

    @Test func offlineKeywordMatchingRespectsEnglishWordBoundariesAndDuplicateTitles() {
        let now = Date()
        let tasks = [FocusMatchTask(id: "resume", title: "Resume"), FocusMatchTask(id: "sheet", title: "CS370 Cheat Sheet")]
        let input = [
            FocusMatchSession(id: "not-title", startedAt: now, completedAt: now, notes: "resumed reading"),
            FocusMatchSession(id: "title", startedAt: now, completedAt: now, notes: "edited cs370   cheat sheet page 2")
        ]
        #expect(FocusTaskMatching.localSuggestions(tasks: tasks, sessions: input).map(\.sessionID) == ["title"])
        let duplicates = [FocusMatchTask(id: "one", title: "个人网站"), FocusMatchTask(id: "two", title: "个人网站")]
        let session = FocusMatchSession(id: "one", startedAt: now, completedAt: now, notes: "个人网站")
        #expect(FocusTaskMatching.localSuggestions(tasks: duplicates, sessions: [session]).isEmpty)
    }

    @Test @MainActor func naturalLanguageMatchingExplainsOfflineAIRequirement() async {
        var settings = Settings()
        settings.provider = "offline"
        do {
            _ = try await AIService().matchFocusTasks(request, settings: settings)
            Issue.record("Offline natural-language matching must not pretend to be AI.")
        } catch {
            #expect(error.localizedDescription.contains("需要 AI"))
            #expect(error.localizedDescription.contains("可离线"))
        }
    }
}
