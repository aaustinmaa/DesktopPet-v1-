import AppKit
import Foundation

struct CompanionReply {
    var text: String
    var state: PetState = .happy
    static func parse(_ raw: String) -> CompanionReply {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") { candidate = String(trimmed[start...end]) }
        else { candidate = trimmed }
        if let json = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)) as? [String: Any], let reply = json["reply"] as? String {
            let action = json["action"] as? String
            let state = action == "wave" ? PetState.waving : action == "heart" ? .heart : PetState(rawValue: (json["emotion"] as? String) ?? "happy") ?? .happy
            return CompanionReply(text: reply, state: state)
        }
        return CompanionReply(text: trimmed)
    }
}

@MainActor final class AIService {
    let codex = CodexClient()
    static func instructions(_ name: String) -> String {
        "You are \(name), a warm pixel-art desktop companion. Reply in the user's language, concisely and naturally. " +
        "Never execute commands, inspect files, browse, or call tools. Local memory is private context. " +
        "Return JSON with reply (text), emotion (idle,happy,working,question,success,error,sleeping,reminder,waving,heart), " +
        "and action (none,bounce,wave,heart)."
    }
    func reply(text: String, context: String, settings: Settings, screenshot: URL?, memoryReply: String?) async throws -> CompanionReply {
        if settings.provider == "offline" {
            if let memoryReply { return CompanionReply(text: memoryReply) }
            if text.contains("累") || text.lowercased().contains("tired") { return CompanionReply(text: "辛苦啦。喝点水，伸个懒腰，我陪你慢慢来。", state: .heart) }
            return CompanionReply(text: ["我在这里陪你。今天想先做哪一件小事？", "一步一步来，你已经在前进啦。", "收到！要不要一起开始一轮专注？"].randomElement()!)
        }
        let prompt = "[本地聊天与记忆]\n\(context)\n[当前消息]\n\(text)"
        if settings.provider == "codex" {
            return CompanionReply.parse(try await codex.reply(prompt, settings: settings, screenshot: screenshot))
        }
        let key = try Keychain.read()
        guard !key.isEmpty else { throw AppError.message("请在设置中填写 OpenAI API key。") }
        guard !settings.apiModel.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.message("请在设置中填写账号可用的 API 模型名称。") }
        var content: [[String: Any]] = [["type": "input_text", "text": prompt]]
        if let screenshot {
            content.append(["type": "input_image", "image_url": "data:image/jpeg;base64," + (try Data(contentsOf: screenshot)).base64EncodedString()])
        }
        let body: [String: Any] = ["model": settings.apiModel, "instructions": Self.instructions(settings.petName),
                                   "input": [["role": "user", "content": content]], "store": false]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
            throw AppError.message(((object["error"] as? [String: Any])?["message"] as? String) ?? "OpenAI 请求失败。")
        }
        let output = (object["output"] as? [[String: Any]]) ?? []
        let text = output.flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
            .filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.isEmpty else { throw AppError.message("AI 没有返回可显示的回复。") }
        return CompanionReply.parse(text)
    }
}

struct CodexModel: Identifiable {
    let id: String
    let name: String
    let efforts: [String]
}

@MainActor final class CodexClient: ObservableObject {
    @Published var account = "尚未检查登录状态"
    @Published var signedIn = false
    @Published var models: [CodexModel] = []
    @Published var loginPending = false
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var ready = false
    private var starting: Task<Void, Error>?
    private var activeThread: String?
    private var turnResult: Result<String, Error>?
    private var turnWaiter: CheckedContinuation<String, Error>?
    private var turnText = ""
    private var turnTimeout: Task<Void, Never>?

    func start() async throws {
        if ready { return }
        if let starting { return try await starting.value }
        let task = Task { @MainActor in try await self.launch() }
        starting = task
        defer { starting = nil }
        try await task.value
    }
    private func launch() async throws {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Codex/codex")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppError.message("此构建未包含 Mac Codex 运行组件。请按 Mac/README.md 构建完整版，或在设置中选择离线陪伴 / OpenAI API。")
        }
        let home = DataStore.applicationDirectory.appendingPathComponent("Codex", isDirectory: true)
        let workspace = DataStore.applicationDirectory.appendingPathComponent("CompanionWorkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let task = Process()
        task.executableURL = executable
        task.arguments = ["app-server", "-c", "cli_auth_credentials_store=\"keyring\"", "-c", "web_search=\"disabled\"", "-c", "features.shell_tool=false"]
        task.currentDirectoryURL = workspace
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = home.path
        env["CODEX_SQLITE_HOME"] = home.path
        task.environment = env
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = stderr
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        errors = stderr.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { return }
            DispatchQueue.main.async { self?.receive(bytes) }
        }
        // Drain stderr to avoid blocking the child; do not persist auth or conversation diagnostics.
        errors?.readabilityHandler = { handle in _ = handle.availableData }
        task.terminationHandler = { [weak self] exited in
            DispatchQueue.main.async {
                guard self?.process === exited else { return }
                self?.shutdown(reason: AppError.message("Codex 已停止。请重新连接 ChatGPT。"))
            }
        }
        process = task
        do {
            try task.run()
            _ = try await rpc("initialize", ["clientInfo": ["name": "su_wu_du_mac", "title": "SuWuDu", "version": "1.0.0"]])
            try write(["method": "initialized", "params": [:]])
            ready = true
        } catch { shutdown(reason: error); throw error }
    }
    func refresh() async throws {
        try await start()
        let result = try await rpc("account/read", ["refreshToken": false])
        let value = result["account"] as? [String: Any]
        signedIn = value != nil
        account = (value?["email"] as? String) ?? (signedIn ? "已连接 ChatGPT" : "尚未登录")
        guard signedIn else { models = []; return }
        var loaded: [CodexModel] = []
        var cursor: String?
        repeat {
            var params: [String: Any] = ["limit": 100]
            if let cursor { params["cursor"] = cursor }
            let page = try await rpc("model/list", params)
            loaded += ((page["data"] as? [[String: Any]]) ?? []).compactMap {
                guard let id = ($0["model"] as? String) ?? $0["id"] as? String else { return nil }
                let efforts = (($0["supportedReasoningEfforts"] as? [[String: Any]]) ?? []).compactMap { $0["reasoningEffort"] as? String }
                return CodexModel(id: id, name: ($0["displayName"] as? String) ?? id, efforts: efforts)
            }
            cursor = page["nextCursor"] as? String
        } while cursor != nil
        models = loaded
    }
    func login() async throws {
        try await start()
        let result = try await rpc("account/login/start", ["type": "chatgpt"])
        guard let text = result["authUrl"] as? String, let url = URL(string: text), url.scheme == "https" else {
            throw AppError.message("登录服务没有返回有效的授权地址。")
        }
        loginPending = true
        NSWorkspace.shared.open(url)
    }
    func logout() async throws {
        try await start()
        _ = try await rpc("account/logout", [:])
        signedIn = false
        account = "已退出登录"
        models = []
        loginPending = false
    }
    func reply(_ text: String, settings: Settings, screenshot: URL?) async throws -> String {
        try await refresh()
        guard signedIn else { throw AppError.message("请先在设置中连接 ChatGPT。") }
        guard activeThread == nil else { throw AppError.message("请等待上一条回复完成。") }
        let workspace = DataStore.applicationDirectory.appendingPathComponent("CompanionWorkspace")
        var params: [String: Any] = ["cwd": workspace.path, "sandbox": "read-only", "approvalPolicy": "never",
                                   "baseInstructions": AIService.instructions(settings.petName), "serviceName": "su-wu-du-mac"]
        if !settings.codexModel.isEmpty {
            guard models.contains(where: { $0.id == settings.codexModel }) else { throw AppError.message("所选模型当前不可用，请在设置中刷新模型列表。") }
            params["model"] = settings.codexModel
        }
        let threadResult = try await rpc("thread/start", params)
        guard let id = (threadResult["thread"] as? [String: Any])?["id"] as? String else { throw AppError.message("Codex 未返回聊天编号。") }
        activeThread = id
        turnResult = nil
        turnText = ""
        defer { activeThread = nil; turnTimeout?.cancel(); turnTimeout = nil }
        var content: [[String: Any]] = [["type": "text", "text": text, "textElements": []]]
        if let screenshot { content.append(["type": "localImage", "path": screenshot.path]) }
        let schema: [String: Any] = ["type": "object", "properties": ["reply": ["type": "string"], "emotion": ["type": "string"], "action": ["type": "string"]],
                                     "required": ["reply", "emotion", "action"], "additionalProperties": false]
        var turn: [String: Any] = ["threadId": id, "input": content, "outputSchema": schema]
        if !settings.reasoning.isEmpty { turn["effort"] = settings.reasoning }
        _ = try await rpc("turn/start", turn)
        turnTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
            self?.shutdown(reason: AppError.message("等待 AI 回复超时，请重试。"))
        }
        let result: String
        if let completed = turnResult { result = try completed.get() }
        else { result = try await withCheckedThrowingContinuation { turnWaiter = $0 } }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("Codex 没有返回可显示的回复。") }
        // Each request carries bounded local context; retire the server-side thread after completion.
        _ = try? await rpc("thread/archive", ["threadId": id])
        return result
    }
    private func rpc(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try write(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 45_000_000_000) } catch { return }
                self?.pending.removeValue(forKey: id)?.resume(throwing: AppError.message("Codex 请求超时：\(method)"))
                self?.timeouts.removeValue(forKey: id)
            }
        }
    }
    private func write(_ object: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw AppError.message("Codex 进程未启动。") }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.write(contentsOf: data)
    }
    private func receive(_ bytes: Data) {
        buffer.append(bytes)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let method = object["method"] as? String {
                if let id = object["id"] {
                    try? write(["id": id, "error": ["code": -32000, "message": "Desktop companion does not authorize tool execution."]])
                    continue
                }
                notification(method, (object["params"] as? [String: Any]) ?? [:])
            } else if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                timeouts.removeValue(forKey: id)?.cancel()
                if let error = object["error"] as? [String: Any] { continuation.resume(throwing: AppError.message((error["message"] as? String) ?? "Codex 请求失败")) }
                else { continuation.resume(returning: (object["result"] as? [String: Any]) ?? [:]) }
            }
        }
    }
    private func notification(_ method: String, _ params: [String: Any]) {
        if method == "account/login/completed" {
            loginPending = false
            if params["success"] as? Bool == true {
                Task { do { try await refresh() } catch { account = error.localizedDescription } }
            } else { account = (params["error"] as? String) ?? "登录失败，请重试。" }
            return
        }
        guard let activeThread, params["threadId"] as? String == activeThread else { return }
        switch method {
        case "item/agentMessage/delta": turnText += (params["delta"] as? String) ?? ""
        case "item/completed":
            if let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage", let text = item["text"] as? String { turnText = text }
        case "turn/completed":
            let turn = (params["turn"] as? [String: Any]) ?? [:]
            if turn["status"] as? String == "completed" { finish(.success(turnText)) }
            else { finish(.failure(AppError.message(((turn["error"] as? [String: Any])?["message"] as? String) ?? "生成回复失败或被中断。"))) }
        default: break
        }
    }
    private func finish(_ result: Result<String, Error>) {
        turnResult = result
        turnWaiter?.resume(with: result)
        turnWaiter = nil
    }
    func shutdown(reason: Error = AppError.message("聊天已取消。")) {
        ready = false
        output?.readabilityHandler = nil
        errors?.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        try? input?.close()
        try? output?.close()
        try? errors?.close()
        input = nil; output = nil; errors = nil
        buffer.removeAll()
        for timeout in timeouts.values { timeout.cancel() }
        timeouts.removeAll()
        let waiting = pending.values
        pending.removeAll()
        for continuation in waiting { continuation.resume(throwing: reason) }
        if activeThread != nil { finish(.failure(reason)) }
        loginPending = false
    }
}
