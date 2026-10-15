import SwiftUI

enum FocusAllocationPresentation {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func label(_ allocations: [FocusTaskAllocation], tasks: [FocusTask], includePercent: Bool = true,
                      totalMinutes: Double? = nil) -> String {
        guard !allocations.isEmpty else { return "未关联" }
        return allocations.map { allocation in
            let title = tasks.first { $0.id == allocation.taskID }?.title ?? "已删除任务"
            if let totalMinutes { return "\(title) \(number(allocation.share * totalMinutes)) 分钟" }
            return includePercent ? "\(title) \(number(allocation.share * 100))%" : title
        }.joined(separator: " · ")
    }
}

struct FocusAllocationDraft {
    let totalMinutes: Double
    private(set) var allocations: [FocusTaskAllocation]
    private(set) var minuteDrafts: [String: String] = [:]
    private(set) var hasChanges = false
    private var pendingTaskIDs: [String] = []

    init(allocations: [FocusTaskAllocation], totalMinutes: Double) {
        self.allocations = allocations; self.totalMinutes = totalMinutes
        refreshMinuteDrafts()
    }

    mutating func changeSelection(_ ids: [String]) {
        allocations = FocusTaskAllocationRules.equal(ids)
        pendingTaskIDs = []
        hasChanges = true
        refreshMinuteDrafts()
    }

    mutating func setMinutesText(_ text: String, taskID: String) {
        guard allocations.contains(where: { $0.taskID == taskID }) else { return }
        minuteDrafts[taskID] = text
        if !pendingTaskIDs.contains(taskID) { pendingTaskIDs.append(taskID) }
        hasChanges = true
    }

    mutating func commitMinutes(_ taskID: String) throws {
        guard let existing = allocations.first(where: { $0.taskID == taskID }) else { return }
        let text = (minuteDrafts[taskID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Merely focusing rounded text must preserve the exact equal split.
        if text != formattedMinutes(existing.share) {
            let minutes = try validatedMinutes(taskID)
            let remainder = allocations.filter { $0.taskID != taskID }.reduce(0) { $0 + $1.share }
            let share = minutes / totalMinutes
            let updated = allocations.map { allocation in
                FocusTaskAllocation(taskID: allocation.taskID,
                                    share: allocation.taskID == taskID ? share : allocation.share / remainder * (1 - share))
            }
            allocations = try FocusTaskAllocationRules.normalized(updated)
        }
        pendingTaskIDs.removeAll { $0 == taskID }
        refreshMinuteDrafts()
    }

    func preparedAllocations() throws -> [FocusTaskAllocation] {
        // Save also commits a still-focused field. Validate every pending field before
        // applying any edit so an invalid, previously blurred value cannot disappear.
        for id in pendingTaskIDs { _ = try validatedMinutes(id) }
        var prepared = self
        for id in pendingTaskIDs { try prepared.commitMinutes(id) }
        return try FocusTaskAllocationRules.normalized(prepared.allocations)
    }

    private func validatedMinutes(_ taskID: String) throws -> Double {
        let existing = allocations.first { $0.taskID == taskID }!.share
        let text = (minuteDrafts[taskID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text == formattedMinutes(existing) { return existing * totalMinutes }
        let value = Double(text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."))
        guard totalMinutes.isFinite, totalMinutes > 0, allocations.count > 1,
              let value, value.isFinite, value > 0, value < totalMinutes else {
            throw AppError.message("分钟须大于 0 且小于 \(FocusAllocationPresentation.number(totalMinutes))。")
        }
        return value
    }

    private func formattedMinutes(_ share: Double) -> String {
        (share * totalMinutes).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    private mutating func refreshMinuteDrafts() {
        let previous = minuteDrafts
        minuteDrafts = Dictionary(uniqueKeysWithValues: allocations.map {
            ($0.taskID, pendingTaskIDs.contains($0.taskID) ? previous[$0.taskID] ?? formattedMinutes($0.share) : formattedMinutes($0.share))
        })
    }
}

@MainActor struct FocusAllocationEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let tasks: [FocusTask]
    let totalMinutes: Double
    let minutesScope: String
    let failureMessage: (() -> String?)?
    let onSave: ([FocusTaskAllocation]) -> Bool
    @State private var draft: FocusAllocationDraft
    @State private var search = ""
    @State private var saveError: String?
    @FocusState private var focusedTaskID: String?

    init(title: String, tasks: [FocusTask], allocations: [FocusTaskAllocation], totalMinutes: Double,
         minutesScope: String = "共",
         failureMessage: (() -> String?)? = nil,
         onSave: @escaping ([FocusTaskAllocation]) -> Bool) {
        self.title = title; self.tasks = tasks; self.failureMessage = failureMessage; self.onSave = onSave
        self.totalMinutes = totalMinutes
        self.minutesScope = minutesScope
        _draft = State(initialValue: FocusAllocationDraft(allocations: allocations, totalMinutes: totalMinutes))
    }

    private var allocations: [FocusTaskAllocation] { draft.allocations }

    private var visibleTasks: [FocusTask] {
        tasks.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                return $0.createdAt < $1.createdAt
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Text("已选 \(allocations.count)").font(.callout).foregroundStyle(PetTheme.muted)
            }
            HStack(spacing: 10) {
                TextField("搜索任务", text: $search)
                Button("均分") { equalize() }.disabled(allocations.count < 2)
                Button("清空") { changeSelection([]) }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                        if task.id != visibleTasks.last?.id { Divider() }
                    }
                    if visibleTasks.isEmpty {
                        Text(search.isEmpty ? "暂无任务" : "未找到任务")
                            .font(.callout).foregroundStyle(PetTheme.muted).padding(.vertical, 24)
                    }
                }.padding(.horizontal, 10)
            }.frame(height: 300)
                .background(PetTheme.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(PetTheme.border))
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
            HStack {
                if !allocations.isEmpty {
                    Text("\(minutesScope) \(FocusAllocationPresentation.number(totalMinutes)) 分钟").font(.callout.weight(.semibold)).monospacedDigit()
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }.buttonStyle(PetButtonStyle(primary: true)).disabled(!draft.hasChanges)
            }
        }.padding(24).frame(width: 520).petPage()
            .onChange(of: focusedTaskID) { old, _ in
                if let old { _ = commitMinutes(old) }
            }
    }

    private func taskRow(_ task: FocusTask) -> some View {
        let isSelected = allocations.contains { $0.taskID == task.id }
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: { selected in
                var ids = allocations.map(\.taskID)
                if selected { ids.append(task.id) } else { ids.removeAll { $0 == task.id } }
                changeSelection(ids)
            })) {
                Text(task.title).font(.callout).lineLimit(1).help(task.title)
                    .strikethrough(task.isCompleted)
            }.toggleStyle(.checkbox)
            Spacer(minLength: 4)
            if isSelected {
                TextField("分钟", text: Binding(get: { draft.minuteDrafts[task.id] ?? "" }, set: {
                    draft.setMinutesText($0, taskID: task.id)
                }))
                    .multilineTextAlignment(.trailing).monospacedDigit().frame(width: 72)
                    .focused($focusedTaskID, equals: task.id)
                    .onSubmit { _ = commitMinutes(task.id) }
                    .disabled(allocations.count == 1 || totalMinutes <= 0)
                    .accessibilityLabel("\(task.title) 分钟")
                    .help("修改分钟后，其余任务按原比例分配剩余时间。")
                Text("分钟").font(.callout).foregroundStyle(PetTheme.muted)
            }
        }.frame(minHeight: 38)
    }

    private func changeSelection(_ ids: [String]) {
        focusedTaskID = nil
        draft.changeSelection(ids)
        saveError = nil
    }

    private func equalize() { changeSelection(allocations.map(\.taskID)) }

    @discardableResult private func commitMinutes(_ taskID: String) -> Bool {
        do {
            try draft.commitMinutes(taskID)
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func save() {
        do {
            let normalized = try draft.preparedAllocations()
            if onSave(normalized) { dismiss() }
            else { saveError = failureMessage?() ?? "关联未保存，请重试。" }
        } catch { saveError = error.localizedDescription }
    }
}
