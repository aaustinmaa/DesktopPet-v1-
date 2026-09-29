import Foundation
import Testing
@testable import SuWuDu

struct TargetScheduleTests {
    @Test func rangesOverridesAndSingleDayEdits() {
        var data = AppData()
        data.journal = [JournalDay(date: "2026-10-05", target: 1, notes: "keep", sessions: [FocusSession()])]
        data.setTargets(from: "2026-10-01", through: nil, target: 4)
        data.setTargets(from: "2026-11-01", through: "2026-11-30", target: 8)
        #expect(data.journalDay("2026-09-30").target == 0)
        #expect(data.journalDay("2026-10-05").target == 4)
        #expect(data.journalDay("2026-10-05").notes == "keep")
        #expect(data.journalDay("2026-10-05").sessions.count == 1)
        #expect(data.journalDay("2026-11-01").target == 8)
        #expect(data.journalDay("2026-11-30").target == 8)
        #expect(data.journalDay("2026-12-01").target == 4)
        #expect(data.journalDay("2040-01-01").target == 4)
        data.journal.append(JournalDay(date: "2026-11-12", target: 0))
        #expect(data.journalDay("2026-11-12").target == 0)
    }

    @Test func persistedRulesAndOldDataCompatibility() throws {
        var data = AppData()
        data.setTargets(from: "2026-10-01", through: nil, target: 6)
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        #expect(decoded.journalDay("2030-01-01").target == 6)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        object.removeValue(forKey: "targetRules")
        let legacy = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.journalDay("2030-01-01").target == 0)
    }

    @Test func automaticSessionInheritsScheduledTarget() throws {
        let date = try #require(FocusAccounting.date(from: "2026-10-05"))
        var journal: [JournalDay] = []
        FocusAccounting.record(segments: [FocusSegment(start: date.addingTimeInterval(-1500), end: date)],
                               planned: 25, completed: true, startedAt: date.addingTimeInterval(-1500), endedAt: date,
                               targets: [JournalTargetRule(from: "2026-10-01", target: 7)], journal: &journal)
        #expect(journal.first?.target == 7)
        #expect(journal.first?.count == 1)
    }
}
