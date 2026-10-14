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

    private func response(title: String = "CS370 补课", estimate: Any = NSNull(), estimateText: Any = NSNull(),
                          deadline: Any = NSNull(), source: String = "CS370 补课 - 15，明天 17:30 前提交笔记") throws -> String {
        let task: [String: Any] = ["title": title, "estimatedPomodoros": estimate, "estimateText": estimateText,
            "deadlineText": deadline, "notes": "提交笔记", "sourceExcerpt": source]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["tasks": [task]]), as: UTF8.self)
    }

    @Test func parsesOnlySupportedExplicitEvidenceAndRetainsSource() throws {
        var snapshot = request
        snapshot.sourceText = "CS370 补课，预计 15 个番茄钟，明天 17:30 前提交笔记"
        let result = try FocusMemoExtraction.parse(response(estimate: 15, estimateText: "15 个番茄钟",
            deadline: "明天 17:30", source: snapshot.sourceText), request: snapshot)
        let task = try #require(result.first)
        #expect(task.title == "CS370 补课")
        #expect(task.estimatedPomodoros == 15)
        #expect(task.dueHasTime)
        #expect(task.dueDate == ISO8601DateFormatter().date(from: "2026-10-15T21:30:00Z"))
        #expect(task.sourceExcerpt == snapshot.sourceText)
        #expect(snapshot.sourceText == "CS370 补课，预计 15 个番茄钟，明天 17:30 前提交笔记")
    }

    @Test func trailingBudgetAndSeparateNumericBudgetRequireOneOriginalTask() throws {
        for source in ["个人网站 - 20", "个人网站\n20"] {
            var snapshot = request; snapshot.sourceText = source
            let proposals = try FocusMemoExtraction.parse(response(title: "个人网站", estimate: 20,
                estimateText: "20", source: source), request: snapshot)
            #expect(proposals.first?.estimatedPomodoros == 20)
        }
    }

    @Test func rejectsCourseNumbersInventedEvidenceAndMalformedBatchAsWhole() throws {
        var snapshot = request; snapshot.sourceText = "Mod 10\nCS 370\n2026-10-16\n读两小时"
        let invalid = [
            try response(title: "Mod 10", estimate: 10, estimateText: "10", source: "Mod 10"),
            try response(title: "CS 370", estimate: 370, estimateText: "370", source: "CS 370"),
            try response(title: "读两小时", estimate: 5, estimateText: "两小时", source: "读两小时"),
            try response(title: "Mod 10", deadline: "明天", source: "Mod 10"),
            try response(title: "新任务", source: "不存在的原文"),
            try response(title: "", source: "Mod 10"),
            #"{"tasks":[],"extra":true}"#, "not JSON"
        ]
        for raw in invalid {
            #expect(throws: (any Error).self) { try FocusMemoExtraction.parse(raw, request: snapshot) }
        }
        #expect(try FocusMemoExtraction.parse(#"{"tasks":[]}"#, request: snapshot).isEmpty)
    }

    @Test func truncatedEstimateEvidenceCannotConvertHoursOrMinutesIntoPomodoros() throws {
        for source in ["补课 预计3小时", "补课 预计30分钟"] {
            var snapshot = request; snapshot.sourceText = source
            let value = source.contains("30") ? 30 : 3
            let raw = try response(title: "补课", estimate: value, estimateText: "预计\(value)", source: source)
            #expect(throws: (any Error).self) { try FocusMemoExtraction.parse(raw, request: snapshot) }
        }
    }

    @Test func ambiguousAndInvalidDeadlineWordsStayEmptyWithOriginalVisible() throws {
        for deadline in ["周五", "2026-02-30", "明天或后天", "明天下午三点", "有空", "大后天", "下下周五",
                         "明天下午3点半", "明天晚上12点", "明天凌晨12点"] {
            var snapshot = request; snapshot.sourceText = "修改网站：" + deadline
            let proposals = try FocusMemoExtraction.parse(response(title: "修改网站", deadline: deadline,
                source: snapshot.sourceText), request: snapshot)
            #expect(proposals.first?.dueDate == nil)
            #expect(proposals.first?.dueHasTime == false)
            #expect(proposals.first?.notes.contains(deadline) == true)
            #expect(proposals.first?.sourceExcerpt == snapshot.sourceText)
        }
    }

    @Test func truncatedDeadlineEvidenceCannotDiscardSuppliedTimeQualifier() throws {
        for (source, evidence) in [("修改网站 明天下午3点半", "明天下午3点"),
                                   ("修改网站 明天 17:30", "明天")] {
            var snapshot = request; snapshot.sourceText = source
            let proposals = try FocusMemoExtraction.parse(response(title: "修改网站", deadline: evidence,
                source: source), request: snapshot)
            #expect(proposals.first?.dueDate == nil)
            #expect(proposals.first?.notes.contains("待确认") == true)
        }
    }

    @Test func explicitCalendarDatesAndWeekdayDeadlinesUseLocalMidnight() throws {
        for (text, expected, timed) in [
            ("2026-10-16", "2026-10-16T04:00:00Z", false),
            ("2026年10月16日 下午3点", "2026-10-16T19:00:00Z", true),
            ("本周五", "2026-10-16T04:00:00Z", false),
            ("下周五", "2026-10-23T04:00:00Z", false)
        ] {
            let resolved = try #require(FocusMemoExtraction.explicitDeadline(text, request: request))
            #expect(resolved.date == ISO8601DateFormatter().date(from: expected))
            #expect(resolved.hasTime == timed)
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
