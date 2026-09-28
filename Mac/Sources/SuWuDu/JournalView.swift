import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum JournalExport {
    static func markdown(_ days: [JournalDay]) -> String {
        days.sorted { $0.date < $1.date }.map { day in
            var text = "## \(day.date)\n\n完成：\(day.count) / \(day.target) 个番茄钟\n总计：\(day.total) 分钟\n分钟调整：\(day.adjustment)\n"
            if !day.notes.isEmpty { text += "\n### Notes\n\n\(day.notes)\n" }
            for session in day.sessions {
                text += "\n- \(session.minutes) 分钟 · \(session.source == "automatic" ? "自动" : "手动")\(session.countsTowardGoal ? "" : " · 不计入目标")"
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
    var day: JournalDay { draft ?? model.data.journal.first { $0.date == dateKey } ?? JournalDay(date: dateKey) }
    func edit(_ updated: JournalDay) {
        if baseline == nil { baseline = day }
        draft = updated
    }
    func save() {
        guard var value = draft, let baseline else { return }
        let latest = model.data.journal.first { $0.date == value.date } ?? JournalDay(date: value.date)
        let known = Set(baseline.sessions.map(\.id) + value.sessions.map(\.id))
        value.sessions += latest.sessions.filter { !known.contains($0.id) }
        value.adjustment += latest.adjustment - baseline.adjustment
        model.saveDay(value)
        draft = nil
        self.baseline = nil
    }
    func navigate(_ newDate: Date) { save(); date = newDate }
}

@MainActor struct JournalView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: JournalEditor
    @State private var expanded: Set<String> = []
    @State private var showingExport = false
    @State private var status = "记录日会在晚上 9 点切换。"
    @State private var exportFrom = Date()
    @State private var exportTo = Date()
    private var date: Date { editor.date }
    private var dateKey: String { editor.dateKey }
    private var day: JournalDay { editor.day }
    private func binding<T>(_ key: WritableKeyPath<JournalDay, T>) -> Binding<T> {
        Binding(get: { day[keyPath: key] }, set: { value in var updated = day; updated[keyPath: key] = value; editor.edit(updated) })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("专注记录").font(.system(size: 24, weight: .bold))
                    Text("回顾每一段认真投入的时间").font(.caption).foregroundStyle(PetTheme.muted)
                }
                Spacer()
                Button { moveDay(-1) } label: { Image(systemName: "chevron.left") }.help("前一天")
                DatePicker("记录日", selection: Binding(get: { date }, set: { editor.navigate($0) }), displayedComponents: .date).labelsHidden().frame(width: 120)
                Button { moveDay(1) } label: { Image(systemName: "chevron.right") }.help("后一天")
                Button("今天") { editor.navigate(FocusAccounting.date(from: FocusAccounting.key(Date())) ?? Date()) }
            }.padding(22).background(PetTheme.card)
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    PetCard {
                        HStack {
                            summary("完成 / 目标", "\(day.count) / \(day.target)")
                            summary("番茄钟时间", "\(day.sessions.filter(\.countsTowardGoal).reduce(0) { $0 + $1.minutes }) 分钟")
                            summary("最终计入", "\(day.total) 分钟")
                        }
                        ProgressView(value: day.target > 0 ? min(1, Double(day.count) / Double(day.target)) : 0)
                        HStack(spacing: 18) {
                            VStack(alignment: .leading) {
                                Text("今日目标（个）").font(.headline)
                                TextField("0–999", value: Binding(get: { day.target }, set: { binding(\.target).wrappedValue = min(999, max(0, $0)) }), format: .number)
                            }
                            VStack(alignment: .leading) {
                                Text("今日分钟调整（可正可负）").font(.headline)
                                TextField("分钟", value: Binding(get: { day.adjustment }, set: { binding(\.adjustment).wrappedValue = min(10_000, max(-10_000, $0)) }), format: .number)
                            }
                        }
                    }
                    PetCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("番茄钟").font(.title3.bold())
                                Text("完成时自动记录，也可以手动补记或删除。").font(.caption).foregroundStyle(PetTheme.muted)
                            }
                            Spacer()
                            Button("＋ 补记一个番茄钟", action: addSession)
                        }
                        if day.sessions.isEmpty { Text("这一天还没有番茄钟记录。").foregroundStyle(PetTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 18) }
                        ForEach(day.sessions) { session in
                            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(session.id) }, set: { if $0 { expanded.insert(session.id) } else { expanded.remove(session.id) } })) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("分钟数")
                                        TextField("分钟", value: sessionBinding(session, \.minutes), format: .number).frame(width: 70)
                                        Toggle("计入完成数量", isOn: sessionBinding(session, \.countsTowardGoal))
                                        Spacer()
                                        Button("删除") { var updated = day; updated.sessions.removeAll { $0.id == session.id }; editor.edit(updated) }
                                    }
                                    Text("这个番茄钟的 Notes").font(.caption).foregroundStyle(PetTheme.muted)
                                    TextEditor(text: sessionBinding(session, \.notes)).frame(height: 65)
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
                                }.padding(.top, 10)
                            } label: {
                                Text("\(session.completedAt.formatted(date: .omitted, time: .shortened)) · \(session.minutes) 分钟 · \(session.source == "automatic" ? "自动" : "手动")\(session.countsTowardGoal ? "" : " · 不计入目标")").font(.callout.weight(.semibold))
                            }.padding(12).background(PetTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    PetCard("今日 Notes") {
                        TextEditor(text: binding(\.notes)).frame(height: 110)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(PetTheme.border))
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Text(editor.draft == nil ? status : "有未保存的修改").font(.caption).foregroundStyle(PetTheme.muted)
                Spacer()
                Button("复制当天文本") { editor.save(); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(JournalExport.markdown([day]), forType: .string); status = "已复制当天记录。" }
                Button("导出 Markdown") { editor.save(); exportFrom = date; exportTo = date; showingExport = true }
                Button("保存") { editor.save(); status = "已保存。" }.buttonStyle(PetButtonStyle(primary: true))
            }.padding(18).background(PetTheme.card)
        }.frame(minWidth: 670, minHeight: 600).petPage()
            .sheet(isPresented: $showingExport) {
                VStack(alignment: .leading, spacing: 20) {
                    PetHeading(title: "导出专注记录", subtitle: "选择日期范围，保存为 Markdown 文件。")
                    DatePicker("从", selection: $exportFrom, displayedComponents: .date)
                    DatePicker("至", selection: $exportTo, displayedComponents: .date)
                    HStack {
                        Spacer()
                        Button("取消") { showingExport = false }
                        Button("导出…", action: export).buttonStyle(PetButtonStyle(primary: true))
                            .disabled(Calendar.current.startOfDay(for: exportFrom) > Calendar.current.startOfDay(for: exportTo))
                    }
                }.padding(26).frame(width: 390).petPage()
            }
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
                updated.sessions[index].minutes = min(1440, max(1, updated.sessions[index].minutes))
                editor.edit(updated)
            }
        })
    }
    private func addSession() {
        var updated = day
        let minutes = model.data.settings.focusMinutes
        let completion = dateKey == FocusAccounting.key(Date()) ? Date() : FocusAccounting.date(from: dateKey) ?? Date()
        let session = FocusSession(source: "manual", startedAt: completion.addingTimeInterval(-Double(minutes * 60)), completedAt: completion, minutes: minutes)
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
        do { try JournalExport.markdown(days).write(to: url, atomically: true, encoding: .utf8); showingExport = false; status = "已导出 Markdown。" }
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
