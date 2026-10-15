import SwiftUI
import AppKit

@MainActor struct ClaudeSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var client: ClaudeClient
    @State private var operation: Operation?
    @State private var operationTask: Task<Void, Never>?
    @State private var operationID: UUID?

    private enum Operation { case refresh, login, logout }
    private var requestActive: Bool { model.busy || model.matchingBusy || model.memoExtractionBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(client.account).textSelection(.enabled)
            HStack {
                Group {
                    Button("连接我的 Claude") { perform(.login) { try await client.login() } }
                    Button("刷新账号") { perform(.refresh) { try await client.refresh() } }
                    Button("退出登录") { perform(.logout) { try await client.logout() } }
                        .disabled(!client.signedIn)
                }.disabled(operation != nil || client.loginPending || requestActive)
                if operation != nil { ProgressView().controlSize(.small) }
                if operation == .login {
                    Button("取消") { cancelOperation() }
                }
            }
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
