import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor struct LauncherView: View {
    @ObservedObject var model: AppModel
    var recover: () -> Void
    var chat: () -> Void
    var journal: () -> Void
    var settings: () -> Void
    var help: () -> Void
    var hide: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PetHeading(title: "苏无度沈青", subtitle: "桌宠控制面板")
                PetCard("快速操作") {
                    HStack(spacing: 10) {
                        action("叫醒桌宠", recover)
                        action("和她聊聊", chat)
                    }
                }
                PetCard("管理") {
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow { action("设置", settings); action("使用说明", help) }
                        GridRow {
                            action("今日专注记录", journal)
                            action("在 Finder 中显示应用") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                        }
                        GridRow { action("把桌宠收起来", hide); action("完全退出") { NSApp.terminate(nil) } }
                    }
                }
                Text("提示：右键桌面上的角色，可以更快地进入聊天、专注、设置和其它常用功能。\n⌃⌥P 可关闭鼠标穿透并叫回桌宠。")
                    .font(.callout).foregroundStyle(PetTheme.muted).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading).background(PetTheme.soft, in: RoundedRectangle(cornerRadius: 9))
            }.padding(24)
        }.frame(minWidth: 420, minHeight: 510).petPage()
    }
    private func action(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 25) }
    }
}

@MainActor struct SettingsView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    @State private var draft: SettingsDraft
    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
        _draft = State(initialValue: SettingsDraft(model.data.settings))
    }
    private enum Category: String, CaseIterable {
        case appearance = "外观与行为", focus = "专注与提醒", chat = "AI 与记忆", storage = "本地数据"
        var icon: String {
            switch self { case .appearance: return "pawprint"; case .focus: return "timer"; case .chat: return "bubble.left.and.bubble.right"; case .storage: return "externaldrive" }
        }
    }
    @State private var category: Category = .appearance
    @State private var key = ""
    @State private var startup = SMAppService.mainApp.status == .enabled
    @State private var status = ""
    private func binding<T>(_ path: WritableKeyPath<Settings, T>, previewAppearance: Bool = false) -> Binding<T> {
        Binding(get: { draft.value[keyPath: path] }, set: {
            draft.value[keyPath: path] = $0
            if previewAppearance {
                model.previewAppearance(skin: draft.value.skin, scale: draft.value.scale)
            }
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PetHeading(title: "桌宠设置", subtitle: "调整苏无度或沈青的外观、陪伴方式和可选 AI。")
                HStack(spacing: 8) {
                    ForEach(Category.allCases, id: \.self) { item in
                        Button { category = item } label: {
                            Label(item.rawValue, systemImage: item.icon).frame(maxWidth: .infinity)
                        }.buttonStyle(PetButtonStyle(primary: category == item))
                            .accessibilityAddTraits(category == item ? .isSelected : [])
                    }
                }
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch category {
                    case .appearance: appearance
                    case .focus: focus
                    case .chat: chat
                    case .storage: storage
                    }
                }.padding(24)
            }.id(category)
            Divider()
            HStack {
                Text(status).font(.caption).foregroundStyle(PetTheme.muted)
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("保存", action: save).buttonStyle(PetButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
                    .disabled(model.busy)
            }.padding(18).background(PetTheme.card)
        }.frame(minWidth: 610, minHeight: 580).petPage()
    }
    private func save() {
        guard draft.value.wanderMin <= draft.value.wanderMax, draft.value.microMin <= draft.value.microMax else {
            status = "最短间隔不能大于最长间隔。"; return
        }
        let values: [(Int, ClosedRange<Int>)] = [(draft.value.wanderMin, 3...300), (draft.value.wanderMax, 3...300),
            (draft.value.hydrationMinutes, 10...240), (draft.value.focusMinutes, 1...120), (draft.value.breakMinutes, 1...120),
            (draft.value.microMin, 1...120), (draft.value.microMax, 1...120), (draft.value.microSeconds, 1...300)]
        guard values.allSatisfy({ $0.1.contains($0.0) }) else { status = "请检查时长：专注和微休息间隔 1–120 分钟，喝水 10–240 分钟，漫游 3–300 秒，微休息 1–300 秒。"; return }
        do {
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try Keychain.save(key) }
            if startup != (SMAppService.mainApp.status == .enabled) {
                if startup { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
            model.changeSettings { $0 = draft.applying(to: $0) }
            close()
        } catch { model.error = error.localizedDescription }
    }
    private var appearance: some View {
        PetCard("外观与行为") {
            VStack(alignment: .leading, spacing: 6) { Text("名字").font(.headline); TextField("名字", text: binding(\.petName)) }
            Picker("角色", selection: binding(\.skin, previewAppearance: true)) { Text("苏无度").tag("suwudu"); Text("沈青").tag("shenqing") }
            HStack { Slider(value: binding(\.scale, previewAppearance: true), in: 0.2...1.5, step: 0.05) { Text("桌宠大小") }; Text(draft.value.scale, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 50) }
            Toggle("始终置顶", isOn: binding(\.topmost))
            Toggle("在所有桌面空间显示", isOn: binding(\.allSpaces))
            Toggle("自动漫游", isOn: binding(\.wander))
            numberRow("漫游最短间隔", unit: "秒", path: \.wanderMin, range: 3...300)
            numberRow("漫游最长间隔", unit: "秒", path: \.wanderMax, range: 3...300)
            Toggle("登录 Mac 时自动启动", isOn: $startup)
            Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
            Text("鼠标穿透可从桌宠右键菜单开启。使用 ⌃⌥P 或菜单栏叫回。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var focus: some View {
        PetCard("专注与提醒") {
            Toggle("启用喝水提醒", isOn: binding(\.hydration))
            numberRow("喝水间隔", unit: "分钟", path: \.hydrationMinutes, range: 10...240)
            Divider()
            numberRow("默认专注时长", unit: "分钟", path: \.focusMinutes, range: 1...120)
            numberRow("默认休息时长", unit: "分钟", path: \.breakMinutes, range: 1...120)
            Text("番茄钟铃声").font(.headline)
            soundRow("开始铃声", path: \.startSound)
            soundRow("完成铃声", path: \.finishSound, complete: true)
            soundRow("休息结束", path: \.breakSound, complete: true)
            Divider()
            Text("随机提示音与微休息").font(.headline)
            Toggle("启用番茄钟内的随机微休息", isOn: binding(\.microbreaks))
            VStack(alignment: .leading, spacing: 12) {
            numberRow("最短间隔", unit: "分钟", path: \.microMin, range: 1...120)
            numberRow("最长间隔", unit: "分钟", path: \.microMax, range: 1...120)
            numberRow("微休息", unit: "秒", path: \.microSeconds, range: 1...300)
            soundRow("微休息开始", path: \.microStartSound, complete: true)
            soundRow("微休息结束", path: \.microEndSound)
            }.disabled(!draft.value.microbreaks)
            Button("允许系统通知") {
                Task {
                    do { status = try await Notifications.request() ? "通知已允许" : "通知未允许；桌宠气泡仍可显示。" }
                    catch { model.error = error.localizedDescription }
                }
            }
            if !status.isEmpty { Text(status).font(.caption) }
        }
    }
    private func numberRow(_ title: String, unit: String, path: WritableKeyPath<Settings, Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: binding(path), format: .number).multilineTextAlignment(.center).frame(width: 65)
            Text(unit).foregroundStyle(PetTheme.muted)
            Stepper(title, value: binding(path), in: range).labelsHidden()
        }
    }
    private func soundRow(_ title: String, path: WritableKeyPath<Settings, String>, complete: Bool = false) -> some View {
        HStack {
            Picker(title, selection: binding(path)) {
                ForEach(SoundService.options, id: \.0) { item in Text(item.1).tag(item.0) }
            }
            Button("试听") { model.sound.play(draft.value[keyPath: path], complete: complete) }
        }
    }
    private var chat: some View {
        PetCard("AI 与记忆") {
            Picker("聊天方式", selection: binding(\.provider)) {
                Text("ChatGPT 登录").tag("codex")
                Text("OpenAI API").tag("openai")
                Text("离线陪伴").tag("offline")
            }.pickerStyle(.segmented).disabled(model.busy)
            if draft.value.provider == "codex" { CodexSettingsView(model: model, client: model.ai.codex, settings: $draft.value) }
            if draft.value.provider == "openai" {
                SecureField("新的 API key（留空保持不变，点击保存后生效）", text: $key)
                HStack {
                    Button("删除已保存的 key") { do { try Keychain.save(""); status = "API key 已删除" } catch { model.error = error.localizedDescription } }
                }
                TextField("API 模型名称", text: binding(\.apiModel))
                Text("API 使用独立的 API 账号计费；填写该账号可用的模型。") .font(.caption).foregroundStyle(.secondary)
            }
            if draft.value.provider == "offline" { Text("不联网，也不发送任何聊天内容；仍会回应问候、休息、完成任务等简单消息。").font(.callout).foregroundStyle(PetTheme.muted) }
            Toggle("开启跨聊天记忆", isOn: binding(\.memory))
            Toggle("看屏幕（每次发送附一张多显示器截图）", isOn: binding(\.screenVision))
            Text("聊天记录始终保存在本机。联网聊天会发送当前消息和聊天上下文；开启记忆或看屏幕时还会发送相应内容。离线模式不会截图或联网。")
                .font(.caption).foregroundStyle(.secondary)
            if !status.isEmpty { Text(status).font(.caption) }
        }
    }
    private var storage: some View {
        PetCard("本地数据与记忆管理") {
            Text("本地数据：~/Library/Application Support/SuWuDu")
            Button("打开数据文件夹") { NSWorkspace.shared.open(model.store.directory) }
            Button("导入 Windows 数据…") { importWindows() }.disabled(model.busy || model.data.focus != nil)
            Text("选择从 Windows PixelHeartDesktopPet 复制的文件夹。相同日期和聊天 ID 会被导入版本替换；其他记录保留。导入前创建完整备份。API key 和登录信息需重新设置。请先结束当前专注。")
                .font(.caption).foregroundStyle(.secondary)
            Section("长期事实（最多 50 条）") {
                ForEach(Array(model.data.facts.enumerated()), id: \.offset) { index, fact in
                    HStack { Text(fact); Spacer(); Button("忘记") { model.data.facts.remove(at: index); model.persist() } }
                }
                if model.data.facts.isEmpty { Text("在聊天中说“请记住……”即可添加。").foregroundStyle(.secondary) }
            }
        }
    }
    private func importWindows() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        do {
            let imported = try WindowsImport.read(folder, into: model.data)
            let alert = NSAlert()
            alert.messageText = "导入 Windows 数据？"
            alert.informativeText = "相同日期和聊天 ID 将被替换；导入前会保留完整备份。"
            alert.addButton(withTitle: "导入")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let backup = model.store.directory.appendingPathComponent("before-import-\(UUID().uuidString).json")
            try DataStore.encoder.encode(model.data).write(to: backup, options: .atomic)
            try model.store.save(imported)
            model.data = imported
            draft = SettingsDraft(imported.settings)
            model.endAppearancePreview()
            model.paused = true
            model.changeSettings { _ in }
            model.say("Windows 数据已导入。")
        } catch { model.error = error.localizedDescription }
    }
}

@MainActor struct CodexSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var client: CodexClient
    @Binding var settings: Settings
    @State private var loading = false
    private func perform(_ operation: @escaping () async throws -> Void) {
        loading = true
        Task {
            defer { loading = false }
            do { try await operation() } catch { model.error = error.localizedDescription }
        }
    }
    var body: some View {
        Text(client.account).textSelection(.enabled)
        HStack {
            Button(client.loginPending ? "重新打开登录" : "连接我的 ChatGPT") { perform { try await client.login() } }
            Button("刷新账号和模型") { perform { try await client.refresh() } }
            Button("退出登录") { perform { try await client.logout() } }.disabled(!client.signedIn)
            if loading { ProgressView().controlSize(.small) }
        }.disabled(loading || model.busy)
        Picker("模型", selection: Binding(get: { settings.codexModel }, set: { value in
            settings.codexModel = value; settings.reasoning = ""
        })) {
            Text("自动选择").tag("")
            ForEach(client.models) { Text($0.name).tag($0.id) }
        }.disabled(model.busy)
        Picker("推理强度", selection: Binding(get: { settings.reasoning }, set: { value in settings.reasoning = value })) {
            Text("模型默认").tag("")
            ForEach(client.models.first(where: { $0.id == settings.codexModel })?.efforts ?? [], id: \.self) { Text($0).tag($0) }
        }.disabled(model.busy)
    }
}

@MainActor struct ChatView: View {
    @ObservedObject var model: AppModel
    @State var selected: String
    var settings: () -> Void
    var resizeSidebar: (Bool) -> Void
    @State private var sidebar = false
    @State private var archived = false
    @State private var draft = ""
    private var thread: ChatThread? { model.data.threads.first { $0.id == selected } }
    var body: some View {
        HStack(spacing: 14) {
            if sidebar {
                PetCard {
                    HStack {
                        Text("聊天").font(.title3.bold()); Spacer()
                        Button { toggleSidebar() } label: { Image(systemName: "sidebar.left") }.help("收起聊天列表").accessibilityLabel("收起聊天列表")
                    }
                    Text("选择一个聊天继续").font(.caption).foregroundStyle(PetTheme.muted)
                    Button { selected = model.newChat(); draft = "" } label: { Text("＋ 新聊天").frame(maxWidth: .infinity) }
                        .buttonStyle(PetButtonStyle(primary: true)).disabled(model.busy)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最近").font(.caption.bold()).foregroundStyle(PetTheme.muted)
                            threadList(archived: false)
                            DisclosureGroup("已归档", isExpanded: $archived) { threadList(archived: true) }
                        }
                    }
                }.frame(width: 205)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if !sidebar { Button { toggleSidebar() } label: { Image(systemName: "sidebar.left") }.help("展开聊天列表").accessibilityLabel("展开聊天列表") }
                    Text(thread?.title ?? "新聊天").font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Button(thread?.archived == true ? "恢复" : "归档") { model.archive(selected) }.disabled(model.busy || thread == nil)
                    Button(action: settings) { Image(systemName: "gearshape") }.help("打开设置").accessibilityLabel("打开设置")
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if thread?.messages.isEmpty != false {
                                Text("今天想聊些什么？").foregroundStyle(PetTheme.muted).frame(maxWidth: .infinity).padding(.top, 30)
                            }
                            ForEach(thread?.messages ?? []) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 25) }
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(message.role == "user" ? "你" : model.data.settings.petName).font(.caption.bold())
                                            Spacer()
                                            ChatCopyButton(content: message.content, onDark: message.role == "user")
                                        }
                                        if message.role == "user" {
                                            Text(message.content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            ChatMessageBody(content: message.content)
                                        }
                                    }.padding(12).foregroundStyle(message.role == "user" ? Color.white : PetTheme.ink)
                                        .background(message.role == "user" ? PetTheme.accent : PetTheme.soft, in: RoundedRectangle(cornerRadius: 10))
                                    if message.role != "user" { Spacer(minLength: 25) }
                                }.id(message.id)
                            }
                            if model.busy { ProgressView("正在回复…") }
                        }.padding(12)
                    }.onChange(of: thread?.messages.count) { _, _ in
                        if let last = thread?.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PetTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(PetTheme.border))
                HStack(spacing: 10) {
                    Composer(text: $draft, send: send).frame(height: 75)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PetTheme.border))
                        .disabled(model.busy)
                        .help("Enter 发送，Shift+Enter 换行")
                    VStack(spacing: 6) {
                        Button("发送", action: send).buttonStyle(PetButtonStyle(primary: true))
                            .disabled(model.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Toggle("看屏幕", isOn: Binding(get: { model.data.settings.screenVision }, set: { value in model.changeSettings { $0.screenVision = value } }))
                            .toggleStyle(.switch).controlSize(.mini).font(.caption).disabled(model.busy)
                        if model.busy { Button("取消") { model.ai.codex.shutdown() }.disabled(model.data.settings.provider != "codex") }
                    }
                }.padding(10).background(PetTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(PetTheme.border))
            }.frame(minWidth: 360)
        }.padding(18).frame(minWidth: sidebar ? 615 : 396, minHeight: 370).petPage()
    }
    private func toggleSidebar() { sidebar.toggle(); resizeSidebar(sidebar) }
    private func threadList(archived: Bool) -> some View {
        ForEach(model.data.threads.filter { $0.archived == archived }.sorted { $0.updated > $1.updated }) { item in
            Button { selected = item.id; draft = "" } label: {
                Text(item.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(selected == item.id ? PetTheme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).disabled(model.busy)
                .contextMenu { Button(item.archived ? "恢复" : "归档") { model.archive(item.id) }.disabled(model.busy) }
        }
    }
    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.busy else { return }
        let id = selected
        draft = ""
        Task { await model.send(text, threadID: id) }
    }
}

@MainActor struct Composer: NSViewRepresentable {
    @Binding var text: String
    var send: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let editor = SendTextView()
        editor.isRichText = false
        editor.font = .systemFont(ofSize: 14)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.send = send
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = view.documentView as? SendTextView else { return }
        editor.synchronizeDraft(text)
        editor.send = send
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Composer
        init(_ parent: Composer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}
final class SendTextView: NSTextView {
    var send: (() -> Void)?
    func synchronizeDraft(_ text: String) {
        // SwiftUI can refresh while the input method owns uncommitted pinyin.
        // Replacing string then discards the marked text and candidate selection.
        guard !hasMarkedText(), string != text else { return }
        string = text
    }
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76) && !event.modifierFlags.contains(.shift) && !hasMarkedText() { send?() }
        else { super.keyDown(with: event) }
    }
}
