import Foundation

@MainActor extension AppModel {
    func requestMemoTaskExtraction(_ text: String) {
        guard !busy else { memoExtractionError = "请等待当前 AI 请求完成，或先取消它。"; return }
        clearFocusMatch()
        clearMemoTaskExtraction()
        let request = FocusMemoExtractionRequest(sourceText: text)
        do { try FocusMemoExtraction.validate(request) }
        catch { memoExtractionError = error.localizedDescription; return }
        guard text == (data.taskMemos ?? "") else {
            memoExtractionError = "备忘录尚未保存，请保存后重新整理。"; return
        }
        let settings = data.settings
        let requestID = UUID()
        memoExtractionRequestID = requestID
        memoExtractionBusy = true; busy = true
        memoExtractionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.memoExtractionRequestID == requestID {
                    self.memoExtractionBusy = false; self.busy = false; self.memoExtractionTask = nil
                }
            }
            do {
                let proposals: [FocusMemoTaskProposal]
                if let extractor = self.memoTaskExtractor {
                    proposals = try await extractor(request, settings)
                } else { proposals = try await self.ai.extractMemoTasks(request, settings: settings) }
                try Task.checkCancellation()
                guard self.memoExtractionRequestID == requestID else { return }
                guard request.sourceText == (self.data.taskMemos ?? "") else {
                    self.memoExtractionError = "备忘录在整理期间已有修改，请用最新内容重新生成预览。"; return
                }
                guard !proposals.isEmpty else {
                    self.memoExtractionError = "没有找到明确的待办任务，备忘录保持原样。"; return
                }
                self.memoExtractionPlan = FocusMemoExtractionPlan(sourceText: request.sourceText, proposals: proposals)
                self.memoExtractionError = nil
            } catch {
                guard self.memoExtractionRequestID == requestID, !Task.isCancelled else { return }
                self.memoExtractionError = error.localizedDescription
            }
        }
    }

    func cancelMemoTaskExtraction() {
        guard memoExtractionBusy else { return }
        memoExtractionRequestID = UUID()
        memoExtractionTask?.cancel(); memoExtractionTask = nil
        memoExtractionBusy = false; busy = false
        memoExtractionError = "已取消整理，任务和备忘录未修改。"
    }

    func clearMemoTaskExtraction() {
        cancelMemoTaskExtraction()
        memoExtractionPlan = nil; memoExtractionError = nil
    }

    @discardableResult func applyMemoTaskExtraction(_ proposals: [FocusMemoTaskProposal], selectedIDs: Set<String>) -> Bool {
        guard !memoExtractionBusy, !busy, let plan = memoExtractionPlan else { return false }
        guard plan.sourceText == (data.taskMemos ?? "") else {
            memoExtractionPlan = nil
            memoExtractionError = "备忘录在预览后已有修改，请用最新内容重新整理。"; return false
        }
        let originalIDs = Set(plan.proposals.map(\.id))
        guard !selectedIDs.isEmpty else { memoExtractionError = "请至少选中一个需要添加的任务。"; return false }
        guard originalIDs.count == plan.proposals.count, Set(proposals.map(\.id)) == originalIDs,
              proposals.count == originalIDs.count, selectedIDs.isSubset(of: originalIDs),
              proposals.allSatisfy({ proposal in
                  plan.proposals.contains { $0.id == proposal.id && $0.sourceExcerpt == proposal.sourceExcerpt }
              }) else {
            memoExtractionError = "预览内容已不一致，请重新整理备忘录。"; return false
        }
        let instant = Date()
        var newTasks: [FocusTask] = []
        var titles = Set((data.tasks ?? []).map { FocusMemoExtraction.normalizedTitle($0.title) })
        let existingIDs = Set((data.tasks ?? []).map(\.id))
        for proposal in proposals where selectedIDs.contains(proposal.id) {
            let title = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 300, proposal.notes.count <= 10_000,
                  proposal.estimatedPomodoros == nil || (0...10_000).contains(proposal.estimatedPomodoros!),
                  proposal.dueDate == nil || proposal.dueDate!.timeIntervalSince1970.isFinite,
                  !proposal.dueHasTime || proposal.dueDate != nil,
                  !existingIDs.contains(proposal.id) else {
                memoExtractionError = "部分任务名称、预计番茄数或截止日期无效，请修正后再添加。"; return false
            }
            guard titles.insert(FocusMemoExtraction.normalizedTitle(title)).inserted else {
                memoExtractionError = "「\(title)」与已有任务或本批任务重名，请取消勾选或修改名称后再添加。"; return false
            }
            newTasks.append(FocusTask(id: proposal.id, title: title, estimatedPomodoros: proposal.estimatedPomodoros,
                dueDate: proposal.dueDate, dueHasTime: proposal.dueHasTime, notes: proposal.notes,
                sourceExcerpt: proposal.sourceExcerpt, createdAt: instant, updatedAt: instant))
        }
        let previous = data
        data.tasks = (data.tasks ?? []) + newTasks
        guard persist() else {
            data = previous
            memoExtractionError = error ?? "任务未能保存，预览已保留，请重试。"
            return false
        }
        // Memo text remains unchanged. Clearing the preview makes a successful batch single-use.
        clearFocusMatch()
        clearMemoTaskExtraction()
        return true
    }
}
