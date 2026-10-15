import Foundation
import Testing
@testable import SuWuDu

struct FocusAllocationEditorTests {
    private func share(_ id: String, in allocations: [FocusTaskAllocation]) -> Double {
        allocations.first { $0.taskID == id }?.share ?? -1
    }

    @Test func twoTasksDefaultToTwelveAndAHalfMinutesAndEditingTenLeavesFifteen() throws {
        var draft = FocusAllocationDraft(allocations: [], totalMinutes: 25)
        draft.changeSelection(["a", "b"])
        #expect(share("a", in: draft.allocations) * 25 == 12.5)
        #expect(share("b", in: draft.allocations) * 25 == 12.5)
        draft.setMinutesText("10", taskID: "a")
        try draft.commitMinutes("a")
        #expect(abs(share("a", in: draft.allocations) - 0.4) < 0.000001)
        #expect(abs(share("b", in: draft.allocations) - 0.6) < 0.000001)
        #expect(abs(share("b", in: draft.allocations) * 25 - 15) < 0.000001)
    }

    @Test func savingPendingTextWorksWithoutFocusLoss() throws {
        var draft = FocusAllocationDraft(allocations: FocusTaskAllocationRules.equal(["a", "b"]), totalMinutes: 25)
        #expect(!draft.hasChanges)
        draft.setMinutesText("10", taskID: "a")
        #expect(draft.hasChanges)
        let saved = try draft.preparedAllocations()
        #expect(abs(share("a", in: saved) - 0.4) < 0.000001)
        #expect(abs(share("b", in: saved) - 0.6) < 0.000001)
        #expect(share("a", in: draft.allocations) == 0.5)
    }

    @Test func unchangedRoundedThirdsPreserveExactEqualSplitsAndTotalMinutes() throws {
        let thirds = FocusTaskAllocationRules.equal(["a", "b", "c"])
        var draft = FocusAllocationDraft(allocations: thirds, totalMinutes: 25)
        try draft.commitMinutes("a")
        #expect(draft.allocations == thirds)
        #expect(!draft.hasChanges)
        draft.setMinutesText("10", taskID: "a")
        try draft.commitMinutes("a")
        #expect(abs(share("a", in: draft.allocations) * 25 - 10) < 0.000001)
        #expect(abs(share("b", in: draft.allocations) * 25 - 7.5) < 0.000001)
        #expect(abs(share("c", in: draft.allocations) * 25 - 7.5) < 0.000001)
        #expect(abs(draft.allocations.reduce(0) { $0 + $1.share * 25 } - 25) < 0.000001)
    }

    @Test func rebalancingPreservesTheOtherTasksRelativeAmounts() throws {
        var draft = FocusAllocationDraft(allocations: [
            .init(taskID: "a", share: 0.2), .init(taskID: "b", share: 0.3), .init(taskID: "c", share: 0.5)
        ], totalMinutes: 25)
        draft.setMinutesText("10", taskID: "a")
        try draft.commitMinutes("a")
        #expect(abs(share("b", in: draft.allocations) / share("c", in: draft.allocations) - 0.6) < 0.000001)
        #expect(abs(draft.allocations.reduce(0) { $0 + $1.share * 25 } - 25) < 0.000001)
    }

    @Test func invalidMinutesDoNotChangeAllocationsOrSilentlySaveTheOldValue() throws {
        let original = FocusTaskAllocationRules.equal(["a", "b"])
        for invalid in ["-1", "0", "25", "26", "NaN", "Infinity", "10 minutes", ""] {
            var draft = FocusAllocationDraft(allocations: original, totalMinutes: 25)
            draft.setMinutesText(invalid, taskID: "a")
            #expect(throws: (any Error).self) { try draft.commitMinutes("a") }
            #expect(draft.allocations == original)
            #expect(throws: (any Error).self) { try draft.preparedAllocations() }
            #expect(draft.allocations == original)
        }
    }

    @Test func invalidBlurredFieldRemainsVisibleAndBlocksSaveAfterEditingAnotherField() throws {
        var draft = FocusAllocationDraft(allocations: FocusTaskAllocationRules.equal(["a", "b", "c"]), totalMinutes: 25)
        draft.setMinutesText("-1", taskID: "a")
        #expect(throws: (any Error).self) { try draft.commitMinutes("a") }
        draft.setMinutesText("10", taskID: "b")
        try draft.commitMinutes("b")
        #expect(draft.minuteDrafts["a"] == "-1")
        #expect(throws: (any Error).self) { try draft.preparedAllocations() }
        draft.setMinutesText("5", taskID: "a")
        let saved = try draft.preparedAllocations()
        #expect(abs(share("a", in: saved) * 25 - 5) < 0.000001)
        #expect(abs(saved.reduce(0) { $0 + $1.share * 25 } - 25) < 0.000001)
    }

    @Test func selectionChangesEqualizeAndExplicitClearMarksMixedBatchAsChanged() throws {
        var draft = FocusAllocationDraft(allocations: [], totalMinutes: 25)
        #expect(!draft.hasChanges)
        draft.changeSelection([])
        #expect(draft.hasChanges)
        #expect(try draft.preparedAllocations().isEmpty)
        draft.changeSelection(["a", "b"])
        draft.setMinutesText("10", taskID: "a")
        try draft.commitMinutes("a")
        draft.changeSelection(["a", "b", "c"])
        #expect(draft.allocations == FocusTaskAllocationRules.equal(["a", "b", "c"]))
        draft.changeSelection(["a", "c"])
        #expect(draft.allocations == FocusTaskAllocationRules.equal(["a", "c"]))
    }

    @Test func zeroMinuteRecordsKeepTaskSelectionsWithoutInventingMinutes() throws {
        var draft = FocusAllocationDraft(allocations: [], totalMinutes: 0)
        draft.changeSelection(["a", "b"])
        try draft.commitMinutes("a")
        let saved = try draft.preparedAllocations()
        #expect(saved == FocusTaskAllocationRules.equal(["a", "b"]))
        #expect(saved.reduce(0) { $0 + $1.share * draft.totalMinutes } == 0)
        draft.setMinutesText("1", taskID: "a")
        #expect(throws: (any Error).self) { try draft.preparedAllocations() }
    }
}
