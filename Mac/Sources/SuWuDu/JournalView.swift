import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum JournalExport {
    static func markdown(_ days: [JournalDay], tasks: [FocusTask] = []) -> String {
        days.sorted { $0.date < $1.date }.map { day in
            var text = "## \(day.date)\n\n完成：\(day.count) / \(day.target) 个番茄钟\n总计：\(day.total) 分钟\n分钟调整：\(day.adjustment)\n"
            if !day.notes.isEmpty { text += "\n### Notes\n\n\(day.notes)\n" }
            for session in day.sessions {
                let source = session.isPartial ? "提前结束" : session.actualMinutes == 0 ? "分钟换算" : session.source == "automatic" ? "自动" : "手动"
                let task = FocusAllocationPresentation.label(session.allocations, tasks: tasks,
                    totalMinutes: Double(session.taskMinutes))
                text += "\n- \(session.completedAt.formatted(date: .omitted, time: .shortened)) · \(session.minutes) 分钟 · \(source)\(session.countsTowardGoal ? "" : " · 不计入目标") · 任务：\(task)"
                if !session.notes.isEmpty { text += "\n  " + session.notes.replacingOccurrences(of: "\n", with: "\n  ") }
            }
            return text + "\n"
        }.joined(separator: "\n")
    }
}

// Keep edits local until Save, navigation, export, or closing the window.
// Automatic focus sessions arriving during editing are merged, never overwritten.
@MainActor final class JournalEditor: ObservableObject {
    @Published var date = FocusAccounting.date(from: FocusAccounting.key(Date())) ?? Date()
    @Published private(set) var draft: JournalDay?
    private var baseline: JournalDay?
    let model: AppModel
    init(model: AppModel) { self.model = model }
    var dateKey: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    var day: JournalDay { draft ?? model.data.journalDay(dateKey) }
    func edit(_ updated: JournalDay) {
        if baseline == nil { baseline = day }
        draft = updated
    }
    @discardableResult func adjustMinutes(by delta: Int) -> Bool {
        guard delta != 0 else { return false }
        var updated = day
        let (adjustment, overflow) = updated.adjustment.addingReportingOverflow(delta)
        guard !overflow, (-10_000...10_000).contains(adjustment) else {
            model.error = "调整后的分钟数须在 -10000 至 10000 之间，本次增减未应用。"
            return false
        }
        updated.adjustment = adjustment
        edit(updated)
        return true
    }
    @discardableResult func save() -> Bool {
        guard var value = draft, let baseline else { return true }
        let latest = model.data.journalDay(value.date)
        if value.target == baseline.target { value.target = latest.target }
        if value.notes == baseline.notes { value.notes = latest.notes }
        // Three-way merge: only fields explicitly changed in the editor win.
        value.sessions = value.sessions.compactMap { edited in
            guard let original = baseline.sessions.first(where: { $0.id == edited.id }) else { return edited }
            guard var live = latest.sessions.first(where: { $0.id == edited.id }) else { return nil }
            if edited.minutes != original.minutes { live.minutes = edited.minutes }
            if edited.notes != original.notes { live.notes = edited.notes }
            if edited.countsTowardGoal != original.countsTowardGoal { live.countsTowardGoal = edited.countsTowardGoal }
            if !FocusTaskAllocationRules.same(edited.allocations, original.allocations) {
                live.allocations = edited.allocations
                live.assignmentSource = edited.assignmentSource
                live.assignmentRevision = edited.assignmentRevision
            }
            return live
        }
        let known = Set(baseline.sessions.map(\.id) + value.sessions.map(\.id))
        value.sessions += latest.sessions.filter { !known.contains($0.id) }
        value.adjustment += latest.adjustment - baseline.adjustment
        guard model.saveDay(value) else { return false }
        draft = nil
        self.baseline = nil
        return true
    }
    func navigate(_ newDate: Date) { if save() { date = newDate } }
}

@MainActor struct JournalView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: JournalEditor
    @State private var expanded: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var selectionAnchor: String?
    @State private var recordsByTask = false
    @State private var showAdjustments = false
    @State private var minutesToAdd = 0
    @State private var minutesToSubtract = 0
    @State private var showingExport = false
    @State private var showingTargets = false
    @State private var allocationEdit: AllocationEdit?
    @State private var status = ""
    @State private var exportFrom = Date()
    @State private var exportTo = Date()
    private var date: Date { editor.date }
    private var dateKey: String { editor.dateKey }
    private var day: JournalDay { editor.day }
    private var tasks: [FocusTask] { model.data.tasks ?? [] }
    private var matchingSessions: [FocusSession] {
        day.sessions.filter { selectable($0) && (selected.isEmpty || selected.contains($0.id)) }
    }
    private var orderedSessions: [FocusSession] {
        day.sessions.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
    }
    private struct AllocationEdit: Identifiable {
        var id = UUID()
        var sessions: [FocusSession]
        var initial: [FocusTaskAllocation]
        var sameDuration: Bool { sessions.allSatisfy { $0.taskMinutes == sessions.first?.taskMinutes } }
        var totalMinutes: Double {
            sameDuration ? Double(sessions.first?.taskMinutes ?? 0) : sessions.reduce(0) { $0 + Double($1.taskMinutes) }
        }
        var minutesScope: String { sessions.count == 1 ? "共" : sameDuration ? "每条" : "合计" }
    }
    private struct RecordGroup: Identifiable {
        var taskID: String?
        var sessions: [FocusSession]
        var id: String { taskID.map { "task:" + $0 } ?? "unassigned" }
    }
    private var recordGroups: [RecordGroup] {
        let ids = Set(orderedSessions.flatMap { $0.allocations.map(\.taskID) }).sorted {
            let left = taskTitle($0), right = taskTitle($1)
            return left == right ? $0 < $1 : left.localizedStandardCompare(right) == .orderedAscending
        }
        var groups = ids.map { id in
            RecordGroup(taskID: id, sessions: orderedSessions.filter { $0.allocations.contains { $0.taskID == id } })
        }
        let unassigned = orderedSessions.filter { $0.allocations.isEmpty }
        if !unassigned.isEmpty { groups.append(RecordGroup(taskID: nil, sessions: unassigned)) }
        return groups
    }
    private func binding<T>(_ key: WritableKeyPath<JournalDay, T>) -> Binding<T> {
        Binding(get: { day[keyPath: key] }, set: { value in var updated = day; updated[keyPath: key] = value; editor.edit(updated) })
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FocusTaskTimerBar(model: model)
            Divider()
            GeometryReader { geometry in
                if geometry.size.width >= 1000 {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { taskList.padding(20) }.frame(width: 350)
                        Divider()
                        ScrollView { recordPanel.padding(20) }.frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) { taskList; recordPanel }.padding(20)
                    }
                }
            }
            Divider()
            footer
        }.frame(minWidth: 760, minHeight: 650).petPage()
            .onChange(of: dateKey) { _, _ in
                minutesToAdd = 0; minutesToSubtract = 0
                status = ""
                selected = []; selectionAnchor = nil; expanded = []
                model.cancelFocusMatch(); model.clearFocusMatch()
            }
            .onChange(of: day.sessions.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .onChange(of: selected) { _, _ in model.clearFocusMatch() }
            .onChange(of: recordsByTask) { _, _ in selectionAnchor = nil }
            .sheet(isPresented: $showingTargets) { TargetScheduleView(model: model, initialDate: date) }
            .sheet(isPresented: $showingExport) { exportSheet }
            .sheet(item: $allocationEdit) { request in
                FocusAllocationEditor(title: request.sessions.count == 1 ? "分配任务" : "分配 \(request.sessions.count) 条记录",
                    tasks: tasks, allocations: request.initial, totalMinutes: request.totalMinutes, minutesScope: request.minutesScope,
                    failureMessage: { model.matchingError ?? model.error }) { allocations in
                    guard model.assignFocusSessions(request.sessions, allocations: allocations) else { return false }
                    status = "已更新 · \(request.sessions.count) 条"
                    selected = []; selectionAnchor = nil
                    return true
                }
                .help("批量分配时，每条记录按相同的时间比例分配给所选任务。")
            }
    }
    private var header: some View {
        HStack {
            Text("任务与专注").font(.system(size: 24, weight: .bold))
            Spacer()
            Button { moveDay(-1) } label: { Image(systemName: "chevron.left") }.help("前一天")
            DatePicker("记录日", selection: Binding(get: { date }, set: { editor.navigate($0) }), displayedComponents: .date)
                .labelsHidden().frame(width: 120).help("每晚 21:00 切换记录日")
            Button { moveDay(1) } label: { Image(systemName: "chevron.right") }.help("后一天")
            Button("今天") { editor.navigate(FocusAccounting.date(from: FocusAccounting.key(Date())) ?? Date()) }
        }.padding(22).background(PetTheme.card)
    }
    private var taskList: some View {
        FocusTasksView(model: model, selectedSessionCount: selected.count, assignSelection: assignSelection,
                       onSelectJournalDay: { key in
            if let date = FocusAccounting.date(from: key) { editor.navigate(date) }
        })
    }
    private var recordPanel: some View {
        VStack(spacing: 16) {
            dailySummary
            FocusMatchingCard(model: model, sessions: matchingSessions, selectionOnly: !selected.isEmpty, prepare: { editor.save() })
            sessionsCard
            PetCard("当天 Notes") {
                NotesEditor(text: binding(\.notes)).frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
            }
        }
    }
    private var dailySummary: some View {
        PetCard {
            HStack {
                summary("完成 / 目标", "\(day.count) / \(day.target)")
                summary("番茄钟时间", "\(day.sessions.filter(\.countsTowardGoal).reduce(0) { $0 + $1.minutes }) 分钟")
                summary("最终计入", "\(day.total) 分钟")
            }
            ProgressView(value: day.target > 0 ? min(1, Double(day.count) / Double(day.target)) : 0)
            DisclosureGroup("目标与分钟调整", isExpanded: $showAdjustments) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading) {
                            Text("目标（个）").font(.headline)
                            IntegerField(title: "0–999", value: binding(\.target), range: 0...999)
                        }
                        VStack(alignment: .leading) {
                            Text("分钟调整").font(.headline)
                            IntegerField(title: "分钟", value: binding(\.adjustment), range: -10_000...10_000)
                                .help("可填正数或负数，按原有规则折算当天目标。")
                        }
                    }
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("增加分钟").font(.headline)
                            HStack {
                                IntegerField(title: "分钟", value: $minutesToAdd, range: 0...10_000)
                                Button("增加") { applyMinuteChange(subtract: false) }.disabled(minutesToAdd == 0)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("减少分钟").font(.headline)
                            HStack {
                                IntegerField(title: "分钟", value: $minutesToSubtract, range: 0...10_000)
                                Button("减少") { applyMinuteChange(subtract: true) }.disabled(minutesToSubtract == 0)
                            }
                        }
                    }
                    Button("批量设置番茄钟目标") { if editor.save() { showingTargets = true } }
                }.padding(.top, 12)
            }.font(.callout.weight(.semibold))
        }
    }
    private var sessionsCard: some View {
        PetCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("番茄钟记录").font(.title3.bold())
                    Text("\(day.sessions.count) 条").font(.caption).foregroundStyle(PetTheme.muted)
                    Spacer()
                    Button("＋ 补记", action: addSession).help("补记一个番茄钟")
                }
                HStack {
                    Picker("排列方式", selection: $recordsByTask) {
                        Text("按时间").tag(false)
                        Text("按任务").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    Spacer()
                    Button("选未关联") { selected = Set(day.sessions.filter { $0.allocations.isEmpty && selectable($0) }.map(\.id)); selectionAnchor = nil }
                        .disabled(day.sessions.allSatisfy { !$0.allocations.isEmpty || !selectable($0) })
                    Button("全选") { selected = Set(day.sessions.filter(selectable).map(\.id)); selectionAnchor = nil }
                        .disabled(day.sessions.allSatisfy { !selectable($0) })
                    if model.canUndoFocusAssignments {
                        Button("撤销") { if editor.save(), model.undoFocusAssignments() { status = "已撤销" } }
                            .help("撤销最近一批任务匹配")
                    }
                }
                if !selected.isEmpty {
                    HStack(spacing: 8) {
                        Text("已选 \(selected.count) 条").font(.caption.weight(.semibold))
                        Button("关联任务…") { editAllocations(day.sessions.filter { selected.contains($0.id) }) }
                            .help("为所选记录选择多个任务并分配用时。")
                        Spacer()
                        Button("取消选择") { selected = []; selectionAnchor = nil }
                    }
                }
                if day.sessions.isEmpty {
                    Text("暂无记录").foregroundStyle(PetTheme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                if !day.sessions.isEmpty {
                    VStack(spacing: 0) {
                        sessionTableHeader
                        if recordsByTask {
                            ForEach(recordGroups) { group in
                                taskGroupHeading(group)
                                ForEach(group.sessions) { session in
                                    sessionRow(session, groupID: group.id)
                                    Divider()
                                }
                            }
                        } else {
                            ForEach(orderedSessions) { session in
                                sessionRow(session)
                                Divider()
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PetTheme.border))
                }
            }
        }
    }
    private var sessionTableHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 20, height: 1)
            HStack(spacing: 8) {
                Text("时间").frame(width: 96, alignment: .leading)
                Text("分钟").frame(width: 42, alignment: .trailing)
                Text("任务 · 分钟").frame(width: 200, alignment: .leading)
                Text("Notes").frame(maxWidth: .infinity, alignment: .leading)
            }
            Color.clear.frame(width: 20, height: 1)
        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(PetTheme.muted)
            .padding(.horizontal, 8).frame(height: 25).background(PetTheme.surface)
    }
    private func taskGroupHeading(_ group: RecordGroup) -> some View {
        let summary = group.sessions.reduce(into: (pomodoros: 0.0, minutes: 0.0)) { result, session in
            let share = group.taskID.flatMap { id in session.allocations.first { $0.taskID == id }?.share } ?? 1
            if session.isCompletedPomodoro { result.pomodoros += share }
            result.minutes += Double(session.taskMinutes) * share
        }
        return HStack {
            Text(taskTitle(group.taskID)).font(.callout.weight(.semibold))
            Spacer()
            Text("\(FocusAllocationPresentation.number(summary.pomodoros)) 颗 · \(FocusAllocationPresentation.number(summary.minutes)) 分钟")
                .font(.caption).foregroundStyle(PetTheme.muted)
        }.padding(.horizontal, 8).padding(.vertical, 6).background(PetTheme.surface)
    }
    private func sessionRow(_ session: FocusSession, groupID: String = "") -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { select(session, groupID: groupID) } label: {
                    Image(systemName: selected.contains(session.id) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15)).foregroundStyle(PetTheme.accent)
                        .frame(width: 20, height: 30)
                }.buttonStyle(.plain).disabled(!selectable(session))
                    .accessibilityLabel(selected.contains(session.id) ? "取消选择这条番茄钟记录" : "选择这条番茄钟记录")
                    .help("选择这条记录；Shift 点击可连续选择")
                Button { select(session, groupID: groupID) } label: {
                    HStack(spacing: 8) {
                        Text(sessionTimeRange(session)).monospacedDigit()
                            .frame(width: 96, alignment: .leading)
                            .help("\(session.startedAt.formatted()) → \(session.completedAt.formatted())")
                        Text("\(session.minutes)").monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }.font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                        .frame(minHeight: 30, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!selectable(session))
                Button { editAllocations([session]) } label: {
                    allocationCell(session)
                        .foregroundStyle(session.allocations.isEmpty ? PetTheme.muted : PetTheme.accent)
                        .font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                        .frame(width: 200, height: 30, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!selectable(session))
                    .accessibilityLabel(allocationLabel(session))
                    .help(allocationLabel(session) + "\n点击分配任务用时")
                Button { select(session, groupID: groupID) } label: {
                    Text(sessionPreview(session)).foregroundStyle(PetTheme.muted)
                        .font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!selectable(session)).help(sessionDetail(session))
                Button {
                    if expanded.contains(session.id) { expanded.remove(session.id) } else { expanded.insert(session.id) }
                } label: {
                    Image(systemName: expanded.contains(session.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 30)
                }.buttonStyle(.plain)
                    .accessibilityLabel(expanded.contains(session.id) ? "收起番茄钟记录" : "展开番茄钟记录")
                    .help(expanded.contains(session.id) ? "收起编辑" : "查看完整 Notes、编辑或删除")
            }
            .padding(.horizontal, 8)
            if expanded.contains(session.id) { sessionEditor(session).padding(.horizontal, 12).padding(.bottom, 12) }
        }.background(selected.contains(session.id) ? PetTheme.soft : PetTheme.card)
    }
    private func sessionTimeRange(_ session: FocusSession) -> String {
        "\(Self.recordClock.string(from: session.startedAt))–\(Self.recordClock.string(from: session.completedAt))"
    }
    private static let recordClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private func sessionPreview(_ session: FocusSession) -> String {
        var parts: [String] = []
        if session.isPartial { parts.append("提前结束") }
        else if session.actualMinutes == 0 { parts.append("分钟换算") }
        else if !session.countsTowardGoal { parts.append("不计目标") }
        if !session.notes.isEmpty { parts.append(session.notes) }
        return parts.joined(separator: " · ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    private func sessionDetail(_ session: FocusSession) -> String {
        var parts = [sourceLabel(session)]
        if !session.countsTowardGoal && !session.isPartial { parts.append("不计入目标") }
        if !selectable(session) { parts.append("仅用于目标统计，实际投入见专注明细") }
        if !session.notes.isEmpty { parts.append(session.notes) }
        return parts.joined(separator: " · ")
    }
    private func sessionEditor(_ session: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("分钟数").font(.callout)
                IntegerField(title: "分钟", value: sessionBinding(session, \.minutes), range: 0...1440).frame(width: 70)
                    .help(session.isPartial ? "提前结束的分钟已计入分钟调整；修改时会同步调整。" : "这个番茄钟记录的分钟数。")
                Toggle("计入完成数量", isOn: sessionBinding(session, \.countsTowardGoal)).disabled(session.isPartial)
                    .help(session.isPartial ? "提前结束不计作完整番茄。" : session.actualMinutes == 0 ? "分钟换算只服务每日目标，不重复计算任务投入。" : "关闭后不计入当天完成数量。")
                Spacer()
                Button("删除") {
                    var updated = day
                    updated.sessions.removeAll { $0.id == session.id }
                    editor.edit(updated)
                    selected.remove(session.id)
                }
            }
            Text("Notes").font(.caption).foregroundStyle(PetTheme.muted)
            NotesEditor(text: sessionBinding(session, \.notes)).frame(height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
        }
    }
    private var footer: some View {
        HStack {
            if editor.draft != nil || !status.isEmpty {
                Text(editor.draft == nil ? status : "未保存").font(.caption).foregroundStyle(PetTheme.muted)
            }
            Spacer()
            Button("复制当天文本") {
                guard editor.save() else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(JournalExport.markdown([day], tasks: tasks), forType: .string)
                status = "已复制"
            }
            Button("导出 Markdown") { if editor.save() { exportFrom = date; exportTo = date; showingExport = true } }
            Button("保存") { if editor.save() { status = "已保存" } }.buttonStyle(PetButtonStyle(primary: true))
        }.padding(18).background(PetTheme.card)
    }
    private var exportSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("导出专注记录").font(.title2.bold())
            DatePicker("从", selection: $exportFrom, displayedComponents: .date)
            DatePicker("至", selection: $exportTo, displayedComponents: .date)
            HStack {
                Spacer()
                Button("取消") { showingExport = false }
                Button("导出…", action: export).buttonStyle(PetButtonStyle(primary: true))
                    .disabled(Calendar.current.startOfDay(for: exportFrom) > Calendar.current.startOfDay(for: exportTo))
            }
        }.padding(26).frame(width: 430).petPage()
    }
    private func selectionKey(_ sessionID: String, groupID: String) -> String {
        "\(groupID.count):\(groupID)\(sessionID)"
    }
    private func select(_ session: FocusSession, groupID: String) {
        guard selectable(session) else { return }
        let rows: [(key: String, sessionID: String)] = recordsByTask
            ? recordGroups.flatMap { group in group.sessions.filter(selectable).map { (selectionKey($0.id, groupID: group.id), $0.id) } }
            : orderedSessions.filter(selectable).map { (selectionKey($0.id, groupID: ""), $0.id) }
        let key = selectionKey(session.id, groupID: groupID)
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
           let anchor = selectionAnchor, let from = rows.firstIndex(where: { $0.key == anchor }),
           let to = rows.firstIndex(where: { $0.key == key }) {
            selected.formUnion(rows[min(from, to)...max(from, to)].map(\.sessionID))
        } else {
            if selected.contains(session.id) { selected.remove(session.id) } else { selected.insert(session.id) }
            selectionAnchor = key
        }
    }
    private func selectable(_ session: FocusSession) -> Bool {
        !(session.actualMinutes == 0 && session.completedPomodoro == false && !session.isPartial)
    }
    private func assignSelection(_ taskID: String?) {
        guard !selected.isEmpty, editor.save() else { return }
        let live = model.data.journalDay(dateKey).sessions.filter { selected.contains($0.id) }
        guard model.assignFocusSessions(live, to: taskID) else { return }
        status = taskID == nil ? "已取消关联 · \(live.count) 条" : "已关联 · \(live.count) 条"
        selected = []; selectionAnchor = nil
    }
    private func editAllocations(_ sessions: [FocusSession]) {
        guard !sessions.isEmpty, editor.save() else { return }
        let ids = Set(sessions.map(\.id))
        let live = model.data.journalDay(dateKey).sessions.filter { ids.contains($0.id) && selectable($0) }
        guard !live.isEmpty else { return }
        let initial = live[0].allocations
        allocationEdit = AllocationEdit(sessions: live,
            initial: live.allSatisfy { FocusTaskAllocationRules.same($0.allocations, initial) } ? initial : [])
    }
    private func allocationLabel(_ session: FocusSession) -> String {
        FocusAllocationPresentation.label(session.allocations, tasks: tasks, totalMinutes: Double(session.taskMinutes))
    }
    @ViewBuilder private func allocationCell(_ session: FocusSession) -> some View {
        if session.allocations.isEmpty {
            Text("未关联")
        } else {
            HStack(spacing: 5) {
                ForEach(Array(session.allocations.prefix(3).enumerated()), id: \.element.taskID) { index, allocation in
                    if index > 0 { Text("·").foregroundStyle(PetTheme.muted) }
                    HStack(spacing: 3) {
                        Text(taskTitle(allocation.taskID)).lineLimit(1).truncationMode(.tail)
                        Text(FocusAllocationPresentation.number(Double(session.taskMinutes) * allocation.share))
                            .monospacedDigit().fixedSize()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if session.allocations.count > 3 { Text("+\(session.allocations.count - 3)").fixedSize() }
            }
        }
    }
    private func taskTitle(_ id: String?) -> String {
        guard let id else { return "未关联任务" }
        return tasks.first { $0.id == id }?.title ?? "已删除任务"
    }
    private func sourceLabel(_ session: FocusSession) -> String {
        if session.isPartial { return "提前结束" }
        if session.actualMinutes == 0 { return "分钟换算" }
        return session.source == "automatic" ? "自动" : "手动"
    }
    private func applyMinuteChange(subtract: Bool) {
        let amount = subtract ? minutesToSubtract : minutesToAdd
        guard editor.adjustMinutes(by: subtract ? -amount : amount) else { return }
        if subtract { minutesToSubtract = 0 } else { minutesToAdd = 0 }
        if editor.save() { status = "已\(subtract ? "减少" : "增加") \(amount) 分钟" }
    }
    private func summary(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.callout).foregroundStyle(PetTheme.muted)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundStyle(PetTheme.accent)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func moveDay(_ delta: Int) { editor.navigate(Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date) }
    private func sessionBinding<T>(_ session: FocusSession, _ path: WritableKeyPath<FocusSession, T>) -> Binding<T> {
        Binding(get: { day.sessions.first { $0.id == session.id }?[keyPath: path] ?? session[keyPath: path] }, set: { value in
            var updated = day
            if let index = updated.sessions.firstIndex(where: { $0.id == session.id }) {
                updated.sessions[index][keyPath: path] = value
                updated.sessions[index].minutes = min(1440, max(0, updated.sessions[index].minutes))
                editor.edit(updated)
            }
        })
    }
    private func addSession() {
        var updated = day
        let minutes = model.data.settings.focusMinutes
        let completion = dateKey == FocusAccounting.key(Date()) ? Date() : FocusAccounting.date(from: dateKey) ?? Date()
        let session = FocusSession(source: "manual", startedAt: completion.addingTimeInterval(-Double(minutes * 60)), completedAt: completion,
                                   minutes: minutes, taskID: model.data.currentTaskID, taskAllocations: model.data.currentAllocations,
                                   assignmentSource: model.data.currentAllocations.isEmpty ? nil : "selected",
                                   actualMinutes: minutes, completedPomodoro: true)
        updated.sessions.append(session)
        editor.edit(updated)
        expanded.insert(session.id)
    }
    private func export() {
        let lower = Calendar.current.startOfDay(for: exportFrom)
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: exportTo))!
        let days = model.data.journal.filter { day in
            guard let date = FocusAccounting.date(from: day.date) else { return false }
            return date >= lower && date < upper
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "专注记录.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JournalExport.markdown(days, tasks: tasks).write(to: url, atomically: true, encoding: .utf8); showingExport = false; status = "已导出" }
        catch { model.error = error.localizedDescription }
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("苏无度 · 沈青 使用说明").font(.largeTitle.bold())
                Text("拖动桌宠移动位置；右键打开完整菜单。单击播放互动，专注期间显示剩余时间。双击开始、暂停或继续专注；三击打开新聊天。睡眠时，在四秒内完成两次分开的单击可以叫醒桌宠；快速双击仍然控制专注。")
                Text("鼠标穿透与找回").font(.headline)
                Text("开启鼠标穿透后，点击会传给后面的应用。按 Control + Option + P，或点击菜单栏爱心图标 → 叫回桌宠。恢复会将桌宠移到鼠标所在的显示器。")
                Text("专注与记录").font(.headline)
                Text("完整专注自动记录，提前停止时记录已完成的整分钟。暂停不计时，Mac 睡眠或应用重启后保持暂停。每天 21:00 开始下一记录日，跨界分钟按实际片段分配。记录窗口支持目标、分钟调整、补记、删除、每日 / 单次 Notes、复制及日期范围导出。完成专注后进入休息，休息结束时提醒；重新开始可以提前结束休息。")
                Text("任务与番茄匹配").font(.headline)
                Text("从启动面板、菜单栏或桌宠右键打开“任务与专注”。任务统一放在一张清单，支持预计番茄数、截止日期、可选截止时间、说明和手动完成；预计数是投入预算。截止日期按日历判断，与 21:00 记录日分界独立。可粘贴清单预览导入，备忘也能转为任务。")
                Text("当前任务可多选，默认均分本轮分钟，也可直接填写各任务用时。例如 25 分钟中补课 10 分钟、网站 15 分钟，分别计入 0.4、0.6 颗番茄。每轮自动沿用所选分配；进行中切换只影响下一轮，暂停或恢复保留本轮分配。番茄表格一行一条，点击任务列调整用时；Shift 连选后点“关联任务”可批量分配。同长度的批量记录直接按每条分钟分配；时长不同时按合计分钟分配，再按记录时长分摊；可清空、撤销最近一次关联。按任务查看、完成历史和导出均包含各任务用时。提前结束仅累计实际分钟，分钟换算记录不重复计算投入。")
                Text("在备忘中点击“AI 提取”，AI 会提取任务并保留原文出处。“任务 - 数字”或紧接下一行的数字表示预计番茄数；例如“Cs370 - 15, catchup cheat sheet +5”会分成课程任务 15 颗和对应 cheat sheet 5 颗，课程号不计入预算。明确截止日期由 AI 根据本地日期和时区整理，不明确的值留空。检查、修改和勾选后整批导入，原备忘保留。该操作向设置中的服务发送专用指令、当前备忘、日期/时区及固定输出格式；应用检查返回格式、数值和原文出处。离线时可手动转任务或粘贴清单。")
                Text("任务清单中的“完成历史”保存已完成任务，显示完成时间、说明、原文出处及累计投入。展开可查看关联专注明细、跳转到对应记录日，也可重新打开任务继续执行。旧任务如果没有保存完成时间，会显示时间未记录。")
                Text("“AI 匹配”和“AI 建议”使用设置中的 ChatGPT／OpenAI API，发送当前范围的记录序号、真实时间、实际分钟、任务及当前分配、单次 Notes。可以说“第一颗补课 10 分钟、网站 15 分钟”“第二颗再加笔记”或“清空第三颗关联”。多个任务未指定用时则均分；AI 返回固定格式的完整分配，未知任务或无法确定的记录会省略。先查看修改前后各任务的分钟数，再应用整批结果；记录有新修改时会阻止覆盖，应用后可撤销。离线“Notes 匹配”只识别明确且唯一的完整任务名。")
                Text("聊天与隐私").font(.headline)
                Text("每次打开聊天默认新建会话；左侧可以继续旧聊天，右键归档或恢复。聊天保存在本机；开启记忆后，近期聊天摘要和最多 50 条明确记住的事实可用于其他聊天。说“请记住……”或“请忘记……”管理事实。关闭记忆不会删除聊天。")
                Text("ChatGPT 模式使用随附 Codex 组件完成登录，API 模式使用保存在 macOS Keychain 的 API key。离线模式仅提供固定回复。开启“看屏幕”时，每次发送会截取所有显示器并合成一张图片，排除聊天窗口；图片会随消息发送给所选服务，请求结束后删除临时文件。屏幕录制权限由 macOS 管理。")
                Text("数据与外部联动").font(.headline)
                Text("数据位于 ~/Library/Application Support/SuWuDu。设置中可导入 Windows 数据；导入前会备份，相同日期 / ID 的记录会替换。通过此目录的 command.json 可以发送 {\"state\":\"working\",\"message\":\"正在工作\"}；文件读取后删除。")
                Text("菜单栏提供设置、通知授权、启动面板和退出入口。全屏应用、Spaces 和系统通知的最终显示由 macOS 决定。")
            }.padding(24)
        }.frame(minWidth: 580, minHeight: 580).petPage()
    }
}
