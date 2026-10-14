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
                let task = session.taskID.map { id in tasks.first { $0.id == id }?.title ?? "已删除任务" } ?? "未关联任务"
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
            if edited.taskID != original.taskID {
                live.taskID = edited.taskID
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
    @State private var status = "记录日会在晚上 9 点切换。"
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
            if recordsByTask, $0.taskID != $1.taskID {
                if $0.taskID == nil { return false }
                if $1.taskID == nil { return true }
                let firstTitle = taskTitle($0.taskID), secondTitle = taskTitle($1.taskID)
                if firstTitle != secondTitle { return firstTitle.localizedStandardCompare(secondTitle) == .orderedAscending }
                return ($0.taskID ?? "") < ($1.taskID ?? "")
            }
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
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
                selected = []; selectionAnchor = nil; expanded = []
                model.cancelFocusMatch(); model.clearFocusMatch()
            }
            .onChange(of: day.sessions.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .onChange(of: selected) { _, _ in model.clearFocusMatch() }
            .sheet(isPresented: $showingTargets) { TargetScheduleView(model: model, initialDate: date) }
            .sheet(isPresented: $showingExport) { exportSheet }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("任务与专注").font(.system(size: 24, weight: .bold))
                Text("计划、投入和每一颗番茄放在一起").font(.caption).foregroundStyle(PetTheme.muted)
            }
            Spacer()
            Button { moveDay(-1) } label: { Image(systemName: "chevron.left") }.help("前一天")
            DatePicker("记录日", selection: Binding(get: { date }, set: { editor.navigate($0) }), displayedComponents: .date)
                .labelsHidden().frame(width: 120).help("每晚 21:00 切换记录日")
            Button { moveDay(1) } label: { Image(systemName: "chevron.right") }.help("后一天")
            Button("今天") { editor.navigate(FocusAccounting.date(from: FocusAccounting.key(Date())) ?? Date()) }
        }.padding(22).background(PetTheme.card)
    }
    private var taskList: some View {
        FocusTasksView(model: model, selectedSessionCount: selected.count, assignSelection: assignSelection)
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
                            Text("当天目标（个）").font(.headline)
                            IntegerField(title: "0–999", value: binding(\.target), range: 0...999)
                        }
                        VStack(alignment: .leading) {
                            Text("当天分钟调整（可正可负）").font(.headline)
                            IntegerField(title: "分钟", value: binding(\.adjustment), range: -10_000...10_000)
                        }
                    }
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("加多少分钟").font(.headline)
                            HStack {
                                IntegerField(title: "分钟", value: $minutesToAdd, range: 0...10_000)
                                Button("增加") { applyMinuteChange(subtract: false) }.disabled(minutesToAdd == 0)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("减多少分钟").font(.headline)
                            HStack {
                                IntegerField(title: "分钟", value: $minutesToSubtract, range: 0...10_000)
                                Button("减少") { applyMinuteChange(subtract: true) }.disabled(minutesToSubtract == 0)
                            }
                        }
                    }
                    Text("输入本次增减量，点击后自动计算并保存当天记录。分钟调整保留原来的折算方式，不会凭空增加任务投入。")
                        .font(.caption).foregroundStyle(PetTheme.muted)
                    Button("批量设置番茄钟目标") { if editor.save() { showingTargets = true } }
                }.padding(.top, 12)
            }.font(.callout.weight(.semibold))
        }
    }
    private var sessionsCard: some View {
        PetCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("番茄钟记录").font(.title3.bold())
                    Text("任务与 Notes 直接可见，展开后仍可编辑分钟、Notes 或删除。")
                        .font(.caption).foregroundStyle(PetTheme.muted)
                }
                Spacer()
                Button("＋ 补记", action: addSession).help("补记一个番茄钟")
            }
            HStack {
                Picker("排列方式", selection: $recordsByTask) {
                    Text("按时间").tag(false)
                    Text("按任务").tag(true)
                }.pickerStyle(.segmented).frame(width: 210)
                Spacer()
                Button("选未关联") { selected = Set(day.sessions.filter { $0.taskID == nil && selectable($0) }.map(\.id)); selectionAnchor = nil }
                    .disabled(day.sessions.allSatisfy { $0.taskID != nil || !selectable($0) })
                Button("全选") { selected = Set(day.sessions.filter(selectable).map(\.id)); selectionAnchor = nil }
                    .disabled(day.sessions.allSatisfy { !selectable($0) })
            }
            if !selected.isEmpty {
                HStack(spacing: 8) {
                    Text("已选 \(selected.count) 条").font(.caption.weight(.semibold))
                    Menu("关联任务…") {
                        ForEach(tasks) { task in Button(task.title) { assignSelection(task.id) } }
                        Divider()
                        Button("清除任务关联") { assignSelection(nil) }
                    }
                    Spacer()
                    Button("取消选择") { selected = []; selectionAnchor = nil }
                }
            }
            HStack {
                Text("点击选择；Shift 点击连续选中一段，再点击任务旁的关联按钮。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
                Spacer()
                if model.canUndoFocusAssignments {
                    Button("撤销匹配") { if editor.save(), model.undoFocusAssignments() { status = "已撤销最近一批任务匹配。" } }
                }
            }
            if day.sessions.isEmpty {
                Text("这一天还没有番茄钟记录。").foregroundStyle(PetTheme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            ForEach(Array(orderedSessions.enumerated()), id: \.element.id) { index, session in
                if recordsByTask && (index == 0 || orderedSessions[index - 1].taskID != session.taskID) {
                    taskGroupHeading(session.taskID)
                }
                sessionRow(session)
            }
        }
    }
    private func taskGroupHeading(_ taskID: String?) -> some View {
        let group = day.sessions.filter { $0.taskID == taskID }
        return HStack {
            Text(taskTitle(taskID)).font(.callout.weight(.semibold))
            Spacer()
            Text("\(group.filter(\.isCompletedPomodoro).count) 颗 · \(group.reduce(0) { $0 + $1.taskMinutes }) 分钟")
                .font(.caption).foregroundStyle(PetTheme.muted)
        }.padding(.top, 8)
    }
    private func sessionRow(_ session: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button { select(session) } label: {
                    Image(systemName: selected.contains(session.id) ? "checkmark.square.fill" : "square")
                        .font(.title3).foregroundStyle(PetTheme.accent)
                }.buttonStyle(.plain).disabled(!selectable(session)).help("选择这条记录；Shift 点击可连续选择")
                Button { select(session) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(session.startedAt.formatted(date: .omitted, time: .shortened))–\(session.completedAt.formatted(date: .omitted, time: .shortened)) · \(session.minutes) 分钟")
                                .font(.callout.weight(.semibold)).monospacedDigit()
                            Spacer()
                            Text(sourceLabel(session)).font(.caption).foregroundStyle(PetTheme.muted)
                        }
                        Text(taskTitle(session.taskID)).font(.callout).foregroundStyle(session.taskID == nil ? PetTheme.muted : PetTheme.accent)
                        if !session.notes.isEmpty {
                            Text(session.notes).font(.caption).foregroundStyle(PetTheme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        if !session.countsTowardGoal && !session.isPartial {
                            Text("不计入目标").font(.caption).foregroundStyle(PetTheme.muted)
                        }
                        if !selectable(session) {
                            Text("仅用于目标统计，实际投入见专注明细。")
                                .font(.caption).foregroundStyle(PetTheme.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!selectable(session))
                Button {
                    if expanded.contains(session.id) { expanded.remove(session.id) } else { expanded.insert(session.id) }
                } label: {
                    Image(systemName: expanded.contains(session.id) ? "chevron.up" : "chevron.down")
                }.help(expanded.contains(session.id) ? "收起编辑" : "编辑记录")
            }
            if expanded.contains(session.id) { sessionEditor(session) }
        }.padding(12).background(selected.contains(session.id) ? PetTheme.soft : PetTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected.contains(session.id) ? PetTheme.accent : Color.clear))
    }
    private func sessionEditor(_ session: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("分钟数").font(.callout)
                IntegerField(title: "分钟", value: sessionBinding(session, \.minutes), range: 0...1440).frame(width: 70)
                Toggle("计入完成数量", isOn: sessionBinding(session, \.countsTowardGoal)).disabled(session.isPartial)
                Spacer()
                Button("删除") {
                    var updated = day
                    updated.sessions.removeAll { $0.id == session.id }
                    editor.edit(updated)
                    selected.remove(session.id)
                }
            }
            if session.isPartial {
                Text("提前结束的分钟已计入分钟调整；修改或删除会同步调整，不计作完整番茄。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            } else if session.actualMinutes == 0 {
                Text("分钟换算用于目标统计，实际投入见专注明细；这条记录的关联不增加任务投入。手动补记可直接关联任务。")
                    .font(.caption).foregroundStyle(PetTheme.muted)
            }
            Text("这个番茄钟的 Notes").font(.caption).foregroundStyle(PetTheme.muted)
            NotesEditor(text: sessionBinding(session, \.notes)).frame(height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
        }
    }
    private var footer: some View {
        HStack {
            Text(editor.draft == nil ? status : "有未保存的记录修改").font(.caption).foregroundStyle(PetTheme.muted)
            Spacer()
            Button("复制当天文本") {
                guard editor.save() else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(JournalExport.markdown([day], tasks: tasks), forType: .string)
                status = "已复制当天记录。"
            }
            Button("导出 Markdown") { if editor.save() { exportFrom = date; exportTo = date; showingExport = true } }
            Button("保存") { if editor.save() { status = "已保存。" } }.buttonStyle(PetButtonStyle(primary: true))
        }.padding(18).background(PetTheme.card)
    }
    private var exportSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            PetHeading(title: "导出专注记录", subtitle: "选择日期范围，保存为 Markdown 文件，包含任务和 Notes。")
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
    private func select(_ session: FocusSession) {
        guard selectable(session) else { return }
        let ids = orderedSessions.filter(selectable).map(\.id)
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
           let anchor = selectionAnchor, let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: session.id) {
            selected.formUnion(ids[min(from, to)...max(from, to)])
        } else {
            if selected.contains(session.id) { selected.remove(session.id) } else { selected.insert(session.id) }
            selectionAnchor = session.id
        }
    }
    private func selectable(_ session: FocusSession) -> Bool {
        !(session.actualMinutes == 0 && session.completedPomodoro == false && !session.isPartial)
    }
    private func assignSelection(_ taskID: String?) {
        guard !selected.isEmpty, editor.save() else { return }
        let live = model.data.journalDay(dateKey).sessions.filter { selected.contains($0.id) }
        guard model.assignFocusSessions(live, to: taskID) else { return }
        status = "已将 \(live.count) 条记录\(taskID == nil ? "取消任务关联" : "关联到「\(taskTitle(taskID))」")。"
        selected = []; selectionAnchor = nil
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
        if editor.save() { status = "已\(subtract ? "减少" : "增加") \(amount) 分钟并保存。" }
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
                                   minutes: minutes, taskID: model.data.currentTaskID, assignmentSource: model.data.currentTaskID == nil ? nil : "selected",
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
        do { try JournalExport.markdown(days, tasks: tasks).write(to: url, atomically: true, encoding: .utf8); showingExport = false; status = "已导出 Markdown。" }
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
                Text("选好当前任务后，每轮专注自动关联；进行中切换任务只影响下一轮。本轮暂停、继续或恢复后仍保留原任务。记录列表直接显示任务与 Notes；勾选记录，按住 Shift 连续选择，再点任务旁“关联”，即可一次修正整批，或清除归属、撤销最近一次关联。按任务查看可汇总投入。提前结束明细记录真实分钟，分钟换算记录仅服务每日目标，避免重复计算任务投入。")
                Text("“一句话匹配”和“AI 建议”使用设置中已有的 ChatGPT／OpenAI API；只发送当前匹配范围的记录时间、任务名称与说明、单次 Notes，不发送聊天历史、自由备忘或截图。先检查原任务、新任务与原因，再应用整批结果；有歧义或记录已被修改时不会覆盖。离线时可用“本机建议”，仅识别 Notes 中明确且唯一的完整任务名。未关联记录可以保留，不必逐颗填写。")
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
