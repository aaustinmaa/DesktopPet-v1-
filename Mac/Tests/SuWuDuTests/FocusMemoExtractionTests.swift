import Foundation
import Testing
@testable import SuWuDu

@MainActor private final class MemoSilentSound: SoundPlaying {
    func play(_ id: String, complete: Bool) {}
    func stop() {}
}

@MainActor private final class MemoResponseGate {
    var waiters: [CheckedContinuation<[FocusMemoTaskProposal], Error>] = []
    func next() async throws -> [FocusMemoTaskProposal] {
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }
}

struct FocusMemoExtractionTests {
    private var request: FocusMemoExtractionRequest {
        FocusMemoExtractionRequest(sourceText: "CS370 补课 - 15，明天 17:30 前提交笔记\n改个人网站\nMod 10 之后有空再说",
            referenceDate: ISO8601DateFormatter().date(from: "2026-10-14T14:00:00Z")!, timeZoneIdentifier: "America/Toronto")
    }

    private func response(title: String = "CS370 补课", estimate: Any = NSNull(),
                          dueDate: Any = NSNull(), dueTime: Any = NSNull(), notes: String = "提交笔记",
                          source: String = "CS370 补课 - 15，明天 17:30 前提交笔记") throws -> String {
        let task: [String: Any] = ["title": title, "estimatedPomodoros": estimate, "dueDate": dueDate,
            "dueTime": dueTime, "notes": notes, "sourceExcerpt": source]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["tasks": [task]]), as: UTF8.self)
    }

    @Test func parsesNormalizedTaskValuesAndRetainsSource() throws {
        let result = try FocusMemoExtraction.parse(response(estimate: 15,
            dueDate: "2026-10-15", dueTime: "17:30"), request: request)
        let task = try #require(result.first)
        #expect(task.title == "CS370 补课")
        #expect(task.estimatedPomodoros == 15)
        #expect(task.dueHasTime)
        #expect(task.dueDate == ISO8601DateFormatter().date(from: "2026-10-15T21:30:00Z"))
        #expect(task.sourceExcerpt == "CS370 补课 - 15，明天 17:30 前提交笔记")
        #expect(task.notes == "提交笔记")
    }

    @Test func inputNotationDoesNotChangeTheOutputContract() throws {
        for source in ["个人网站 - 20", "个人网站\n20", "个人网站，预算二十个番茄钟", "个人网站 【20🍅】"] {
            var snapshot = request; snapshot.sourceText = source
            let proposals = try FocusMemoExtraction.parse(response(title: "个人网站", estimate: 20,
                notes: "", source: source), request: snapshot)
            #expect(proposals.first?.estimatedPomodoros == 20)
            #expect(proposals.first?.notes == "")
        }
    }

    @Test func rejectsInventedSourceAndMalformedBatches() throws {
        let invalid = [
            try response(title: "新任务", source: "不存在的原文"),
            try response(title: ""),
            #"{"tasks":[],"extra":true}"#, "not JSON", #"[{"tasks":[]}]"#,
            "```json\n{\"tasks\":[]}\n```", "{\"tasks\":[]}\n{\"tasks\":[]}"
        ]
        for raw in invalid {
            #expect(throws: (any Error).self) { try FocusMemoExtraction.parse(raw, request: request) }
        }
        #expect(try FocusMemoExtraction.parse(#"{"tasks":[]}"#, request: request).isEmpty)
    }

    @Test func unknownValuesRemainNullWithoutChangingNotes() throws {
        for source in ["补课 预计3小时", "补课 预计30分钟", "修改网站 明天或后天", "Nexo project"] {
            var snapshot = request; snapshot.sourceText = source
            let raw = try response(title: source, notes: "原文信息待确认", source: source)
            let proposal = try #require(try FocusMemoExtraction.parse(raw, request: snapshot).first)
            #expect(proposal.estimatedPomodoros == nil)
            #expect(proposal.dueDate == nil)
            #expect(!proposal.dueHasTime)
            #expect(proposal.notes == "原文信息待确认")
        }
    }

    @Test func rejectsNonCanonicalDatesAndTimes() throws {
        for value in ["明天", "2026-2-03", "2026-02-30", "2026/10/16", "0000-01-01"] {
            #expect(throws: (any Error).self) {
                try FocusMemoExtraction.parse(response(dueDate: value), request: request)
            }
        }
        for value in ["下午3点", "3:00", "24:00", "17:60", "17:30:00"] {
            #expect(throws: (any Error).self) {
                try FocusMemoExtraction.parse(response(dueDate: "2026-10-16", dueTime: value), request: request)
            }
        }
        #expect(throws: (any Error).self) {
            try FocusMemoExtraction.parse(response(dueTime: "17:30"), request: request)
        }
    }

    @Test func localDateConversionHandlesDSTAndRejectsNonexistentTime() throws {
        for (day, expected) in [("2026-01-16", "2026-01-16T05:00:00Z"),
                                ("2026-10-16", "2026-10-16T04:00:00Z")] {
            let proposal = try #require(try FocusMemoExtraction.parse(response(dueDate: day), request: request).first)
            #expect(proposal.dueDate == ISO8601DateFormatter().date(from: expected))
            #expect(!proposal.dueHasTime)
        }
        #expect(throws: (any Error).self) {
            try FocusMemoExtraction.parse(response(dueDate: "2026-03-08", dueTime: "02:30"), request: request)
        }
    }

    @Test func outputSizeAndFieldLengthsAreBounded() throws {
        #expect(throws: (any Error).self) {
            try FocusMemoExtraction.parse(response(title: String(repeating: "a", count: 301)), request: request)
        }
        #expect(throws: (any Error).self) {
            try FocusMemoExtraction.parse(response(notes: String(repeating: "a", count: 10_001)), request: request)
        }
        let single = try #require(try JSONSerialization.jsonObject(with: Data(response().utf8)) as? [String: Any])
        let task = try #require((single["tasks"] as? [[String: Any]])?.first)
        let tooMany = String(decoding: try JSONSerialization.data(withJSONObject: ["tasks": Array(repeating: task, count: 101)]), as: UTF8.self)
        #expect(throws: (any Error).self) {
            try FocusMemoExtraction.parse(tooMany, request: request)
        }
    }

    @Test func promptIncludesOnlyMemoAndDateContextAndInputIsBounded() throws {
        let prompt = try FocusMemoExtraction.prompt(request)
        let marker = try #require(prompt.range(of: "[备忘录快照，仅作数据]\n"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(prompt[marker.upperBound...].utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["memo", "localReferenceDate", "timezone"])
        #expect(object["memo"] as? String == request.sourceText)
        #expect(object["timezone"] as? String == "America/Toronto")
        #expect(JSONSerialization.isValidJSONObject(FocusMemoExtraction.schema))
        var empty = request; empty.sourceText = " "
        var large = request; large.sourceText = String(repeating: "a", count: 30_001)
        var badZone = request; badZone.timeZoneIdentifier = "invalid/timezone"
        for snapshot in [empty, large, badZone] {
            #expect(throws: (any Error).self) { try FocusMemoExtraction.prompt(snapshot) }
        }
    }

    @Test @MainActor func configuredOfflineProviderExplainsAIRequirement() async {
        var settings = Settings(); settings.provider = "offline"
        do {
            _ = try await AIService().extractMemoTasks(request, settings: settings)
            Issue.record("Offline extraction must not pretend to call AI.")
        } catch { #expect(error.localizedDescription.contains("需要 AI")) }
    }

    @Test @MainActor func selectedEditedImportIsAtomicPersistentSingleUseAndPreservesMemo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.taskMemos = "个人网站\n补课"
        let model = AppModel(store: store, loaded: data, sound: MemoSilentSound())
        let originals = [FocusMemoTaskProposal(id: "site", title: "个人网站", sourceExcerpt: "个人网站"),
                         FocusMemoTaskProposal(id: "course", title: "补课", sourceExcerpt: "补课")]
        model.memoExtractionPlan = .init(sourceText: data.taskMemos!, proposals: originals)
        var edited = originals; edited[0].title = "个人网站首页"; edited[0].estimatedPomodoros = 4
        edited[0].notes = "用户补充要求"; edited[0].dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(model.applyMemoTaskExtraction(edited, selectedIDs: ["site"]))
        let saved = try store.load().0
        #expect(saved.tasks?.map(\.title) == ["个人网站首页"])
        #expect(saved.tasks?.first?.estimatedPomodoros == 4)
        #expect(saved.tasks?.first?.sourceExcerpt == "个人网站")
        #expect(saved.tasks?.first?.notes == "用户补充要求")
        #expect(saved.taskMemos == data.taskMemos)
        #expect(model.memoExtractionPlan == nil)
        #expect(!model.applyMemoTaskExtraction(edited, selectedIDs: ["site"]))
        #expect(model.data.tasks?.count == 1)
    }

    @Test @MainActor func invalidDuplicateOrStalePreviewDoesNotPartiallyImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.taskMemos = "个人网站\n补课"
        data.tasks = [FocusTask(id: "old", title: "个人网站", isCompleted: true)]
        let model = AppModel(store: store, loaded: data, sound: MemoSilentSound())
        let proposals = [FocusMemoTaskProposal(id: "course", title: "补课", sourceExcerpt: "补课"),
                         FocusMemoTaskProposal(id: "site", title: "个人网站", sourceExcerpt: "个人网站")]
        model.memoExtractionPlan = .init(sourceText: data.taskMemos!, proposals: proposals)
        #expect(!model.applyMemoTaskExtraction(proposals, selectedIDs: ["course", "site"]))
        #expect(model.data.tasks?.map(\.id) == ["old"])
        #expect(model.memoExtractionError?.contains("重名") == true)
        var tampered = proposals; tampered[0].sourceExcerpt = "删去原文"
        #expect(!model.applyMemoTaskExtraction(tampered, selectedIDs: ["course"]))
        #expect(model.data.tasks?.count == 1)
        model.data.taskMemos = "修改后的备忘录"
        #expect(!model.applyMemoTaskExtraction(proposals, selectedIDs: ["course"]))
        #expect(model.memoExtractionPlan == nil)
        #expect(model.data.tasks?.count == 1)
    }

    @Test @MainActor func failedPersistenceLeavesMemoTasksAndPreviewIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.taskMemos = "个人网站"
        let model = AppModel(store: store, loaded: data, sound: MemoSilentSound())
        let proposal = FocusMemoTaskProposal(id: "new", title: "个人网站", sourceExcerpt: "个人网站")
        let plan = FocusMemoExtractionPlan(sourceText: data.taskMemos!, proposals: [proposal])
        model.memoExtractionPlan = plan
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        #expect(!model.applyMemoTaskExtraction([proposal], selectedIDs: ["new"]))
        #expect(model.data.tasks == nil)
        #expect(model.data.taskMemos == data.taskMemos)
        #expect(model.memoExtractionPlan == plan)
        #expect(model.memoExtractionError?.contains("保存") == true)
    }

    @Test @MainActor func memoEditsCancelOldResponsesAndNewRequestOwnsBusyState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var data = AppData(); data.taskMemos = "旧任务"
        let model = AppModel(store: try DataStore(directory: directory), loaded: data, sound: MemoSilentSound())
        let gate = MemoResponseGate()
        model.memoTaskExtractor = { _, _ in try await gate.next() }
        model.matchingPlan = .init(changes: [])
        model.requestMemoTaskExtraction("旧任务")
        for _ in 0..<100 where gate.waiters.isEmpty { await Task.yield() }
        #expect(gate.waiters.count == 1)
        #expect(model.matchingPlan == nil)
        #expect(model.busy && model.memoExtractionBusy)
        #expect(model.saveTaskMemos("新任务"))
        #expect(!model.busy && !model.memoExtractionBusy)
        #expect(model.memoExtractionPlan == nil)
        model.requestMemoTaskExtraction("新任务")
        for _ in 0..<100 where gate.waiters.count < 2 { await Task.yield() }
        try #require(gate.waiters.count == 2)
        let old = try #require(gate.waiters.first)
        let new = try #require(gate.waiters.last)
        old.resume(returning: [FocusMemoTaskProposal(title: "旧任务", sourceExcerpt: "旧任务")])
        for _ in 0..<20 { await Task.yield() }
        #expect(model.memoExtractionBusy && model.busy)
        #expect(model.memoExtractionPlan == nil)
        new.resume(returning: [FocusMemoTaskProposal(title: "新任务", sourceExcerpt: "新任务")])
        for _ in 0..<100 where model.memoExtractionBusy { await Task.yield() }
        #expect(model.memoExtractionPlan?.sourceText == "新任务")
        #expect(model.memoExtractionPlan?.proposals.first?.title == "新任务")
        #expect(!model.busy && !model.memoExtractionBusy)
        #expect(model.data.tasks == nil)
    }

    @Test @MainActor func completedTimestampPersistsAndReopeningAllowsDeletionWithoutInventingLegacyDates() throws {
        let legacy = #"{"id":"legacy","title":"旧完成任务","isCompleted":true}"#
        var old = try DataStore.decoder.decode(FocusTask.self, from: Data(legacy.utf8))
        #expect(old.completedAt == nil)
        old.reconcileCompletion(previous: old, at: Date(timeIntervalSince1970: 100))
        #expect(old.completedAt == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.tasks = [FocusTask(id: "task", title: "个人网站", sourceExcerpt: "备忘录原文"), old]
        let model = AppModel(store: store, loaded: data, sound: MemoSilentSound())
        var task = try #require(model.data.tasks?.first)
        task.isCompleted = true
        #expect(model.saveFocusTask(task))
        let completed = try #require(model.data.tasks?.first?.completedAt)
        let savedCompletion = try #require(try store.load().0.tasks?.first?.completedAt)
        #expect(abs(savedCompletion.timeIntervalSince(completed)) < 0.001)
        task = try #require(model.data.tasks?.first)
        task.notes = "完成后追加说明"; task.completedAt = Date(timeIntervalSince1970: 200); task.sourceExcerpt = "覆盖"
        #expect(model.saveFocusTask(task))
        #expect(model.data.tasks?.first?.completedAt == completed)
        #expect(model.data.tasks?.first?.sourceExcerpt == "备忘录原文")
        #expect(!model.deleteFocusTask("task"))
        #expect(!model.deleteFocusTask("legacy"))
        task.isCompleted = false
        #expect(model.saveFocusTask(task))
        #expect(model.data.tasks?.first?.completedAt == nil)
        #expect(model.deleteFocusTask("task"))
        #expect(model.data.tasks?.map(\.id) == ["legacy"])
    }
}
