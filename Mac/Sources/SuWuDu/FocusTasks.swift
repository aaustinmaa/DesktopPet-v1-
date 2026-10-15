import Foundation

struct FocusTask: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var estimatedPomodoros: Int?
    var dueDate: Date?
    var dueHasTime = false
    var notes = ""
    var isCompleted = false
    var completedAt: Date?
    var sourceExcerpt: String?
    var createdAt = Date()
    var updatedAt = Date()

    init(id: String = UUID().uuidString, title: String, estimatedPomodoros: Int? = nil,
         dueDate: Date? = nil, dueHasTime: Bool = false, notes: String = "", isCompleted: Bool = false,
         completedAt: Date? = nil, sourceExcerpt: String? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title
        self.estimatedPomodoros = estimatedPomodoros.map { max(0, $0) }
        self.dueDate = dueDate; self.dueHasTime = dueHasTime; self.notes = notes
        self.isCompleted = isCompleted; self.completedAt = completedAt; self.sourceExcerpt = sourceExcerpt
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, estimatedPomodoros, dueDate, dueHasTime, notes, isCompleted, completedAt, sourceExcerpt, createdAt, updatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decode(String.self, forKey: .title)
        estimatedPomodoros = try c.decodeIfPresent(Int.self, forKey: .estimatedPomodoros).map { max(0, $0) }
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        dueHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        sourceExcerpt = try c.decodeIfPresent(String.self, forKey: .sourceExcerpt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    mutating func reconcileCompletion(previous: FocusTask?, at instant: Date = Date()) {
        if !isCompleted { completedAt = nil }
        else if previous?.isCompleted == true { completedAt = previous?.completedAt }
        else { completedAt = instant }
        if let previous { sourceExcerpt = previous.sourceExcerpt }
    }

    // Date-only deadlines expire at the next calendar midnight, never the journal's 21:00 boundary.
    func isOverdue(at instant: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        if dueHasTime { return instant > dueDate }
        return calendar.startOfDay(for: instant) > calendar.startOfDay(for: dueDate)
    }
}

struct FocusTaskSummary: Equatable {
    var taskID: String
    var completedPomodoros = 0.0
    var minutes = 0.0
}

struct FocusTaskAllocation: Codable, Equatable, Identifiable {
    var taskID: String
    var share: Double
    var id: String { taskID }
}

enum FocusTaskAllocationRules {
    static let tolerance = 0.000001

    static func equal(_ ids: [String]) -> [FocusTaskAllocation] {
        let unique = Set(ids.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).sorted()
        guard !unique.isEmpty else { return [] }
        return unique.map { FocusTaskAllocation(taskID: $0, share: 1 / Double(unique.count)) }
    }

    static func normalized(_ allocations: [FocusTaskAllocation]) throws -> [FocusTaskAllocation] {
        guard !allocations.isEmpty else { return [] }
        guard Set(allocations.map(\.taskID)).count == allocations.count,
              allocations.allSatisfy({ !$0.taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.share.isFinite && $0.share > 0 && $0.share <= 1 }) else {
            throw FocusAssignmentError.invalidAllocations
        }
        let total = allocations.reduce(0) { $0 + $1.share }
        guard abs(total - 1) <= tolerance else { throw FocusAssignmentError.invalidAllocations }
        return allocations.sorted { $0.taskID < $1.taskID }
            .map { FocusTaskAllocation(taskID: $0.taskID, share: $0.share / total) }
    }

    static func same(_ lhs: [FocusTaskAllocation], _ rhs: [FocusTaskAllocation]) -> Bool {
        guard let left = try? normalized(lhs), let right = try? normalized(rhs), left.count == right.count else { return false }
        return zip(left, right).allSatisfy { pair in
            pair.0.taskID == pair.1.taskID && abs(pair.0.share - pair.1.share) <= tolerance
        }
    }
}

enum FocusTaskImport {
    // Produce candidates for a selectable preview; tasks can be edited after import. Parse only
    // explicit budget markers or an immediately following numeric line, keeping other text intact.
    static func preview(_ text: String) -> [FocusTask] {
        var result: [FocusTask] = []
        let budgets = [#"\s+-\s*(\d{1,3})\s*$"#,
                       #"\s+预计\s*(\d{1,3})\s*(?:个?\s*番茄(?:钟)?|🍅)?\s*$"#,
                       #"\s+(\d{1,3})\s*(?:个?\s*番茄(?:钟)?|🍅)\s*$"#]
            .map { try! NSRegularExpression(pattern: $0) }
        var canAttachBudget = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { canAttachBudget = false; continue }
            let numericLine = line.allSatisfy { $0.isASCII && $0.isNumber }
            if numericLine, let amount = Int(line), (0...999).contains(amount), canAttachBudget, !result.isEmpty {
                result[result.count - 1].estimatedPomodoros = amount
                canAttachBudget = false
                continue
            }
            var title = line.replacingOccurrences(of: #"^\s*(?:[-*•]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
            var estimate: Int?
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            if let match = budgets.compactMap({ $0.firstMatch(in: title, range: range) }).first,
               let valueRange = Range(match.range(at: 1), in: title),
               let fullRange = Range(match.range, in: title),
               String(title[..<fullRange.lowerBound]).range(of: #"(?:\s[-+]\s*\d|预计\s*\d|\d\s*(?:个?\s*番茄|🍅))"#,
                    options: .regularExpression) == nil {
                estimate = Int(title[valueRange])
                title.removeSubrange(fullRange)
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !title.isEmpty { result.append(FocusTask(title: title, estimatedPomodoros: estimate)) }
            canAttachBudget = !title.isEmpty && !numericLine && estimate == nil
        }
        return result
    }
}

extension FocusSession {
    var isPartial: Bool { source == "partial" }
    var isMinuteConversion: Bool { !isPartial && actualMinutes == 0 && completedPomodoro == false }
    var recordingSourceLabel: String {
        if isPartial { return "提前结束" }
        if isMinuteConversion { return "分钟换算" }
        return source == "automatic" ? "自动" : "手动"
    }
    var taskMinutes: Int {
        if isPartial { return max(0, minutes) }
        return max(0, actualMinutes ?? minutes)
    }
    var isCompletedPomodoro: Bool { !isPartial && actualMinutes != 0 && (completedPomodoro ?? countsTowardGoal) }
}

extension JournalDay {
    // Partial records are detail for minutes already in adjustment. Keep their accounting contribution
    // in sync with explicit edits, without adding those minutes to total a second time.
    mutating func reconcilePartialWorkEdits(previous: JournalDay) {
        let before = previous.sessions.filter(\.isPartial).reduce(0) { $0 + $1.minutes }
        let after = sessions.filter(\.isPartial).reduce(0) { $0 + $1.minutes }
        adjustment += after - before
        for index in sessions.indices {
            if sessions[index].isPartial {
                sessions[index].countsTowardGoal = false
                sessions[index].actualMinutes = sessions[index].minutes
            } else if let original = previous.sessions.first(where: { $0.id == sessions[index].id }),
                      original.minutes != sessions[index].minutes, original.actualMinutes != 0 {
                sessions[index].actualMinutes = sessions[index].minutes
            }
        }
    }
}

struct FocusJournalRecords {
    let counted: [FocusSession]
    let minutes: [FocusSession]
    let excluded: [FocusSession]
    var matchable: [FocusSession] { counted.filter { !$0.isMinuteConversion } }

    init(sessions: [FocusSession]) {
        let ordered = sessions.sorted {
            $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt
        }
        counted = ordered.filter { !$0.isPartial && $0.countsTowardGoal }
        minutes = ordered.filter(\.isPartial)
        excluded = ordered.filter { !$0.isPartial && !$0.countsTowardGoal }
    }
}

struct FocusAssignmentChange: Equatable {
    var sessionID: String
    var targetAllocations: [FocusTaskAllocation]
    var expectedAllocations: [FocusTaskAllocation]
    var expectedRevision: Int
    var expectedNotes: String
    var reason: String
    var expectedSession: FocusSession?

    var targetTaskID: String? {
        get { targetAllocations.count == 1 ? targetAllocations[0].taskID : nil }
        set { targetAllocations = FocusTaskAllocationRules.equal(newValue.map { [$0] } ?? []) }
    }
    var expectedTaskID: String? {
        get { expectedAllocations.count == 1 ? expectedAllocations[0].taskID : nil }
        set { expectedAllocations = FocusTaskAllocationRules.equal(newValue.map { [$0] } ?? []) }
    }

    init(sessionID: String, targetAllocations: [FocusTaskAllocation], expectedAllocations: [FocusTaskAllocation],
         expectedRevision: Int = 0, expectedNotes: String, reason: String = "") {
        self.sessionID = sessionID; self.targetAllocations = targetAllocations; self.expectedAllocations = expectedAllocations
        self.expectedRevision = expectedRevision; self.expectedNotes = expectedNotes; self.reason = reason
    }

    init(sessionID: String, targetTaskID: String?, expectedTaskID: String?, expectedRevision: Int = 0,
         expectedNotes: String, reason: String = "") {
        self.init(sessionID: sessionID, targetAllocations: FocusTaskAllocationRules.equal(targetTaskID.map { [$0] } ?? []),
                  expectedAllocations: FocusTaskAllocationRules.equal(expectedTaskID.map { [$0] } ?? []),
                  expectedRevision: expectedRevision, expectedNotes: expectedNotes, reason: reason)
    }
    init(session: FocusSession, targetTaskID: String?, reason: String = "") {
        self.init(session: session, targetAllocations: FocusTaskAllocationRules.equal(targetTaskID.map { [$0] } ?? []), reason: reason)
    }
    init(session: FocusSession, targetAllocations: [FocusTaskAllocation], reason: String = "") {
        self.init(sessionID: session.id, targetAllocations: targetAllocations, expectedAllocations: session.allocations,
                  expectedRevision: session.assignmentRevision ?? 0, expectedNotes: session.notes, reason: reason)
        expectedSession = session
    }
}

struct FocusMatchingPlan: Equatable {
    var changes: [FocusAssignmentChange]
    var source = "ai"
}

struct FocusAssignmentTransaction {
    struct Entry {
        var sessionID: String
        var previousAllocations: [FocusTaskAllocation]
        var previousSource: String?
        var appliedAllocations: [FocusTaskAllocation]
        var appliedSource: String
        var appliedRevision: Int
    }
    var entries: [Entry]
}

enum FocusAssignmentError: LocalizedError, Equatable {
    case duplicateSession, missingSession, missingTask, staleSession, emptyPlan, invalidAllocations
    var errorDescription: String? {
        switch self {
        case .duplicateSession: return "匹配结果包含重复记录，未应用修改。"
        case .missingSession: return "部分专注记录已经删除，请刷新后重新匹配。"
        case .missingTask: return "部分任务已经删除，请刷新后重新匹配。"
        case .staleSession: return "记录在预览之后已有修改，未覆盖这些修改。请重新生成预览。"
        case .emptyPlan: return "没有需要修改的匹配结果。"
        case .invalidAllocations: return "任务分配无效，请检查各任务用时后重试。"
        }
    }
}

extension AppData {
    func taskSummaries(journal selectedJournal: [JournalDay]? = nil) -> [FocusTaskSummary] {
        var result: [String: FocusTaskSummary] = [:]
        for task in tasks ?? [] { result[task.id] = FocusTaskSummary(taskID: task.id) }
        for session in (selectedJournal ?? journal).flatMap(\.sessions) {
            guard let allocations = try? FocusTaskAllocationRules.normalized(session.allocations) else { continue }
            for allocation in allocations {
                let taskID = allocation.taskID
                if result[taskID] == nil { result[taskID] = FocusTaskSummary(taskID: taskID) }
                result[taskID]!.minutes += Double(session.taskMinutes) * allocation.share
                if session.isCompletedPomodoro { result[taskID]!.completedPomodoros += allocation.share }
            }
        }
        return result.values.sorted { $0.taskID < $1.taskID }
    }

    func validateAssignments(_ plan: FocusMatchingPlan) throws {
        guard !plan.changes.isEmpty else { throw FocusAssignmentError.emptyPlan }
        guard Set(plan.changes.map(\.sessionID)).count == plan.changes.count else { throw FocusAssignmentError.duplicateSession }
        let taskIDs = Set((tasks ?? []).map(\.id))
        let sessions = journal.flatMap(\.sessions)
        for change in plan.changes {
            let matches = sessions.filter { $0.id == change.sessionID }
            guard matches.count == 1, let session = matches.first else {
                throw matches.isEmpty ? FocusAssignmentError.missingSession : FocusAssignmentError.duplicateSession
            }
            let target = try FocusTaskAllocationRules.normalized(change.targetAllocations)
            _ = try FocusTaskAllocationRules.normalized(change.expectedAllocations)
            guard target.allSatisfy({ taskIDs.contains($0.taskID) }) else { throw FocusAssignmentError.missingTask }
            guard FocusTaskAllocationRules.same(session.allocations, change.expectedAllocations),
                  (session.assignmentRevision ?? 0) == change.expectedRevision,
                  change.expectedRevision < Int.max,
                  session.notes == change.expectedNotes,
                  change.expectedSession == nil || change.expectedSession == session else { throw FocusAssignmentError.staleSession }
        }
    }

    @discardableResult mutating func applyAssignments(_ plan: FocusMatchingPlan) throws -> FocusAssignmentTransaction {
        try validateAssignments(plan)
        var transaction = FocusAssignmentTransaction(entries: [])
        for change in plan.changes {
            let dayIndex = journal.firstIndex { $0.sessions.contains { $0.id == change.sessionID } }!
            let sessionIndex = journal[dayIndex].sessions.firstIndex { $0.id == change.sessionID }!
            var session = journal[dayIndex].sessions[sessionIndex]
            let revision = (session.assignmentRevision ?? 0) + 1
            let target = try FocusTaskAllocationRules.normalized(change.targetAllocations)
            transaction.entries.append(.init(sessionID: session.id, previousAllocations: session.allocations,
                previousSource: session.assignmentSource, appliedAllocations: target,
                appliedSource: plan.source, appliedRevision: revision))
            session.allocations = target; session.assignmentSource = plan.source; session.assignmentRevision = revision
            journal[dayIndex].sessions[sessionIndex] = session
        }
        return transaction
    }

    mutating func undoAssignments(_ transaction: FocusAssignmentTransaction) throws {
        let sessions = journal.flatMap(\.sessions)
        guard !transaction.entries.isEmpty else { throw FocusAssignmentError.emptyPlan }
        guard Set(transaction.entries.map(\.sessionID)).count == transaction.entries.count else { throw FocusAssignmentError.duplicateSession }
        for entry in transaction.entries {
            let matches = sessions.filter { $0.id == entry.sessionID }
            guard matches.count == 1, let session = matches.first else { throw FocusAssignmentError.missingSession }
            guard FocusTaskAllocationRules.same(session.allocations, entry.appliedAllocations), session.assignmentSource == entry.appliedSource,
                  session.assignmentRevision == entry.appliedRevision,
                  entry.appliedRevision < Int.max else { throw FocusAssignmentError.staleSession }
            let previous = try FocusTaskAllocationRules.normalized(entry.previousAllocations)
            guard previous.allSatisfy({ allocation in (tasks ?? []).contains(where: { $0.id == allocation.taskID }) }) else {
                throw FocusAssignmentError.missingTask
            }
        }
        for entry in transaction.entries {
            let dayIndex = journal.firstIndex { $0.sessions.contains { $0.id == entry.sessionID } }!
            let sessionIndex = journal[dayIndex].sessions.firstIndex { $0.id == entry.sessionID }!
            journal[dayIndex].sessions[sessionIndex].allocations = entry.previousAllocations
            journal[dayIndex].sessions[sessionIndex].assignmentSource = entry.previousSource
            // Revisions remain monotonic: an older preview must stay stale after an undo.
            journal[dayIndex].sessions[sessionIndex].assignmentRevision = entry.appliedRevision + 1
        }
    }
}
