import Foundation
import Testing
@testable import SuWuDu

final class CoreTests {
    private var toronto: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }
    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func testJournalBoundaryUsesLocal21RatherThanMidnight() {
        #expect(FocusAccounting.key(instant("2026-09-23T20:59:59-04:00"), calendar: toronto) == "2026-09-23")
        #expect(FocusAccounting.key(instant("2026-09-23T21:00:00-04:00"), calendar: toronto) == "2026-09-24")
        #expect(FocusAccounting.key(instant("2026-09-24T00:30:00-04:00"), calendar: toronto) == "2026-09-24")
    }
    @Test func testCrossBoundaryAllocationConservesMinutes() {
        let segment = FocusSegment(start: instant("2026-09-23T20:50:00-04:00"), end: instant("2026-09-23T21:15:00-04:00"))
        #expect(FocusAccounting.allocate([segment], minutes: 25, calendar: toronto) == ["2026-09-23": 10, "2026-09-24": 15])
    }
    @Test func testPausesDoNotEarnMinutesAndTiesAreDeterministic() {
        let segments = [
            FocusSegment(start: instant("2026-09-23T20:59:30-04:00"), end: instant("2026-09-23T21:00:00-04:00")),
            FocusSegment(start: instant("2026-09-23T22:00:00-04:00"), end: instant("2026-09-23T22:00:30-04:00"))
        ]
        #expect(segments.reduce(0) { $0 + $1.seconds } == 60)
        #expect(FocusAccounting.allocate(segments, minutes: 1, calendar: toronto) == ["2026-09-23": 1])
    }
    @Test func testDaylightSavingDoesNotMoveJournalBoundary() {
        let segment = FocusSegment(start: instant("2026-11-01T00:30:00-04:00"), end: instant("2026-11-01T02:30:00-05:00"))
        #expect(segment.seconds == 10_800)
        #expect(FocusAccounting.allocate([segment], minutes: 180, calendar: toronto) == ["2026-11-01": 180])
    }
    @Test func testMinuteSettlementPreservesTotalAndNotes() {
        var day = JournalDay(date: "2026-09-23", adjustment: -10, sessions: [FocusSession(minutes: 25, notes: "retain me")])
        let total = day.total
        day.settle(minutes: 25)
        #expect(day.total == total)
        #expect(day.adjustment == 15)
        #expect(day.count == 0)
        #expect(day.sessions.first?.notes == "retain me")
        day.adjustment += 15
        day.settle(minutes: 25)
        #expect(day.count == 1)
        #expect(day.adjustment == 5)
        #expect(day.total == 30)
    }
    @Test func testInterruptedRunOnlyRecordsCompletedWholeMinutes() {
        let start = Date()
        var journal: [JournalDay] = []
        FocusAccounting.record(segments: [FocusSegment(start: start, end: start.addingTimeInterval(119))], planned: 25,
                               completed: false, startedAt: start, endedAt: start.addingTimeInterval(119), journal: &journal)
        #expect(journal.reduce(0) { $0 + $1.total } == 1)
        #expect(journal.reduce(0) { $0 + $1.count } == 0)
    }
    @Test func testCompletedRunAndRecoverySnapshotCommitTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.focus = FocusRun(startedAt: Date(), planned: 25, remaining: 30)
        try store.save(data)
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        FocusAccounting.record(segments: [FocusSegment(start: start, end: start.addingTimeInterval(1500))], planned: 25,
                               completed: true, startedAt: start, endedAt: start.addingTimeInterval(1500), journal: &data.journal)
        data.focus = nil
        try store.save(data)
        let restored = try store.load().0
        #expect(restored.focus == nil)
        #expect(restored.journal.reduce(0) { $0 + $1.total } == 25)
        #expect(restored.journal.reduce(0) { $0 + $1.count } == 1)
    }
    @Test func testCorruptPrimaryRecoversBackupWithoutDiscardingOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.facts = ["preserved"]
        try store.save(data)
        data.facts.append("newer")
        try store.save(data)
        try Data("broken".utf8).write(to: store.file)
        let (recovered, warning) = try store.load()
        #expect(recovered.facts == ["preserved"])
        #expect(warning != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("app-state-corrupt-") })
    }
    @Test func testMemoryOptOutKeepsOnlyCurrentConversationContext() {
        let current = ChatThread(messages: [ChatMessage(role: "user", content: "current message")])
        let other = ChatThread(summary: "other private summary")
        let context = LocalMemory.context(thread: current, threads: [current, other], facts: ["private fact"], enabled: false)
        #expect(context.contains("current message"))
        #expect(!(context.contains("private fact")))
        #expect(!(context.contains("other private summary")))
    }
    @Test func testFutureSchemaIsNeverReplacedByOlderBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        try store.save(AppData())
        try store.save(AppData())
        let future = Data("{\"version\":2,\"futureData\":\"keep\"}".utf8)
        try future.write(to: store.file)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.file) == future)
    }
    @Test func testRememberForgetAndFiftyFactLimit() {
        var facts: [String] = []
        for index in 0..<55 { _ = LocalMemory.process("请记住：fact \(index)", facts: &facts) }
        #expect(facts.count == 50)
        _ = LocalMemory.process("请忘记fact 54", facts: &facts)
        #expect(!(facts.contains("fact 54")))
        #expect(facts.count == 49)
    }
    @Test func testWindowsImportKeepsMacPositionAndImportsHistoryAndPausedFocus() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func write(_ name: String, _ value: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: value).write(to: directory.appendingPathComponent(name))
        }
        try write("settings.json", ["PetSkin": "shenqing", "WindowLeft": -3000, "FocusMinutes": 40, "PetScale": 0.75])
        try write("focus-journal.json", ["Days": [["Date": "2026-09-23", "TargetCount": 4, "MinuteAdjustment": 12, "DailyNotes": "保留", "Sessions": []]]])
        try write("chat-memory.json", ["Threads": [["Id": "thread-1", "Title": "旧聊天", "IsArchived": true,
                "Messages": [["Role": "user", "Content": "你好", "CreatedAtUtc": "2026-09-23T12:00:00.0000000Z"]]]], "Facts": [["Text": "喜欢茶"]]])
        try write("active-focus.json", ["StartedAt": "2026-09-23T12:00:00Z", "PlannedMinutes": 25, "RemainingSeconds": 120.0, "Segments": []])
        var original = AppData()
        original.settings.windowX = 100
        let imported = try WindowsImport.read(directory, into: original)
        #expect(imported.settings.windowX == 100)
        #expect(imported.settings.skin == "shenqing")
        #expect(imported.journal.first?.total == 12)
        #expect(imported.threads.first?.messages.first?.content == "你好")
        #expect(imported.threads.first?.archived == true)
        #expect(imported.focus?.remaining == 120)
        #expect(imported.facts == ["喜欢茶"])
    }
    @Test func testAllAnimationAssetsExistAndPingPongSequencesMatch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appendingPathComponent("Assets/Sprites")
        for skin in ["suwudu", "shenqing"] {
            for state in PetState.allCases {
                for name in AnimationSpec.make(state, skin: skin).frames {
                    #expect(FileManager.default.fileExists(atPath: assets.appendingPathComponent(name).path), "Missing \(name)")
                }
            }
        }
        #expect(AnimationSpec.make(.working, skin: "suwudu").frames.count == 30)
        #expect(AnimationSpec.make(.heart, skin: "suwudu").frames.count == 15)
    }
}
