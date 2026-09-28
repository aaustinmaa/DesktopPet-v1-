import Foundation

struct DataStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("app-state.json") }
    static var applicationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SuWuDu", isDirectory: true)
    }
    init(directory: URL = DataStore.applicationDirectory) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var value = encoder.singleValueContainer()
            try value.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            let text = try value.decode(String.self)
            guard let date = WindowsImport.parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid ISO-8601 timestamp")
            }
            return date
        }
        return decoder
    }
    func load() throws -> (AppData, String?) {
        guard FileManager.default.fileExists(atPath: file.path) else { return (AppData(), nil) }
        do { return (try decode(file), nil) }
        catch AppError.unsupportedVersion(let version) { throw AppError.unsupportedVersion(version) }
        catch {
            let backup = file.appendingPathExtension("backup")
            guard let recovered = try? decode(backup) else {
                throw AppError.message("无法读取本地数据及备份。原文件已保留：\(file.path)\n\(error.localizedDescription)")
            }
            // Keep the corrupt original for diagnosis, and restore a valid primary before future writes.
            let preserved = directory.appendingPathComponent("app-state-corrupt-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: file, to: preserved)
            try Data(contentsOf: backup).write(to: file, options: .atomic)
            return (recovered, "已从备份恢复数据；损坏文件已保留。")
        }
    }
    private func decode(_ url: URL) throws -> AppData {
        let bytes = try Data(contentsOf: url)
        if let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let version = object["version"] as? Int, version != 1 {
            throw AppError.unsupportedVersion(version)
        }
        var result = try Self.decoder.decode(AppData.self, from: bytes)
        guard result.version == 1 else { throw AppError.unsupportedVersion(result.version) }
        result.settings.normalize()
        return result
    }
    func save(_ data: AppData) throws {
        let encoded = try Self.encoder.encode(data)
        if FileManager.default.fileExists(atPath: file.path) {
            try Data(contentsOf: file).write(to: file.appendingPathExtension("backup"), options: .atomic)
        }
        try encoded.write(to: file, options: .atomic)
    }
}

enum WindowsImport {
    static func read(_ folder: URL, into original: AppData) throws -> AppData {
        var result = original
        var found = false
        func object(_ name: String) throws -> [String: Any]? {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            found = true
            guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw AppError.message("无效的 Windows 数据：\(name)")
            }
            return value
        }
        if let s = try object("settings.json") {
            var value = result.settings
            value.petName = (s["PetName"] as? String) ?? value.petName
            value.skin = (s["PetSkin"] as? String) ?? value.skin
            value.scale = (s["PetScale"] as? Double) ?? value.scale
            value.topmost = (s["Topmost"] as? Bool) ?? value.topmost
            value.wander = (s["AutoWander"] as? Bool) ?? value.wander
            value.wanderMin = (s["WanderMinIdleSeconds"] as? Int) ?? value.wanderMin
            value.wanderMax = (s["WanderMaxIdleSeconds"] as? Int) ?? value.wanderMax
            value.hydration = (s["HydrationEnabled"] as? Bool) ?? value.hydration
            value.hydrationMinutes = (s["HydrationMinutes"] as? Int) ?? value.hydrationMinutes
            value.focusMinutes = (s["FocusMinutes"] as? Int) ?? value.focusMinutes
            value.breakMinutes = (s["BreakMinutes"] as? Int) ?? value.breakMinutes
            value.startSound = (s["FocusStartSound"] as? String) ?? value.startSound
            value.finishSound = (s["FocusCompleteSound"] as? String) ?? value.finishSound
            value.breakSound = (s["BreakCompleteSound"] as? String) ?? value.breakSound
            value.microbreaks = (s["RandomCueEnabled"] as? Bool) ?? value.microbreaks
            value.microMin = (s["RandomCueMinMinutes"] as? Int) ?? value.microMin
            value.microMax = (s["RandomCueMaxMinutes"] as? Int) ?? value.microMax
            value.microSeconds = (s["RandomCueBreakSeconds"] as? Int) ?? value.microSeconds
            value.microStartSound = (s["RandomCueBreakSound"] as? String) ?? value.microStartSound
            value.microEndSound = (s["RandomCueResumeSound"] as? String) ?? value.microEndSound
            value.provider = (s["AiProvider"] as? String) ?? value.provider
            value.apiModel = (s["AiModel"] as? String) ?? value.apiModel
            value.codexModel = (s["CodexModel"] as? String) ?? value.codexModel
            value.reasoning = (s["CodexReasoningEffort"] as? String) ?? value.reasoning
            value.memory = (s["MemoryEnabled"] as? Bool) ?? value.memory
            value.screenVision = (s["ScreenVisionEnabled"] as? Bool) ?? value.screenVision
            value.normalize()
            result.settings = value
        }
        if let source = try object("focus-journal.json") {
            guard let days = source["Days"] as? [[String: Any]] else { throw AppError.message("专注记录缺少 Days。") }
            for d in days {
                guard let date = d["Date"] as? String, FocusAccounting.date(from: date) != nil else { throw AppError.message("无效的记录日期。") }
                let sessions = try ((d["Sessions"] as? [[String: Any]]) ?? []).map { s -> FocusSession in
                    let started = parseDate(s["StartedAt"]) ?? FocusAccounting.date(from: date)!
                    let ended = parseDate(s["CompletedAt"]) ?? started
                    guard let id = s["Id"] as? String else { throw AppError.message("专注记录缺少 Id。") }
                    return FocusSession(id: id, source: (s["Source"] as? String) ?? "manual", startedAt: started,
                        completedAt: ended, minutes: max(0, (s["PlannedMinutes"] as? Int) ?? 0),
                        countsTowardGoal: (s["CountsTowardGoal"] as? Bool) ?? true, notes: (s["Notes"] as? String) ?? "")
                }
                let day = JournalDay(date: date, target: max(0, (d["TargetCount"] as? Int) ?? 0),
                    adjustment: (d["MinuteAdjustment"] as? Int) ?? 0, notes: (d["DailyNotes"] as? String) ?? "", sessions: sessions)
                if let i = result.journal.firstIndex(where: { $0.date == date }) { result.journal[i] = day }
                else { result.journal.append(day) }
            }
        }
        if let source = try object("chat-memory.json") {
            func messages(_ list: [[String: Any]]) -> [ChatMessage] {
                list.map { ChatMessage(role: ($0["Role"] as? String) ?? "user", content: ($0["Content"] as? String) ?? "",
                                       date: parseDate($0["CreatedAtUtc"]) ?? Date()) }
            }
            var threads = (source["Threads"] as? [[String: Any]]) ?? []
            if let old = source["History"] as? [[String: Any]], !old.isEmpty {
                threads.append(["Id": "windows-legacy", "Title": "Windows 历史聊天", "Messages": old])
            }
            for t in threads {
                guard let id = t["Id"] as? String else { throw AppError.message("聊天记录缺少 Id。") }
                let thread = ChatThread(id: id, title: (t["Title"] as? String) ?? "聊天", summary: (t["Summary"] as? String) ?? "",
                    updated: parseDate(t["UpdatedAtUtc"]) ?? Date(), archived: (t["IsArchived"] as? Bool) ?? false,
                    messages: messages((t["Messages"] as? [[String: Any]]) ?? []))
                if let i = result.threads.firstIndex(where: { $0.id == id }) { result.threads[i] = thread }
                else { result.threads.append(thread) }
            }
            for fact in (source["Facts"] as? [[String: Any]]) ?? [] {
                if let text = fact["Text"] as? String, !result.facts.contains(text) { result.facts.append(text) }
            }
            result.facts = Array(result.facts.suffix(50))
        }
        if let f = try object("active-focus.json"), let started = parseDate(f["StartedAt"]), let minutes = f["PlannedMinutes"] as? Int,
           let remaining = f["RemainingSeconds"] as? Double, minutes > 0, minutes <= 120, remaining > 0 {
            let segments = ((f["Segments"] as? [[String: Any]]) ?? []).compactMap { s -> FocusSegment? in
                guard let start = parseDate(s["StartedAt"]), let end = parseDate(s["EndedAt"]), end > start else { return nil }
                return FocusSegment(start: start, end: end)
            }
            result.focus = FocusRun(startedAt: started, planned: minutes, remaining: min(Double(minutes * 60), remaining), segments: segments)
        }
        guard found else { throw AppError.message("此文件夹中没有 Windows 桌宠 JSON 数据。") }
        result.journal.sort { $0.date < $1.date }
        return result
    }
    static func parseDate(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
