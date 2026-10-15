import Foundation

@MainActor extension AppModel {
    @discardableResult func saveFocusTask(_ task: FocusTask) -> Bool {
        var value = task
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty, value.title.count <= 300 else {
            matchingError = "任务名称须为 1–300 个字符。"; return false
        }
        guard value.estimatedPomodoros == nil || (0...10_000).contains(value.estimatedPomodoros!) else {
            matchingError = "预计番茄数须在 0–10000 之间，也可以留空。"; return false
        }
        let previous = data
        value.updatedAt = Date()
        var tasks = data.tasks ?? []
        if let index = tasks.firstIndex(where: { $0.id == value.id }) {
            value.reconcileCompletion(previous: tasks[index]); tasks[index] = value
        } else { value.reconcileCompletion(previous: nil); tasks.append(value) }
        data.tasks = tasks
        guard persist() else { data = previous; return false }
        clearFocusMatch()
        return true
    }

    @discardableResult func deleteFocusTask(_ id: String) -> Bool {
        guard !(data.tasks ?? []).contains(where: { $0.id == id && $0.isCompleted }) else {
            matchingError = "已完成任务保留在历史记录中；如需删除，请先重新打开任务。"; return false
        }
        guard !(data.focus?.allocations.contains(where: { $0.taskID == id }) ?? false),
              !data.journal.flatMap(\.sessions).contains(where: { $0.allocations.contains { $0.taskID == id } }) else {
            matchingError = "这个任务仍有关联的专注记录，请标记完成以保留历史。"; return false
        }
        let previous = data
        data.tasks?.removeAll { $0.id == id }
        let remaining = data.currentAllocations.filter { $0.taskID != id }
        let total = remaining.reduce(0) { $0 + $1.share }
        data.currentAllocations = remaining.map { FocusTaskAllocation(taskID: $0.taskID, share: $0.share / total) }
        guard persist() else { data = previous; return false }
        clearFocusMatch()
        return true
    }

    @discardableResult func selectFocusTask(_ id: String?) -> Bool {
        selectFocusTasks(FocusTaskAllocationRules.equal(id.map { [$0] } ?? []))
    }

    @discardableResult func selectFocusTasks(_ allocations: [FocusTaskAllocation]) -> Bool {
        let normalized: [FocusTaskAllocation]
        do { normalized = try FocusTaskAllocationRules.normalized(allocations) }
        catch { matchingError = error.localizedDescription; return false }
        let taskIDs = Set((data.tasks ?? []).map(\.id))
        guard normalized.allSatisfy({ taskIDs.contains($0.taskID) }) else {
            matchingError = "任务已不存在，请刷新任务清单。"; return false
        }
        let previous = data
        // An active run keeps its captured distribution. The selection applies to the next run.
        data.currentAllocations = normalized
        guard persist() else { data = previous; return false }
        matchingError = nil
        return true
    }

    @discardableResult func saveTaskMemos(_ text: String) -> Bool {
        let previous = data.taskMemos
        data.taskMemos = text
        guard persist() else { data.taskMemos = previous; return false }
        if previous != text { clearMemoTaskExtraction() }
        return true
    }

    @discardableResult func assignFocusSessions(_ sessions: [FocusSession], to taskID: String?) -> Bool {
        assignFocusSessions(sessions, allocations: FocusTaskAllocationRules.equal(taskID.map { [$0] } ?? []))
    }

    @discardableResult func assignFocusSessions(_ sessions: [FocusSession], allocations: [FocusTaskAllocation]) -> Bool {
        let normalized: [FocusTaskAllocation]
        do { normalized = try FocusTaskAllocationRules.normalized(allocations) }
        catch { matchingError = error.localizedDescription; return false }
        let changes = sessions.filter { !FocusTaskAllocationRules.same($0.allocations, normalized) && !isConversionRecord($0) }
            .map { FocusAssignmentChange(session: $0, targetAllocations: normalized) }
        guard !changes.isEmpty else {
            matchingError = "没有需要修改的专注明细；分钟换算记录只用于每日目标统计。"; return false
        }
        return commitFocusAssignments(FocusMatchingPlan(changes: changes, source: "manual"))
    }

    @discardableResult func appendFocusSessions(_ sessions: [FocusSession], taskIDs: [String]) -> Bool {
        let requested = Set(taskIDs)
        let known = Set((data.tasks ?? []).map(\.id))
        guard requested.isSubset(of: known) else {
            matchingError = FocusAssignmentError.missingTask.localizedDescription; return false
        }
        guard !requested.isEmpty else { matchingError = nil; return true }
        let candidates = sessions.filter { !isConversionRecord($0) }.map { session in
            let existing = Set(session.allocations.map(\.taskID))
            let target = requested.isSubset(of: existing) ? session.allocations
                : FocusTaskAllocationRules.equal(Array(existing.union(requested)))
            return FocusAssignmentChange(session: session, targetAllocations: target)
        }
        guard !candidates.isEmpty else { matchingError = nil; return true }
        do {
            // Check the whole selected snapshot, including records that already contain
            // the requested tasks, before committing any changes in this batch.
            try data.validateAssignments(FocusMatchingPlan(changes: candidates, source: "manual"))
        } catch { matchingError = error.localizedDescription; return false }
        let changes = candidates.filter {
            !FocusTaskAllocationRules.same($0.expectedAllocations, $0.targetAllocations)
        }
        guard !changes.isEmpty else {
            // A repeated add must preserve custom minutes and the previous undo action.
            matchingError = nil; return true
        }
        return commitFocusAssignments(FocusMatchingPlan(changes: changes, source: "manual"))
    }

    @discardableResult func undoFocusAssignments() -> Bool {
        guard let transaction = focusAssignmentUndo else { return false }
        let previous = data
        do {
            try data.undoAssignments(transaction)
            guard persist() else { data = previous; return false }
            focusAssignmentUndo = nil; canUndoFocusAssignments = false
            matchingPlan = nil; matchingError = nil
            return true
        } catch {
            data = previous; matchingError = error.localizedDescription; return false
        }
    }

    @discardableResult func applyFocusMatch() -> Bool {
        guard !matchingBusy, let plan = matchingPlan else { return false }
        return commitFocusAssignments(plan)
    }

    func clearFocusMatch() {
        cancelFocusMatch()
        matchingPlan = nil; matchingError = nil
    }

    func cancelFocusMatch() {
        guard matchingBusy else { return }
        focusMatchRequestID = UUID()
        focusMatchTask?.cancel(); focusMatchTask = nil
        matchingBusy = false; busy = false
        matchingError = "已取消匹配，记录未修改。"
    }

    func requestFocusMatch(_ instruction: String, sessions: [FocusSession]) {
        startFocusMatching(instruction: instruction, sessions: sessions, onlyUnassigned: false)
    }

    func requestFocusSuggestions(sessions: [FocusSession], useAI: Bool) {
        let candidates = sessions.filter { $0.allocations.isEmpty && !isConversionRecord($0) }
        if useAI {
            startFocusMatching(instruction: "仅根据单次 Notes 中明确的任务线索，建议这些未关联记录的任务。线索不足或存在歧义就省略；不要按截止日期、预计番茄数或时间猜测。", sessions: candidates, onlyUnassigned: true)
            return
        }
        guard !busy else { return }
        clearMemoTaskExtraction()
        matchingError = nil; matchingPlan = nil
        let request = focusMatchSnapshot(instruction: "根据明确任务名生成本机建议", sessions: candidates)
        let proposals = FocusTaskMatching.localSuggestions(tasks: request.tasks, sessions: request.sessions)
        publishFocusProposals(proposals, sessions: candidates, source: "keyword", onlyUnassigned: true)
    }

    private func startFocusMatching(instruction: String, sessions: [FocusSession], onlyUnassigned: Bool) {
        guard !busy else { matchingError = "请等待当前 AI 请求完成，或先取消它。"; return }
        clearMemoTaskExtraction()
        matchingPlan = nil; matchingError = nil
        let snapshots = sessions.filter { !isConversionRecord($0) }
        let request = focusMatchSnapshot(instruction: instruction, sessions: snapshots)
        do { try FocusTaskMatching.validate(request) }
        catch { matchingError = error.localizedDescription; return }
        let settings = data.settings
        let requestID = UUID()
        focusMatchRequestID = requestID
        matchingPlan = nil; matchingError = nil; matchingBusy = true; busy = true
        focusMatchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.focusMatchRequestID == requestID {
                    self.matchingBusy = false; self.busy = false; self.focusMatchTask = nil
                }
            }
            do {
                let proposals = try await self.ai.matchFocusTasks(request, settings: settings)
                try Task.checkCancellation()
                guard self.focusMatchRequestID == requestID else { return }
                self.publishFocusProposals(proposals, sessions: snapshots, source: "ai", onlyUnassigned: onlyUnassigned)
            } catch {
                guard self.focusMatchRequestID == requestID, !Task.isCancelled else { return }
                self.matchingError = error.localizedDescription
            }
        }
    }

    private func focusMatchSnapshot(instruction: String, sessions: [FocusSession]) -> FocusMatchRequest {
        FocusMatchRequest(instruction: instruction,
            tasks: (data.tasks ?? []).map { FocusMatchTask(id: $0.id, title: $0.title, notes: $0.notes) },
            sessions: sessions.map { FocusMatchSession(id: $0.id, startedAt: $0.startedAt,
                completedAt: $0.completedAt, minutes: Double($0.taskMinutes), notes: $0.notes, allocations: $0.allocations,
                assignmentRevision: $0.assignmentRevision ?? 0) })
    }

    private func publishFocusProposals(_ proposals: [FocusMatchProposal], sessions: [FocusSession],
                                      source: String, onlyUnassigned: Bool) {
        let changes = proposals.compactMap { proposal -> FocusAssignmentChange? in
            guard let session = sessions.first(where: { $0.id == proposal.sessionID }),
                  !onlyUnassigned || session.allocations.isEmpty,
                  !FocusTaskAllocationRules.same(session.allocations, proposal.allocations) else { return nil }
            return FocusAssignmentChange(session: session, targetAllocations: proposal.allocations, reason: proposal.reason)
        }
        guard !changes.isEmpty else {
            matchingError = "没有找到明确的匹配线索，现有归属保持不变。可补充时间段和任务名称后再试。"; return
        }
        let plan = FocusMatchingPlan(changes: changes, source: source)
        do { try data.validateAssignments(plan); matchingPlan = plan; matchingError = nil }
        catch { matchingPlan = nil; matchingError = error.localizedDescription }
    }

    private func isConversionRecord(_ session: FocusSession) -> Bool {
        session.actualMinutes == 0 && session.completedPomodoro == false && !session.isPartial
    }

    private func commitFocusAssignments(_ plan: FocusMatchingPlan) -> Bool {
        let previous = data
        do {
            let transaction = try data.applyAssignments(plan)
            guard persist() else { data = previous; return false }
            focusAssignmentUndo = transaction; canUndoFocusAssignments = true
            matchingPlan = nil; matchingError = nil
            return true
        } catch {
            data = previous; matchingError = error.localizedDescription; return false
        }
    }
}
