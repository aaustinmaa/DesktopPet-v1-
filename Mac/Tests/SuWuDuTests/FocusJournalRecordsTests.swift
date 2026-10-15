import Foundation
import Testing
@testable import SuWuDu

struct FocusJournalRecordsTests {
    @Test func earlyEndsStayInMinuteDetailsWhenTheyAccumulateIntoCountedUnits() throws {
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课")]
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        FocusAccounting.record(segments: [.init(start: start, end: start.addingTimeInterval(600))],
            planned: 25, completed: false, startedAt: start, endedAt: start.addingTimeInterval(600),
            taskID: "a", journal: &state.journal)
        var day = try #require(state.journal.first)
        var records = FocusJournalRecords(sessions: day.sessions)
        #expect(records.counted.isEmpty)
        #expect(records.matchable.isEmpty)
        #expect(records.minutes.map(\.minutes) == [10])
        #expect(day.count == 0 && day.total == 10 && day.adjustment == 10)

        let next = start.addingTimeInterval(1200)
        FocusAccounting.record(segments: [.init(start: next, end: next.addingTimeInterval(900))],
            planned: 25, completed: false, startedAt: next, endedAt: next.addingTimeInterval(900),
            taskID: "a", journal: &state.journal)
        day = try #require(state.journal.first)
        records = FocusJournalRecords(sessions: day.sessions)
        #expect(records.minutes.map(\.minutes) == [10, 15])
        #expect(records.counted.count == 1)
        #expect(records.counted.allSatisfy { $0.isMinuteConversion })
        #expect(records.matchable.isEmpty)
        #expect(day.count == 1 && day.total == 25 && day.adjustment == 0)
        #expect(state.taskSummaries().first?.minutes == 25)
        #expect(state.taskSummaries().first?.completedPomodoros == 0)
    }

    @Test @MainActor func hiddenDetailsRemainEditableAndRestorableAfterSaveAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        let partial = FocusSession(id: "partial", source: "partial", minutes: 10, countsTowardGoal: false,
            taskID: "a", actualMinutes: 10, completedPomodoro: false)
        let automatic = FocusSession(id: "automatic", actualMinutes: 25, completedPomodoro: true)
        let manual = FocusSession(id: "manual", source: "manual", actualMinutes: 25, completedPomodoro: true)
        let excluded = FocusSession(id: "excluded", source: "manual", countsTowardGoal: false,
            actualMinutes: 25, completedPomodoro: true)
        var data = AppData()
        data.tasks = [FocusTask(id: "a", title: "补课")]
        data.journal = [JournalDay(date: FocusAccounting.key(Date()), adjustment: 10,
            sessions: [partial, automatic, manual, excluded])]
        let model = AppModel(store: store, loaded: data)
        let editor = JournalEditor(model: model)
        let original = FocusJournalRecords(sessions: editor.day.sessions)
        #expect(Set(original.counted.map(\.id)) == ["automatic", "manual"])
        #expect(Set(original.matchable.map(\.id)) == ["automatic", "manual"])
        #expect(original.minutes.map(\.id) == ["partial"])
        #expect(original.excluded.map(\.id) == ["excluded"])

        var edited = editor.day
        edited.sessions[0].minutes = 12
        edited.sessions[0].notes = "提前结束的补课"
        edited.sessions[1].countsTowardGoal = false
        edited.sessions[3].countsTowardGoal = true
        editor.edit(edited)
        #expect(editor.save())
        let saved = try #require(store.load().0.journal.first)
        let records = FocusJournalRecords(sessions: saved.sessions)
        #expect(Set(records.matchable.map(\.id)) == ["manual", "excluded"])
        #expect(records.excluded.map(\.id) == ["automatic"])
        #expect(records.minutes.first?.minutes == 12)
        #expect(records.minutes.first?.notes == "提前结束的补课")
        #expect(saved.count == 2 && saved.total == 62)
        #expect(model.data.taskSummaries().first?.minutes == 12)
        #expect(JournalExport.markdown([saved]).contains("12 分钟 · 提前结束"))

        var deleted = editor.day
        deleted.sessions.removeAll { $0.id == "partial" }
        editor.edit(deleted)
        #expect(editor.save())
        #expect(editor.day.total == 50)
        #expect(FocusJournalRecords(sessions: editor.day.sessions).minutes.isEmpty)
        #expect(model.data.taskSummaries().first?.minutes == 0)
    }
}
