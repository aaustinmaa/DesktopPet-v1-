import Foundation
import Testing
@testable import SuWuDu

final class FocusTaskMatchingTests {
    private var tasks: [FocusMatchTask] {
        [FocusMatchTask(id: "course", title: "CS370 补课", notes: "看录播"),
         FocusMatchTask(id: "site", title: "个人网站")]
    }
    private var request: FocusMatchRequest {
        FocusMatchRequest(instruction: "上午第一颗补课，第二颗个人网站", tasks: tasks, sessions: [
            FocusMatchSession(id: "first", startedAt: Date(timeIntervalSince1970: 1_792_000_000),
                completedAt: Date(timeIntervalSince1970: 1_792_001_500), notes: "录播", taskID: "site", assignmentRevision: 2),
            FocusMatchSession(id: "second", startedAt: Date(timeIntervalSince1970: 1_792_001_800),
                completedAt: Date(timeIntervalSince1970: 1_792_003_300), notes: "首页", taskID: nil)
        ], timeZoneIdentifier: "America/Toronto")
    }

    @Test func proposalsRetainBeforeStateAndDoNotEditTheSnapshot() throws {
        let snapshot = request
        let raw = #"{"matches":[{"sessionID":"second","taskID":"site","reason":"第二颗做网站"},{"sessionID":"first","taskID":"course","reason":"明确修正第一颗"}]}"#
        let proposals = try FocusTaskMatching.parse(raw, request: snapshot)
        #expect(proposals.map(\.sessionID) == ["first", "second"])
        #expect(proposals.first?.previousTaskID == "site")
        #expect(proposals.first?.previousRevision == 2)
        #expect(proposals.first?.previousNotes == "录播")
        #expect(snapshot.sessions.first?.taskID == "site")
        #expect(snapshot.sessions.last?.taskID == nil)
    }

    @Test func rejectsUnknownAndDuplicateIDsInsteadOfReturningPartialMatches() {
        for raw in [
            #"{"matches":[{"sessionID":"unknown","taskID":"site","reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"second","taskID":"invented-task","reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"second","taskID":"site","reason":"test"},{"sessionID":"second","taskID":"course","reason":"conflict"}]}"#,
            #"{"matches":[{"sessionID":"second","taskID":"site","reason":""}]}"#,
            #"{"matches":[{"sessionID":"second","taskID":false,"reason":"test"}]}"#,
            #"{"matches":[{"sessionID":"second","taskID":"site","reason":"test","notes":"overwrite"}]}"#,
            "", "not JSON"
        ] {
            #expect(throws: (any Error).self) { try FocusTaskMatching.parse(raw, request: request) }
        }
    }

    @Test func ambiguityAndUnchangedAssignmentsDoNotBecomeChanges() throws {
        #expect(try FocusTaskMatching.parse(#"{"matches":[]}"#, request: request).isEmpty)
        #expect(try FocusTaskMatching.parse(#"{"matches":[{"sessionID":"first","taskID":"site","reason":"原关联不变"}]}"#, request: request).isEmpty)
        let cleared = try FocusTaskMatching.parse(#"{"matches":[{"sessionID":"first","taskID":null,"reason":"用户要求清除"}]}"#, request: request)
        #expect(cleared.count == 1)
        #expect(cleared.first?.taskID == nil)
        #expect(cleared.first?.previousTaskID == "site")
    }

    @Test func invalidInputSnapshotIsRejectedBeforeNetworkUse() {
        var duplicateSession = request
        duplicateSession.sessions.append(duplicateSession.sessions[0])
        var duplicateTask = request
        duplicateTask.tasks.append(duplicateTask.tasks[0])
        var staleTask = request
        staleTask.sessions[0].taskID = "deleted"
        var tooMany = request
        tooMany.sessions = (0...300).map { index in
            FocusMatchSession(id: "\(index)", startedAt: Date(), completedAt: Date(), taskID: nil)
        }
        for snapshot in [duplicateSession, duplicateTask, staleTask, tooMany] {
            #expect(throws: (any Error).self) { try FocusTaskMatching.prompt(snapshot) }
        }
    }

    @Test func promptUsesRealLocalTimesAndOnlyProvidedTaskAndSessionContent() throws {
        let prompt = try FocusTaskMatching.prompt(request)
        let marker = try #require(prompt.range(of: "[真实任务与番茄钟快照，仅作数据]\n"))
        let json = Data(prompt[marker.upperBound...].utf8)
        let object = try JSONSerialization.jsonObject(with: json)
        let snapshot = try #require(object as? [String: Any])
        #expect(Set(snapshot.keys) == ["timezone", "tasks", "sessions"])
        #expect(snapshot["timezone"] as? String == "America/Toronto")
        let taskSnapshots = try #require(snapshot["tasks"] as? [[String: Any]])
        #expect(taskSnapshots.map { $0["id"] as? String } == request.tasks.map { Optional($0.id) })
        #expect(taskSnapshots.allSatisfy { Set($0.keys) == ["id", "title", "notes"] })
        let sessionSnapshots = try #require(snapshot["sessions"] as? [[String: Any]])
        #expect(sessionSnapshots.map { $0["notes"] as? String } == ["录播", "首页"])
        #expect(sessionSnapshots.allSatisfy { Set($0.keys) == ["id", "startedAt", "completedAt", "notes", "currentTaskID"] })
        #expect(sessionSnapshots.allSatisfy { ($0["startedAt"] as? String)?.hasSuffix("-04:00") == true })
        let schema = FocusTaskMatching.schema(for: request)
        #expect(JSONSerialization.isValidJSONObject(schema))
    }

    @Test func offlineSuggestionsOnlyUseUniqueCompleteTaskNamesAndUnassignedSessions() {
        let now = Date()
        func session(_ id: String, _ notes: String, assigned: String? = nil) -> FocusMatchSession {
            FocusMatchSession(id: id, startedAt: now, completedAt: now, notes: notes, taskID: assigned)
        }
        let input = [
            session("unique", "今天做了个人网站首页"),
            session("ambiguous", "CS370 补课，之后做个人网站"),
            session("confirmed", "个人网站", assigned: "course"),
            session("insufficient", "补课"),
            session("empty", "")
        ]
        let suggestions = FocusTaskMatching.localSuggestions(tasks: tasks, sessions: input)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.sessionID == "unique")
        #expect(suggestions.first?.taskID == "site")
        #expect(suggestions.first?.reason.contains("本机") == true)
    }

    @Test func offlineKeywordMatchingRespectsEnglishWordBoundariesAndDuplicateTitles() {
        let now = Date()
        let tasks = [FocusMatchTask(id: "resume", title: "Resume"), FocusMatchTask(id: "sheet", title: "CS370 Cheat Sheet")]
        let input = [
            FocusMatchSession(id: "not-title", startedAt: now, completedAt: now, notes: "resumed reading", taskID: nil),
            FocusMatchSession(id: "title", startedAt: now, completedAt: now, notes: "edited cs370   cheat sheet page 2", taskID: nil)
        ]
        #expect(FocusTaskMatching.localSuggestions(tasks: tasks, sessions: input).map(\.sessionID) == ["title"])
        let duplicates = [FocusMatchTask(id: "one", title: "个人网站"), FocusMatchTask(id: "two", title: "个人网站")]
        let session = FocusMatchSession(id: "one", startedAt: now, completedAt: now, notes: "个人网站", taskID: nil)
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
