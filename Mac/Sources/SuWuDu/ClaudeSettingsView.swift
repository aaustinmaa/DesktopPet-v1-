import SwiftUI
import AppKit

@MainActor struct ClaudeSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var client: ClaudeClient
    @Binding var settings: Settings
    @State private var operation: Operation?
    @State private var operationTask: Task<Void, Never>?
    @State private var operationID: UUID?

    private enum Operation { case refresh, login, logout }
    private var requestActive: Bool { model.busy || model.matchingBusy || model.memoExtractionBusy }
    private var controlsDisabled: Bool { operation != nil || client.loginPending || requestActive }
    private var selectedModel: String { settings.claudeModel ?? "" }
    private var selectedEffort: String { settings.claudeEffort ?? "" }
    private var efforts: [String] { client.models.first(where: { $0.id == selectedModel })?.efforts ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(client.account).textSelection(.enabled)
            HStack {
                Group {
                    Button("连接我的 Claude") { perform(.login) { try await client.login() } }
                    Button("刷新账号和模型") { perform(.refresh) { try await client.refresh() } }
                    Button("退出登录") { perform(.logout) { try await client.logout() } }
                        .disabled(!client.signedIn)
                }.disabled(controlsDisabled)
                if operation != nil { ProgressView().controlSize(.small) }
                if operation == .login {
                    Button("取消") { cancelOperation() }
                }
            }
            Picker("模型", selection: Binding(get: { selectedModel }, set: { value in
                settings.claudeModel = value.isEmpty ? nil : value
                settings.claudeEffort = nil
            })) {
                Text(client.models.first(where: { $0.id.isEmpty })?.pickerLabel ?? "自动选择").tag("")
                ForEach(client.models.filter { !$0.id.isEmpty }) { Text($0.pickerLabel).tag($0.id) }
                if !selectedModel.isEmpty && !client.models.contains(where: { $0.id == selectedModel }) {
                    Text("\(selectedModel)（当前不可用）").tag(selectedModel).disabled(true)
                }
            }.disabled(controlsDisabled)
            Picker("推理强度", selection: Binding(get: { selectedEffort }, set: { value in
                settings.claudeEffort = value.isEmpty ? nil : value
            })) {
                Text("模型默认").tag("")
                ForEach(efforts, id: \.self) { Text($0).tag($0) }
                if !selectedEffort.isEmpty && !efforts.contains(selectedEffort) {
                    Text("\(selectedEffort)（当前不可用）").tag(selectedEffort).disabled(true)
                }
            }.disabled(controlsDisabled)
        }
        .task { perform(.refresh) { try await client.refresh() } }
        .onDisappear { cancelOperation() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if (notification.object as? NSWindow)?.identifier?.rawValue == "settings" { cancelOperation() }
        }
    }

    private func perform(_ kind: Operation, _ action: @escaping () async throws -> Void) {
        guard operation == nil, !client.loginPending, !requestActive else { return }
        let id = UUID()
        operationID = id
        operation = kind
        operationTask = Task { @MainActor in
            defer {
                if operationID == id {
                    operation = nil
                    operationTask = nil
                    operationID = nil
                }
            }
            do { try await action() }
            catch is CancellationError { }
            catch {
                if !Task.isCancelled { model.error = error.localizedDescription }
            }
        }
    }

    private func cancelOperation() {
        operationTask?.cancel()
        if operation == .login { client.cancelLogin() }
        operationID = nil
        operation = nil
        operationTask = nil
    }
}
