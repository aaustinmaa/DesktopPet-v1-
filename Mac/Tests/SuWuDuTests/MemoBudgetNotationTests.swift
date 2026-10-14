import Foundation
import Testing
@testable import SuWuDu

struct MemoBudgetNotationTests {
    private let memo = """
    Cs370 - 15, catchup cheat sheet +5
    CS479 - 25, catchup cheat sheet +7
    CS341 - 8

    Build personal website
    20
    Nexo project
    """

    private func request(_ source: String) -> FocusMemoExtractionRequest {
        FocusMemoExtractionRequest(sourceText: source,
            referenceDate: Date(timeIntervalSince1970: 1_792_008_000),
            timeZoneIdentifier: "America/Toronto")
    }

    private func task(_ title: String, estimate: Any = NSNull(), dueDate: Any = NSNull(),
                      dueTime: Any = NSNull(), source: String, notes: String = "") -> [String: Any] {
        ["title": title, "estimatedPomodoros": estimate, "dueDate": dueDate,
         "dueTime": dueTime, "notes": notes, "sourceExcerpt": source]
    }

    private func response(_ tasks: [[String: Any]]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["tasks": tasks]), as: UTF8.self)
    }

    @Test func screenshotMemoAcceptsSevenCanonicalTasksWithoutReinterpretingBudgets() throws {
        let course370 = "Cs370 - 15, catchup cheat sheet +5"
        let course479 = "CS479 - 25, catchup cheat sheet +7"
        let raw = try response([
            task("Cs370", estimate: 15, source: "Cs370 - 15"),
            task("Cs370 catchup cheat sheet", estimate: 5, source: course370),
            task("CS479", estimate: 25, source: "CS479 - 25"),
            task("CS479 catchup cheat sheet", estimate: 7, source: course479),
            task("CS341", estimate: 8, source: "CS341 - 8"),
            task("Build personal website", estimate: 20, source: "Build personal website\n20"),
            task("Nexo project", source: "Nexo project")
        ])
        let proposals = try FocusMemoExtraction.parse(raw, request: request(memo))
        #expect(proposals.map(\.estimatedPomodoros) == [15, 5, 25, 7, 8, 20, nil])
        #expect(proposals.map(\.title) == ["Cs370", "Cs370 catchup cheat sheet", "CS479",
            "CS479 catchup cheat sheet", "CS341", "Build personal website", "Nexo project"])
        #expect(proposals[1].sourceExcerpt == course370)
        #expect(proposals[5].sourceExcerpt == "Build personal website\n20")
        #expect(proposals.allSatisfy { $0.dueDate == nil && !$0.dueHasTime && $0.notes.isEmpty })
    }

    @Test func normalizedAIResponseWorksAcrossInputNotationsWithoutLocalGrammarRules() throws {
        for source in ["CS370: fifteen pomodoros", "CS370【15】", "CS370 → 15", "CS370 budget = 15"] {
            let raw = try response([task("CS370", estimate: 15, source: source, notes: "Review course materials")])
            let proposals = try FocusMemoExtraction.parse(raw, request: request(source))
            let proposal = try #require(proposals.first)
            #expect(proposal.estimatedPomodoros == 15)
            #expect(proposal.sourceExcerpt == source)
            #expect(proposal.notes == "Review course materials")
        }
    }

    @Test func promptDocumentsMemoHabitsAndItsCompleteExampleUsesTheOutputContract() throws {
        let instructions = FocusMemoExtraction.instructions
        #expect(instructions.contains("Cs370 - 15, catchup cheat sheet +5"))
        #expect(instructions.contains("CS479 - 25, catchup cheat sheet +7"))
        #expect(instructions.contains("Build personal website"))
        #expect(instructions.contains("Nexo project"))
        #expect(instructions.contains("Mod 10"))
        #expect(instructions.contains("POMODOROS") || instructions.contains("pomodoros"))
        let marker = try #require(instructions.range(of: "Example output:\n"))
        let example = try #require(instructions[marker.upperBound...].split(separator: "\n").first)
        let proposals = try FocusMemoExtraction.parse(String(example), request: request(memo))
        #expect(proposals.count == 7)
        #expect(proposals.map(\.estimatedPomodoros) == [15, 5, 25, 7, 8, 20, nil])

        let schemaProperties = try #require(FocusMemoExtraction.schema["properties"] as? [String: Any])
        let tasksSchema = try #require(schemaProperties["tasks"] as? [String: Any])
        let taskSchema = try #require(tasksSchema["items"] as? [String: Any])
        let properties = try #require(taskSchema["properties"] as? [String: Any])
        let required = try #require(taskSchema["required"] as? [String])
        let fields: Set<String> = ["title", "estimatedPomodoros", "dueDate", "dueTime", "notes", "sourceExcerpt"]
        #expect(Set(properties.keys) == fields)
        #expect(Set(required) == fields)
        #expect(taskSchema["additionalProperties"] as? Bool == false)
    }

    @Test func unknownOptionalValuesRemainNullAndNotesRemainUnchanged() throws {
        let source = "Nexo project"
        let raw = try response([task("Nexo project", source: source, notes: "Scope to be decided")])
        let proposal = try #require(try FocusMemoExtraction.parse(raw, request: request(source)).first)
        #expect(proposal.estimatedPomodoros == nil)
        #expect(proposal.dueDate == nil)
        #expect(!proposal.dueHasTime)
        #expect(proposal.notes == "Scope to be decided")
    }

    @Test func malformedTypesMissingFieldsAndLegacyKeysRejectTheWholeResponse() throws {
        let source = "CS341 - 8\nNexo project"
        let valid = task("CS341", estimate: 8, source: "CS341 - 8")
        let baseline = task("Nexo project", source: "Nexo project")
        var invalidTasks: [[String: Any]] = []
        for (field, value) in [("estimatedPomodoros", "8" as Any),
                               ("estimatedPomodoros", true as Any),
                               ("estimatedPomodoros", 2.5 as Any),
                               ("estimatedPomodoros", -1 as Any),
                               ("estimatedPomodoros", 10_001 as Any),
                               ("title", NSNull() as Any),
                               ("notes", NSNull() as Any),
                               ("sourceExcerpt", NSNull() as Any)] {
            var invalid = baseline; invalid[field] = value; invalidTasks.append(invalid)
        }
        for field in baseline.keys {
            var invalid = baseline; invalid.removeValue(forKey: field); invalidTasks.append(invalid)
        }
        for field in ["estimateText", "deadlineText", "unexpected"] {
            var invalid = baseline; invalid[field] = NSNull(); invalidTasks.append(invalid)
        }
        for invalid in invalidTasks {
            let raw = try response([valid, invalid])
            #expect(throws: (any Error).self) { try FocusMemoExtraction.parse(raw, request: request(source)) }
        }
        for raw in ["not JSON", #"{"tasks":[],"unexpected":true}"#, #"{"tasks":[null]}"#] {
            #expect(throws: (any Error).self) { try FocusMemoExtraction.parse(raw, request: request(source)) }
        }
    }

    @Test func invalidNormalizedDatesAndTimesRejectTheWholeResponse() throws {
        let source = "Nexo project"
        for (date, time) in [
            ("2026/10/16" as Any, NSNull() as Any),
            ("tomorrow" as Any, NSNull() as Any),
            ("2026-02-30" as Any, NSNull() as Any),
            ("2026-10-16" as Any, "3pm" as Any),
            ("2026-10-16" as Any, "9:30" as Any),
            ("2026-10-16" as Any, "24:00" as Any),
            (NSNull() as Any, "17:30" as Any),
            (20261016 as Any, NSNull() as Any),
            ("2026-10-16" as Any, 1730 as Any)
        ] {
            let raw = try response([task("Nexo project", dueDate: date, dueTime: time, source: source)])
            #expect(throws: (any Error).self) { try FocusMemoExtraction.parse(raw, request: request(source)) }
        }
    }

    @Test func fabricatedSourceStillRejectsTheWholeResponse() throws {
        let source = "CS341 - 8\nNexo project"
        let raw = try response([
            task("CS341", estimate: 8, source: "CS341 - 8"),
            task("Nexo project", source: "not in the memo")
        ])
        #expect(throws: (any Error).self) { try FocusMemoExtraction.parse(raw, request: request(source)) }
    }
}
