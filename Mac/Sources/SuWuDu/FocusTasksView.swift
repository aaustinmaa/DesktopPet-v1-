import SwiftUI

@MainActor struct FocusTaskTimerBar: View {
    @ObservedObject var model: AppModel
    private var tasks: [FocusTask] { model.data.tasks ?? [] }
    private var taskSelection: Binding<String> {
        Binding(get: { model.data.currentTaskID ?? "" }, set: { _ = model.selectFocusTask($0.isEmpty ? nil : $0) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { taskPicker; Spacer(minLength: 12); controls }
                VStack(alignment: .leading, spacing: 12) { taskPicker; controls }
            }
            if let run = model.data.focus {
                Text("本轮：\(taskTitle(run.taskID))。任务选择会沿用到之后的番茄；更换选择从下一轮生效。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            } else {
                Text("选一次任务，之后的番茄自动沿用；也可以先专注，再整批补关联。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            }
        }.padding(.horizontal, 22).padding(.vertical, 14).background(PetTheme.card)
    }
    private var taskPicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope").foregroundStyle(PetTheme.accent)
            Text(model.data.focus == nil ? "当前任务" : "下一轮任务").font(.callout.weight(.semibold))
            Picker("当前任务", selection: taskSelection) {
                Text("未选择任务").tag("")
                ForEach(tasks.filter { !$0.isCompleted || $0.id == model.data.currentTaskID }) { task in
                    Text(task.title).tag(task.id)
                }
            }.labelsHidden().frame(minWidth: 170, maxWidth: 330)
        }
    }
    private var controls: some View {
        HStack(spacing: 10) {
            Text(model.focusLabel).font(.callout.weight(.semibold)).monospacedDigit()
            Button(model.data.focus == nil ? (model.breakRemaining > 0 ? "开始下一轮" : "开始专注") : (model.paused ? "继续" : "暂停")) {
                model.toggleFocus()
            }.buttonStyle(PetButtonStyle(primary: true))
            if model.data.focus != nil {
                Button("重新开始") { model.startFocus() }
                    .help("记录本轮已完成的分钟，重新开始完整一轮。")
            }
            if model.data.focus != nil || model.breakRemaining > 0 {
                Button(model.data.focus == nil ? "结束休息" : "结束并记录") { model.stopFocus() }
            }
        }
    }
    private func taskTitle(_ id: String?) -> String {
        guard let id else { return "未关联任务" }
        return tasks.first { $0.id == id }?.title ?? "已删除任务"
    }
}

@MainActor struct FocusTasksView: View {
    @ObservedObject var model: AppModel
    var selectedSessionCount: Int
    var assignSelection: (String?) -> Void
    var onSelectJournalDay: ((String) -> Void)? = nil
    @State private var search = ""
    @State private var sortByDue = true
    @State private var showingHistory = false
    @State private var expandedHistory: Set<String> = []
    @State private var editingTask: FocusTask?
    @State private var memos = ""
    @State private var savedMemos = ""
    @State private var memoStatus = ""
    @State private var showingImport = false
    @State private var showingMemoExtraction = false
    @State private var taskError: String?
    private var tasks: [FocusTask] { model.data.tasks ?? [] }
    private var visibleTasks: [FocusTask] {
        tasks.filter { $0.isCompleted == showingHistory && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search) || ($0.sourceExcerpt?.localizedCaseInsensitiveContains(search) ?? false)) }
            .sorted {
                if showingHistory {
                    if $0.completedAt != $1.completedAt { return ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                    return $0.updatedAt > $1.updatedAt
                }
                if sortByDue, $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                return $0.createdAt < $1.createdAt
            }
    }
    private var summaries: [FocusTaskSummary] { model.data.taskSummaries() }
    var body: some View {
        VStack(spacing: 16) {
            PetCard {
                HStack {
                    Text("任务清单").font(.title3.bold())
                    Spacer()
                    Button { editingTask = FocusTask(title: "") } label: { Label("新增", systemImage: "plus") }
                }
                Picker("任务状态", selection: $showingHistory) {
                    Text("进行中 \(tasks.filter { !$0.isCompleted }.count)").tag(false)
                    Text("完成历史 \(tasks.filter(\.isCompleted).count)").tag(true)
                }.pickerStyle(.segmented)
                TextField(showingHistory ? "搜索历史任务、说明或原文" : "搜索任务或说明", text: $search)
                HStack {
                    Text(showingHistory ? "按完成时间排列，展开可追溯专注明细。" : "所有待办都在这一份清单中。")
                        .font(.caption).foregroundStyle(PetTheme.muted)
                    Spacer()
                    if !showingHistory { Toggle("截止优先", isOn: $sortByDue).font(.caption) }
                }
                if selectedSessionCount > 0 {
                    Text("已选 \(selectedSessionCount) 条记录，点击任务旁的关联按钮即可整批匹配。")
                        .font(.caption).foregroundStyle(PetTheme.accent)
                }
                if visibleTasks.isEmpty {
                    Text(search.isEmpty ? (showingHistory ? "完成的任务会保存在这里，保留说明与每次专注的记录。" : "把计划写成任务，预计番茄数和截止日期都可以留空。") : "没有符合筛选条件的任务。")
                        .font(.callout).foregroundStyle(PetTheme.muted).padding(.vertical, 14)
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleTasks) { task in taskRow(task) }
                }
                if let taskError { Text(taskError).font(.caption).foregroundStyle(.red) }
                Divider()
                Button("粘贴清单…") { showingImport = true }
                    .help("先预览任务，再选择导入；购物清单和自由备忘可保留在下方。")
            }
            PetCard("备忘") {
                Text("保留想法、链接和日常提醒，需要执行时再转成任务。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
                NotesEditor(text: $memos).frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
                ViewThatFits(in: .horizontal) {
                    HStack { memoButtons }
                    VStack(alignment: .leading, spacing: 8) { memoButtons }
                }
                Text(model.data.settings.provider == "offline" ? "AI 提取任务使用设置中的 AI 服务；离线时仍可手动转成任务。" : "AI 会先列出可执行的任务，可修改名称、预计投入与截止日期，再一次导入；备忘原文会保留。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
                Text(memos == savedMemos ? (memoStatus.isEmpty ? "转成任务时会保留这份备忘。" : memoStatus) : "备忘有未保存的修改")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            }
        }
        .onAppear { memos = model.data.taskMemos ?? ""; savedMemos = memos }
        .onChange(of: model.data.taskMemos) { _, value in
            let latest = value ?? ""
            if memos == savedMemos { memos = latest }
            savedMemos = latest
        }
        .onChange(of: memos) { _, value in
            if value != savedMemos, model.saveTaskMemos(value) { savedMemos = value; memoStatus = "备忘已自动保存。" }
        }
        .sheet(item: $editingTask) { task in FocusTaskEditor(model: model, task: task) }
        .sheet(isPresented: $showingImport) { FocusTaskImportView(model: model) }
        .sheet(isPresented: $showingMemoExtraction) { FocusMemoExtractionView(model: model) }
    }
    private func taskRow(_ task: FocusTask) -> some View {
        let summary = summaries.first { $0.taskID == task.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Button {
                    var changed = task
                    changed.isCompleted.toggle()
                    taskError = model.saveFocusTask(changed) ? nil : (model.matchingError ?? model.error ?? "任务未保存，请重试。")
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(PetTheme.accent)
                }.buttonStyle(.plain).help(task.isCompleted ? "标记为未完成" : "标记为完成")
                Button { editingTask = task } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.callout.weight(.semibold)).strikethrough(task.isCompleted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if task.isCompleted {
                            Text(task.completedAt.map { "完成于 \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "完成时间未记录（旧任务）")
                                .font(.caption).foregroundStyle(PetTheme.muted)
                        }
                        if let due = task.dueDate {
                            Label("\(task.isOverdue() ? "已过期 · " : "截止 ")\(due.formatted(date: .abbreviated, time: task.dueHasTime ? .shortened : .omitted))", systemImage: "calendar")
                                .font(.caption).foregroundStyle(task.isOverdue() ? Color.red : PetTheme.muted)
                        }
                        Text("已投入 \(summary?.completedPomodoros ?? 0)\(task.estimatedPomodoros.map { " / 预计 \($0) 颗" } ?? " 颗") · \(summary?.minutes ?? 0) 分钟")
                            .font(.caption).foregroundStyle(PetTheme.muted)
                        if !task.notes.isEmpty { Text(task.notes).font(.caption).foregroundStyle(PetTheme.muted).lineLimit(2) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                if selectedSessionCount > 0 {
                    Button("关联 \(selectedSessionCount) 条") { assignSelection(task.id) }
                        .buttonStyle(PetButtonStyle(primary: true))
                } else if !task.isCompleted {
                    Button(model.data.currentTaskID == task.id ? "已设为当前" : "设为当前") {
                        taskError = model.selectFocusTask(task.id) ? nil : (model.matchingError ?? model.error ?? "任务选择未保存，请重试。")
                    }
                        .disabled(model.data.currentTaskID == task.id || task.isCompleted)
                }
                Spacer()
                if task.isCompleted {
                    Button(expandedHistory.contains(task.id) ? "收起历史" : "查看历史") {
                        if expandedHistory.contains(task.id) { expandedHistory.remove(task.id) }
                        else { expandedHistory.insert(task.id) }
                    }
                }
                Button { editingTask = task } label: { Image(systemName: "pencil") }.help("编辑任务")
            }
            if task.isCompleted, expandedHistory.contains(task.id) {
                FocusTaskHistoryDetail(model: model, task: task, onSelectJournalDay: onSelectJournalDay)
            }
        }.padding(12).background(PetTheme.surface, in: RoundedRectangle(cornerRadius: 9))
    }
    private func saveMemos() {
        if model.saveTaskMemos(memos) { savedMemos = memos; memoStatus = "备忘已保存。" }
    }
    @ViewBuilder private var memoButtons: some View {
        Button("保存备忘") { saveMemos() }.disabled(memos == savedMemos)
        Button("转成任务…") {
            editingTask = FocusTask(title: String(memos.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(in: .whitespaces), notes: memos)
        }.disabled(memos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("AI 提取任务…") {
            guard memos == savedMemos || model.saveTaskMemos(memos) else { return }
            savedMemos = memos
            model.requestMemoTaskExtraction(memos)
            showingMemoExtraction = true
        }.buttonStyle(PetButtonStyle(primary: true))
            .disabled(memos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.data.settings.provider == "offline")
    }
}

@MainActor struct FocusTaskHistoryDetail: View {
    @ObservedObject var model: AppModel
    var task: FocusTask
    var onSelectJournalDay: ((String) -> Void)? = nil
    @State private var saveError: String?
    private struct HistoryRecord: Identifiable {
        var day: String
        var session: FocusSession
        var id: String { session.id }
    }
    private var records: [HistoryRecord] {
        var result: [HistoryRecord] = []
        for day in model.data.journal {
            for session in day.sessions where session.taskID == task.id {
                let isConversion = session.actualMinutes == 0 && session.completedPomodoro == false && !session.isPartial
                if !isConversion { result.append(HistoryRecord(day: day.date, session: session)) }
            }
        }
        result.sort { lhs, rhs in
            if lhs.session.startedAt == rhs.session.startedAt { return lhs.id < rhs.id }
            return lhs.session.startedAt < rhs.session.startedAt
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text("创建于 \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(PetTheme.muted)
            if !task.notes.isEmpty {
                Text(task.notes).font(.caption).textSelection(.enabled)
            }
            if let source = task.sourceExcerpt, !source.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("来自备忘原文").font(.caption.weight(.semibold))
                    Text(source).font(.caption).foregroundStyle(PetTheme.muted).textSelection(.enabled)
                }
            }
            HStack {
                Text("专注历史 · \(records.count) 条").font(.caption.weight(.semibold))
                Spacer()
                Button("重新打开任务") {
                    var reopened = task; reopened.isCompleted = false
                    saveError = model.saveFocusTask(reopened) ? nil : (model.matchingError ?? model.error ?? "任务未保存，请重试。")
                }.font(.caption)
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            if records.isEmpty {
                Text("尚无关联的专注明细；完成状态与原有计划仍已保留。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    if let onSelectJournalDay {
                                        Button(record.day) { onSelectJournalDay(record.day) }.font(.caption)
                                    } else { Text(record.day).font(.caption) }
                                    Text("\(record.session.startedAt.formatted(date: .omitted, time: .shortened))–\(record.session.completedAt.formatted(date: .omitted, time: .shortened)) · \(record.session.taskMinutes) 分钟")
                                        .font(.caption).monospacedDigit()
                                    Spacer(minLength: 0)
                                }
                                Text(historySource(record.session)).font(.caption2).foregroundStyle(PetTheme.muted)
                                if !record.session.notes.isEmpty {
                                    Text(record.session.notes).font(.caption).foregroundStyle(PetTheme.muted).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(maxHeight: 240)
            }
        }
    }
    private func historySource(_ session: FocusSession) -> String {
        let kind = session.isPartial ? "中途结束" : (session.isCompletedPomodoro ? "完整番茄" : "专注明细")
        let assignment: String
        switch session.assignmentSource {
        case "ai": assignment = "AI 关联"
        case "keyword": assignment = "Notes 匹配"
        case "manual": assignment = "手动关联"
        case "current": assignment = "专注时关联"
        default: assignment = "历史关联"
        }
        return "\(kind) · \(assignment)"
    }
}

@MainActor private struct FocusTaskEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var task: FocusTask
    @State private var hasEstimate: Bool
    @State private var estimate: Int
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var dueHasTime: Bool
    @State private var showingDelete = false
    @State private var saveError: String?
    private var exists: Bool { (model.data.tasks ?? []).contains { $0.id == task.id } }
    private var savedAsCompleted: Bool { (model.data.tasks ?? []).first { $0.id == task.id }?.isCompleted == true }
    init(model: AppModel, task: FocusTask) {
        self.model = model
        _task = State(initialValue: task)
        _hasEstimate = State(initialValue: task.estimatedPomodoros != nil)
        _estimate = State(initialValue: task.estimatedPomodoros ?? 1)
        _hasDue = State(initialValue: task.dueDate != nil)
        _due = State(initialValue: task.dueDate ?? Date())
        _dueHasTime = State(initialValue: task.dueHasTime)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PetHeading(title: exists ? "编辑任务" : "新增任务", subtitle: "预计投入与实际完成独立，截止日期可以留空。")
            TextField("任务名称", text: $task.title)
            Toggle("任务已完成", isOn: $task.isCompleted)
            HStack {
                Toggle("预计番茄数", isOn: $hasEstimate)
                if hasEstimate { IntegerField(title: "个", value: $estimate, range: 0...9999).frame(width: 85); Text("个").foregroundStyle(PetTheme.muted) }
            }
            Toggle("设置截止日期", isOn: $hasDue)
            if hasDue {
                DatePicker("截止日期", selection: $due, displayedComponents: dueHasTime ? [.date, .hourAndMinute] : [.date])
                Toggle("包括具体时间", isOn: $dueHasTime)
                Text("截止日期按实际日历判断，不受 21:00 记录换日影响。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            }
            Text("说明与链接").font(.headline)
            NotesEditor(text: $task.notes).frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            HStack {
                if exists {
                    Button("删除任务") { showingDelete = true }.disabled(savedAsCompleted)
                        .help(savedAsCompleted ? "完成历史会保留；需要删除时先重新打开并保存任务。" : "已关联专注记录的任务会保留历史。")
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    task.estimatedPomodoros = hasEstimate ? estimate : nil
                    task.dueDate = hasDue ? due : nil
                    task.dueHasTime = hasDue && dueHasTime
                    if model.saveFocusTask(task) { dismiss() }
                    else { saveError = model.matchingError ?? model.error ?? "任务未保存，请重试。" }
                }.buttonStyle(PetButtonStyle(primary: true))
                    .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 480).petPage()
            .alert("删除这个任务？", isPresented: $showingDelete) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if model.deleteFocusTask(task.id) { dismiss() }
                    else { saveError = model.matchingError ?? model.error ?? "任务未删除，请重试。" }
                }
            } message: { Text("已关联专注记录的任务请标记完成，保留历史归属。") }
    }
}

@MainActor struct FocusMemoExtractionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var proposals: [FocusMemoTaskProposal] = []
    @State private var selected: Set<String> = []
    @State private var editingProposal: FocusMemoTaskProposal?
    @State private var showOriginal = false
    private var planIsStale: Bool {
        guard let plan = model.memoExtractionPlan else { return false }
        return plan.sourceText != (model.data.taskMemos ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PetHeading(title: "备忘转成任务", subtitle: "选择需要执行的条目，修改后整批导入；原文继续保留。")
            HStack(spacing: 10) {
                if model.memoExtractionBusy {
                    ProgressView().controlSize(.small)
                    Text("AI 正在整理这份备忘…").font(.callout)
                    Spacer()
                    Button("取消整理") { model.cancelMemoTaskExtraction() }
                } else {
                    Text("使用设置中的 AI 服务，只整理明确可执行的内容。")
                        .font(.caption).foregroundStyle(PetTheme.muted)
                    Spacer()
                    Button("重新整理") { model.requestMemoTaskExtraction(model.data.taskMemos ?? "") }
                        .disabled(model.busy || model.data.settings.provider == "offline")
                }
            }
            if let error = model.memoExtractionError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let plan = model.memoExtractionPlan {
                DisclosureGroup("查看备忘原文", isExpanded: $showOriginal) {
                    ScrollView {
                        Text(plan.sourceText).font(.caption).foregroundStyle(PetTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(maxHeight: 110).padding(.top, 5)
                }.font(.caption)
                if planIsStale {
                    Text("备忘在预览后已有修改，请重新整理。")
                        .font(.caption).foregroundStyle(.red)
                }
                if proposals.isEmpty {
                    Text("没有识别到明确可执行的任务。想法、链接和日常记录仍保留在备忘里。")
                        .font(.callout).foregroundStyle(PetTheme.muted).padding(.vertical, 18)
                } else {
                    HStack {
                        Text("候选任务 · \(proposals.count) 项").font(.headline)
                        Spacer()
                        Button(selected == selectableIDs ? "取消全选" : "全选可导入项") {
                            selected = selected == selectableIDs ? [] : selectableIDs
                        }.font(.caption)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(proposals) { proposal in proposalRow(proposal) }
                        }
                    }.frame(minHeight: 180, maxHeight: 340)
                    Text("原文中未明确写出的预计番茄数或日期会留空；这里也可以自行补充。")
                        .font(.caption).foregroundStyle(PetTheme.muted)
                }
            } else if !model.memoExtractionBusy {
                Text("整理不会改动备忘；生成候选后，你可以选择并编辑要导入的任务。")
                    .font(.callout).foregroundStyle(PetTheme.muted).padding(.vertical, 18)
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                Button("导入 \(selected.count) 项") {
                    if model.applyMemoTaskExtraction(proposals, selectedIDs: selected) { dismiss() }
                }.buttonStyle(PetButtonStyle(primary: true))
                    .disabled(model.memoExtractionBusy || selected.isEmpty || planIsStale || model.memoExtractionPlan == nil)
            }
        }.padding(26).frame(width: 600).petPage()
            .onAppear { loadPlan() }
            .onChange(of: model.memoExtractionPlan) { _, _ in loadPlan() }
            .onDisappear { if model.memoExtractionBusy { model.cancelMemoTaskExtraction() } }
            .sheet(item: $editingProposal) { proposal in
                FocusMemoProposalEditor(proposal: proposal) { updated in
                    if let index = proposals.firstIndex(where: { $0.id == updated.id }) { proposals[index] = updated }
                }
            }
    }
    private func loadPlan() {
        proposals = model.memoExtractionPlan?.proposals ?? []
        selected = selectableIDs
    }
    private var selectableIDs: Set<String> {
        var titles = Set((model.data.tasks ?? []).map { FocusMemoExtraction.normalizedTitle($0.title) })
        return Set(proposals.compactMap { titles.insert(FocusMemoExtraction.normalizedTitle($0.title)).inserted ? $0.id : nil })
    }
    private func hasExistingTitle(_ title: String) -> Bool {
        (model.data.tasks ?? []).contains { FocusMemoExtraction.normalizedTitle($0.title) == FocusMemoExtraction.normalizedTitle(title) }
    }
    private func proposalRow(_ proposal: FocusMemoTaskProposal) -> some View {
        let duplicate = hasExistingTitle(proposal.title)
        let batchDuplicate = proposals.first { FocusMemoExtraction.normalizedTitle($0.title) == FocusMemoExtraction.normalizedTitle(proposal.title) }?.id != proposal.id
        return HStack(alignment: .top, spacing: 10) {
            Toggle("导入这项", isOn: Binding(get: { selected.contains(proposal.id) }, set: {
                if $0 { selected.insert(proposal.id) } else { selected.remove(proposal.id) }
            })).labelsHidden()
            VStack(alignment: .leading, spacing: 5) {
                Text(proposal.title).font(.callout.weight(.semibold))
                if let estimate = proposal.estimatedPomodoros {
                    Text("预计 \(estimate) 个番茄").font(.caption).foregroundStyle(PetTheme.muted)
                }
                if let due = proposal.dueDate {
                    Text("截止 \(due.formatted(date: .abbreviated, time: proposal.dueHasTime ? .shortened : .omitted))")
                        .font(.caption).foregroundStyle(PetTheme.muted)
                }
                if !proposal.notes.isEmpty { Text(proposal.notes).font(.caption).foregroundStyle(PetTheme.muted).lineLimit(2) }
                Text("原文：\(proposal.sourceExcerpt)").font(.caption).foregroundStyle(PetTheme.muted).lineLimit(3).textSelection(.enabled)
                if duplicate { Text("已有同名任务，请取消勾选或修改名称后导入。")
                    .font(.caption).foregroundStyle(PetTheme.accent) }
                else if batchDuplicate { Text("本批已有同名任务，请取消勾选或修改名称后导入。")
                    .font(.caption).foregroundStyle(PetTheme.accent) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("编辑") { editingProposal = proposal }.font(.caption)
        }.padding(12).background(PetTheme.surface, in: RoundedRectangle(cornerRadius: 9))
    }
}

@MainActor private struct FocusMemoProposalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var proposal: FocusMemoTaskProposal
    @State private var hasEstimate: Bool
    @State private var estimate: Int
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var dueHasTime: Bool
    var save: (FocusMemoTaskProposal) -> Void
    init(proposal: FocusMemoTaskProposal, save: @escaping (FocusMemoTaskProposal) -> Void) {
        _proposal = State(initialValue: proposal)
        _hasEstimate = State(initialValue: proposal.estimatedPomodoros != nil)
        _estimate = State(initialValue: proposal.estimatedPomodoros ?? 1)
        _hasDue = State(initialValue: proposal.dueDate != nil)
        _due = State(initialValue: proposal.dueDate ?? Date())
        _dueHasTime = State(initialValue: proposal.dueHasTime)
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PetHeading(title: "编辑候选任务", subtitle: "确认名称、预计投入与截止日期后再导入。")
            TextField("任务名称", text: $proposal.title)
            HStack {
                Toggle("预计番茄数", isOn: $hasEstimate)
                if hasEstimate { IntegerField(title: "个", value: $estimate, range: 0...9999).frame(width: 85); Text("个").foregroundStyle(PetTheme.muted) }
            }
            Toggle("设置截止日期", isOn: $hasDue)
            if hasDue {
                DatePicker("截止日期", selection: $due, displayedComponents: dueHasTime ? [.date, .hourAndMinute] : [.date])
                Toggle("包括具体时间", isOn: $dueHasTime)
            }
            Text("任务说明").font(.headline)
            NotesEditor(text: $proposal.notes).frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
            Text("备忘原文").font(.caption.weight(.semibold))
            ScrollView { Text(proposal.sourceExcerpt).font(.caption).foregroundStyle(PetTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 90)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存候选") {
                    proposal.title = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    proposal.estimatedPomodoros = hasEstimate ? estimate : nil
                    proposal.dueDate = hasDue ? due : nil
                    proposal.dueHasTime = hasDue && dueHasTime
                    save(proposal); dismiss()
                }.buttonStyle(PetButtonStyle(primary: true))
                    .disabled(proposal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 490).petPage()
    }
}

@MainActor struct FocusMatchingCard: View {
    @ObservedObject var model: AppModel
    var sessions: [FocusSession]
    var selectionOnly: Bool
    var prepare: () -> Bool
    @State private var instruction = ""
    @State private var expanded = false
    private var tasks: [FocusTask] { model.data.tasks ?? [] }
    private var unavailable: Bool { sessions.isEmpty || tasks.isEmpty }
    private var staleReason: String? {
        guard let plan = model.matchingPlan, !plan.changes.isEmpty else { return nil }
        for change in plan.changes {
            guard let current = sessions.first(where: { $0.id == change.sessionID }) else { return "部分记录已经删除或不属于当前记录日，请重新生成预览。" }
            if let expected = change.expectedSession, expected != current { return FocusAssignmentError.staleSession.localizedDescription }
        }
        do { try model.data.validateAssignments(plan); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        PetCard {
            DisclosureGroup(isExpanded: $expanded) {
                matchingContent.padding(.top, 10)
            } label: {
                HStack {
                    Label("一句话整理与匹配建议", systemImage: "wand.and.stars").font(.title3.bold())
                    Spacer()
                    Text("\(selectionOnly ? "已选" : "当天") \(sessions.count) 条").font(.caption).foregroundStyle(PetTheme.muted)
                    if model.matchingBusy { ProgressView().controlSize(.small) }
                }
            }
        }
    }
    private var matchingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("范围：\(selectionOnly ? "已选的" : "当前记录日的") \(sessions.count) 条专注明细。")
                    .font(.callout.weight(.semibold))
                Spacer()
                if model.matchingBusy { ProgressView().controlSize(.small); Button("取消") { model.cancelFocusMatch() } }
            }
            Text("一句话说明这些时间做了什么，AI 会找出对应记录；先预览，再一次应用。建议功能只处理范围内未关联的记录。")
                .font(.caption).foregroundStyle(PetTheme.muted)
            NotesEditor(text: $instruction).frame(height: 65)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
            ViewThatFits(in: .horizontal) {
                HStack { matchingButtons }
                VStack(alignment: .leading) { matchingButtons }
            }
            Text(model.data.settings.provider == "offline" ? "离线模式可根据 Notes 中明确出现的任务名生成本地建议；一句话匹配需先在设置中启用 AI。" : "AI 使用设置中的服务，发送范围内记录的时间及 Notes、任务名称与说明。明确任务名也可用本地建议。")
                .font(.caption).foregroundStyle(PetTheme.muted)
            if let error = model.matchingError { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if let plan = model.matchingPlan {
                Divider()
                HStack {
                    Text("匹配预览 · \(plan.changes.count) 条").font(.headline)
                    Spacer()
                    Button("清除") { model.clearFocusMatch() }
                    Button("应用整批匹配") { if prepare() { _ = model.applyFocusMatch() } }
                        .buttonStyle(PetButtonStyle(primary: true))
                        .disabled(model.matchingBusy || plan.changes.isEmpty || staleReason != nil)
                }
                if plan.changes.isEmpty {
                    Text("没有可应用的匹配。补充具体时间段、任务名或 Notes 后再试。")
                        .font(.callout).foregroundStyle(PetTheme.muted)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(plan.changes.enumerated()), id: \.offset) { _, change in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(timeLabel(change.sessionID)) · \(title(change.expectedTaskID)) → \(title(change.targetTaskID))")
                                        .font(.callout.weight(.semibold))
                                    if !change.reason.isEmpty { Text(change.reason).font(.caption).foregroundStyle(PetTheme.muted) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: 190)
                    Text("只修改任务归属；分钟、目标和 Notes 会保留。应用后可整批撤销。")
                        .font(.caption).foregroundStyle(PetTheme.muted)
                    if let staleReason { Text(staleReason).font(.caption).foregroundStyle(.red) }
                }
            }
        }
    }
    @ViewBuilder private var matchingButtons: some View {
        Button("一句话匹配（AI）") {
            if prepare() { model.requestFocusMatch(instruction, sessions: liveSessions()) }
        }.buttonStyle(PetButtonStyle(primary: true))
            .disabled(unavailable || model.matchingBusy || model.busy || model.data.settings.provider == "offline" || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("根据 Notes 建议") {
            if prepare() { model.requestFocusSuggestions(sessions: liveSessions(), useAI: false) }
        }.disabled(unavailable || model.matchingBusy)
        Button("AI 建议未关联") {
            if prepare() { model.requestFocusSuggestions(sessions: liveSessions().filter { $0.taskID == nil }, useAI: true) }
        }.disabled(unavailable || model.matchingBusy || model.busy || model.data.settings.provider == "offline" || sessions.allSatisfy { $0.taskID != nil })
    }
    private func liveSessions() -> [FocusSession] {
        let ids = Set(sessions.map(\.id))
        return model.data.journal.flatMap(\.sessions).filter { ids.contains($0.id) }
    }
    private func title(_ id: String?) -> String {
        guard let id else { return "未关联" }
        return tasks.first { $0.id == id }?.title ?? "已删除任务"
    }
    private func timeLabel(_ id: String) -> String {
        guard let session = sessions.first(where: { $0.id == id }) else { return "记录已变化" }
        return session.completedAt.formatted(date: .omitted, time: .shortened)
    }
}

@MainActor private struct FocusTaskImportView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var candidates: [FocusTask] = []
    @State private var selected: Set<String> = []
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PetHeading(title: "粘贴清单", subtitle: "先识别候选任务，再选择要导入的条目。")
            NotesEditor(text: $text).frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
            HStack {
                Button("预览任务") {
                    candidates = FocusTaskImport.preview(text)
                    selected = Set(candidates.map(\.id))
                    status = candidates.isEmpty ? "没有识别到任务。可以每行写一个任务。" : "取消勾选备忘或重复内容，再导入。"
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("行尾番茄数仅作为候选估计，请在预览中确认。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            }
            Text(status).font(.caption).foregroundStyle(PetTheme.muted)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(candidates) { task in
                        Toggle(isOn: Binding(get: { selected.contains(task.id) }, set: { if $0 { selected.insert(task.id) } else { selected.remove(task.id) } })) {
                            Text(task.title + (task.estimatedPomodoros.map { " · 预计 \($0) 个" } ?? ""))
                        }
                    }
                }
            }.frame(height: 190)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("导入 \(selected.count) 项") {
                    var imported: Set<String> = []
                    for task in candidates where selected.contains(task.id) {
                        guard model.saveFocusTask(task) else { break }
                        imported.insert(task.id)
                    }
                    selected.subtract(imported)
                    candidates.removeAll { imported.contains($0.id) }
                    if selected.isEmpty { dismiss() }
                    else { status = "已导入 \(imported.count) 项，剩余任务未保存，请重试。" }
                }.buttonStyle(PetButtonStyle(primary: true)).disabled(selected.isEmpty)
            }
        }.padding(26).frame(width: 570).petPage()
            .onChange(of: text) { _, _ in candidates = []; selected = []; status = "" }
    }
}
