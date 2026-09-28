import Foundation

enum PetState: String, Codable, CaseIterable {
    case idle, blink, happy, working, question, success, error, sleeping, reminder, waving, heart, hit
}

struct Settings: Codable, Equatable {
    var petName = "苏无度"
    var skin = "suwudu"
    var scale = 0.82
    var topmost = true
    var allSpaces = true
    var wander = false
    var wanderMin = 8
    var wanderMax = 18
    var hydration = true
    var hydrationMinutes = 45
    var focusMinutes = 25
    var breakMinutes = 5
    var startSound = "gentle"
    var finishSound = "bell"
    var breakSound = "bell"
    var microbreaks = true
    var microMin = 3
    var microMax = 5
    var microSeconds = 10
    var microStartSound = "bell"
    var microEndSound = "pixel"
    var provider = "codex"
    var apiModel = ""
    var codexModel = ""
    var reasoning = ""
    var memory = true
    var screenVision = true
    var windowX: Double?
    var windowY: Double?
    var firstRun = true

    mutating func normalize() {
        scale = scale.isFinite ? min(1.5, max(0.2, scale)) : 0.82
        focusMinutes = min(120, max(1, focusMinutes))
        breakMinutes = min(120, max(1, breakMinutes))
        hydrationMinutes = min(240, max(10, hydrationMinutes))
        wanderMin = min(300, max(3, wanderMin))
        wanderMax = min(300, max(wanderMin, wanderMax))
        microMin = min(120, max(1, microMin))
        microMax = min(120, max(microMin, microMax))
        microSeconds = min(300, max(1, microSeconds))
        if !["suwudu", "shenqing"].contains(skin) { skin = "suwudu" }
        if !["codex", "openai", "offline"].contains(provider) { provider = "offline" }
        if windowX?.isFinite == false { windowX = nil }
        if windowY?.isFinite == false { windowY = nil }
    }
}

struct FocusSegment: Codable, Equatable {
    var start: Date
    var end: Date
    var seconds: Double { max(0, end.timeIntervalSince(start)) }
}

enum MicrobreakSchedule {
    static func next(settings: Settings, remaining: Double) -> Double? {
        let delay = Double(Int.random(in: settings.microMin * 60...settings.microMax * 60))
        return delay + Double(settings.microSeconds) < remaining ? delay : nil
    }
}

struct FocusSession: Codable, Identifiable {
    var id = UUID().uuidString
    var source = "automatic"
    var startedAt = Date()
    var completedAt = Date()
    var minutes = 25
    var countsTowardGoal = true
    var notes = ""
}

struct JournalDay: Codable, Identifiable {
    var date: String
    var target = 0
    var adjustment = 0
    var notes = ""
    var sessions: [FocusSession] = []
    var id: String { date }
    var count: Int { sessions.filter(\.countsTowardGoal).count }
    var total: Int { sessions.filter(\.countsTowardGoal).reduce(adjustment) { $0 + $1.minutes } }

    mutating func settle(minutes: Int, calendar: Calendar = .current) {
        guard minutes > 0 else { return }
        while adjustment < 0 {
            let candidates = sessions.indices.reversed().filter {
                sessions[$0].countsTowardGoal && sessions[$0].minutes > 0
            }
            guard let index = candidates.first(where: { sessions[$0].minutes == minutes }) ?? candidates.first else { break }
            sessions[index].countsTowardGoal = false
            adjustment += sessions[index].minutes
        }
        let completion = date == FocusAccounting.key(Date(), calendar: calendar) ? Date() : FocusAccounting.date(from: date, calendar: calendar) ?? Date()
        while adjustment >= minutes {
            sessions.append(FocusSession(source: "manual", startedAt: completion.addingTimeInterval(-Double(minutes * 60)),
                                         completedAt: completion, minutes: minutes, notes: "由今日分钟调整自动换算"))
            adjustment -= minutes
        }
    }
}

enum FocusAccounting {
    static func key(_ instant: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: instant)
        let boundary = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day)!
        let journalDate = instant >= boundary ? calendar.date(byAdding: .day, value: 1, to: day)! : day
        let parts = calendar.dateComponents([.year, .month, .day], from: journalDate)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func allocate(_ segments: [FocusSegment], minutes: Int, calendar: Calendar = .current) -> [String: Int] {
        guard minutes > 0 else { return [:] }
        var seconds: [String: Double] = [:]
        for segment in segments where segment.end > segment.start {
            var cursor = segment.start
            while cursor < segment.end {
                let day = calendar.startOfDay(for: cursor)
                var boundary = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day)!
                if boundary <= cursor { boundary = calendar.date(byAdding: .day, value: 1, to: boundary)! }
                let end = min(boundary, segment.end)
                seconds[key(cursor, calendar: calendar), default: 0] += end.timeIntervalSince(cursor)
                cursor = end
            }
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [:] }
        var result = seconds.mapValues { Int(floor(Double(minutes) * $0 / total)) }
        let order = seconds.keys.sorted {
            let left = Double(minutes) * seconds[$0]! / total - Double(result[$0]!)
            let right = Double(minutes) * seconds[$1]! / total - Double(result[$1]!)
            return left == right ? $0 < $1 : left > right
        }
        for date in order.prefix(minutes - result.values.reduce(0, +)) { result[date, default: 0] += 1 }
        return result.filter { $0.value > 0 }
    }

    static func record(segments: [FocusSegment], planned: Int, completed: Bool, startedAt: Date,
                       endedAt: Date, journal: inout [JournalDay]) {
        let minutes = completed ? planned : min(planned, Int(segments.reduce(0) { $0 + $1.seconds } / 60))
        let allocations = allocate(segments, minutes: minutes)
        var affected = Set(allocations.keys)
        let completionKey = key(endedAt)
        if completed { affected.insert(completionKey) }
        for date in affected.sorted() {
            if !journal.contains(where: { $0.date == date }) { journal.append(JournalDay(date: date)) }
            let i = journal.firstIndex(where: { $0.date == date })!
            journal[i].adjustment += allocations[date, default: 0]
            if completed && date == completionKey {
                journal[i].sessions.append(FocusSession(startedAt: startedAt, completedAt: endedAt, minutes: planned))
                journal[i].adjustment -= planned
            }
            journal[i].settle(minutes: planned)
        }
        journal.sort { $0.date < $1.date }
    }
}

struct FocusRun: Codable {
    var startedAt: Date
    var planned: Int
    var remaining: Double
    var segments: [FocusSegment] = []
    var microRemaining: Double?
    var nextMicro: Double?
}

struct ChatMessage: Codable, Identifiable {
    var id = UUID().uuidString
    var role: String
    var content: String
    var date = Date()
}
struct ChatThread: Codable, Identifiable {
    var id = UUID().uuidString
    var title = "新聊天"
    var summary = ""
    var updated = Date()
    var archived = false
    var messages: [ChatMessage] = []
}
struct AppData: Codable {
    var version = 1
    var settings = Settings()
    var journal: [JournalDay] = []
    var focus: FocusRun?
    var threads: [ChatThread] = []
    var facts: [String] = []
}

enum LocalMemory {
    static func process(_ message: String, facts: inout [String]) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["请忘记", "忘记：", "忘记:", "please forget ", "forget "] {
            if trimmed.lowercased().hasPrefix(prefix) {
                let fact = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fact.isEmpty else { return nil }
                facts.removeAll { $0.localizedCaseInsensitiveContains(fact) }
                return "已经忘记这条长期记忆。"
            }
        }
        for prefix in ["请记住", "帮我记住", "记住：", "记住:", "记住 ", "please remember ", "remember that ", "remember "] {
            if trimmed.lowercased().hasPrefix(prefix) {
                let fact = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ：:\n\t"))
                guard !fact.isEmpty else { return nil }
                if !facts.contains(where: { $0.caseInsensitiveCompare(fact) == .orderedSame }) { facts.append(fact) }
                facts = Array(facts.suffix(50))
                return "记住了：\(fact)"
            }
        }
        return nil
    }

    static func context(thread: ChatThread, threads: [ChatThread], facts: [String], enabled: Bool) -> String {
        let recent = thread.messages.suffix(24).map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        guard enabled else { return recent }
        let summaries = threads.filter { $0.id != thread.id && !$0.archived }
            .sorted { $0.updated > $1.updated }.prefix(5).map(\.summary).filter { !$0.isEmpty }.joined(separator: "\n")
        return "长期事实:\n\(facts.joined(separator: "\n"))\n其他聊天摘要:\n\(summaries)\n当前聊天:\n\(recent)"
    }
}

struct AnimationSpec {
    var frames: [String]
    var interval: Double
    var once = false
    static func sequence(_ prefix: String, _ count: Int) -> [String] {
        (1...count).map { String(format: "%@-%02d.png", prefix, $0) }
    }
    static func make(_ state: PetState, skin: String) -> AnimationSpec {
        let shen = skin == "shenqing"
        func frames(_ mac: String, _ count: Int, _ shenName: String, _ shenCount: Int) -> [String] {
            sequence(shen ? "shenqing-" + shenName : mac, shen ? shenCount : count)
        }
        switch state {
        case .idle: return .init(frames: frames("idle-open-close-v5", 16, "idle", 8), interval: 0.170)
        case .blink: return .init(frames: frames("blink-v2", 8, "blink", 8), interval: 0.165, once: true)
        case .happy: return .init(frames: [shen ? "shenqing-success-03.png" : "happy.png"], interval: 0.15)
        case .question: return .init(frames: [shen ? "shenqing-idle-01.png" : "question.png"], interval: 0.15)
        case .working:
            var list = frames("working-float-v3", 16, "working", 16)
            if !shen { list += sequence("working-float-v3", 15).dropFirst().reversed() }
            return .init(frames: list, interval: 0.05)
        case .success: return .init(frames: frames("success-v2", 16, "success", 8), interval: 0.095)
        case .error: return .init(frames: frames("error-v4", 16, "error", 8), interval: 0.125)
        case .sleeping: return .init(frames: shen ? sequence("shenqing-sleeping", 8) : ["sleeping-base.png"], interval: 0.15)
        case .reminder: return .init(frames: frames("reminder-v2", 16, "reminder", 8), interval: 0.09)
        case .waving: return .init(frames: frames("wave-v2", 8, "wave", 8), interval: 0.105)
        case .heart:
            var list = frames("heart-lift-v3", 8, "heart", 8)
            if !shen { list += sequence("heart-lift-v3", 7).reversed() }
            return .init(frames: list, interval: 0.115, once: true)
        case .hit: return .init(frames: frames("idle-hit-v1", 16, "error", 8), interval: 0.075, once: true)
        }
    }
}

enum AppError: LocalizedError {
    case message(String)
    case unsupportedVersion(Int)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .unsupportedVersion(let version): return "不支持的数据版本 \(version)。请使用更新版本的桌宠。原数据未被修改。"
        }
    }
}
