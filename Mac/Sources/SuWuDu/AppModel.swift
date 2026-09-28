import AppKit
import Combine

@MainActor final class AppModel: ObservableObject {
    @Published var data: AppData
    @Published var paused = true
    @Published var breakRemaining: Double = 0
    @Published var bubble = ""
    @Published var state: PetState = .idle
    @Published var manualMode: PetState = .idle
    @Published var error: String?
    @Published var clickThrough = false
    @Published var busy = false
    let store: DataStore
    let sound: any SoundPlaying
    let ai = AIService()
    var onSettingsChanged: (() -> Void)?
    var onStateChanged: ((PetState) -> Void)?
    var onWander: (() -> Void)?
    var onBubble: ((String) -> Void)?
    private var timer: Timer?
    private var lastUptime = ProcessInfo.processInfo.systemUptime
    private var lastDate = Date()
    private var saveTicks = 0
    private var temporaryUntil = Date.distantPast
    private var bubbleUntil = Date.distantPast
    private var countdownUntil = Date.distantPast
    private var hydrationAt = Date()
    private var wanderAt = Date()
    private var gestureAt = Date()
    private var wakeHit: Date?
    private var awakeUntil = Date.distantPast

    init(store: DataStore, loaded: AppData, sound: (any SoundPlaying)? = nil) {
        self.store = store
        self.sound = sound ?? SoundService()
        data = loaded
        hydrationAt = Date().addingTimeInterval(Double(data.settings.hydrationMinutes * 60))
        scheduleWander()
        gestureAt = Date().addingTimeInterval(Double.random(in: 12...28))
    }
    func start() {
        lastUptime = ProcessInfo.processInfo.systemUptime
        lastDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if data.focus != nil { say("已恢复未完成的专注，点击继续。") }
    }
    func persist() {
        do { try store.save(data) } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    func changeSettings(_ change: (inout Settings) -> Void) {
        change(&data.settings)
        data.settings.normalize()
        hydrationAt = Date().addingTimeInterval(Double(data.settings.hydrationMinutes * 60))
        scheduleWander()
        if !data.settings.microbreaks { data.focus?.nextMicro = nil; data.focus?.microRemaining = nil }
        else if data.focus != nil && data.focus?.nextMicro == nil && data.focus?.microRemaining == nil { scheduleMicro() }
        persist()
        onSettingsChanged?()
    }
    var focusLabel: String {
        if let run = data.focus {
            let seconds = max(0, Int(ceil(run.remaining)))
            return "\(paused ? "已暂停" : "专注中") \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        }
        if breakRemaining > 0 { return "休息 \(Int(ceil(breakRemaining)) / 60):\(String(format: "%02d", Int(ceil(breakRemaining)) % 60))" }
        return "准备好开始专注"
    }
    var baseState: PetState {
        if let run = data.focus, !paused { return run.microRemaining != nil ? .reminder : .working }
        if breakRemaining > 0 { return .sleeping }
        if manualMode != .idle { return manualMode }
        if Date() > awakeUntil && CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) >= 300 { return .sleeping }
        return .idle
    }
    func animate(_ value: PetState, seconds: Double = 3) {
        state = value
        let spec = AnimationSpec.make(value, skin: data.settings.skin)
        let cycle = Double(spec.frames.count) * spec.interval
        let duration = spec.once ? cycle : spec.frames.count > 1 ? ceil(seconds / cycle) * cycle : seconds
        temporaryUntil = Date().addingTimeInterval(duration)
        onStateChanged?(value)
    }
    func restoreAnimation() {
        temporaryUntil = .distantPast
        state = baseState
        onStateChanged?(state)
    }
    func say(_ text: String, seconds: Double = 5) {
        countdownUntil = .distantPast
        displayBubble(text, seconds: seconds)
    }
    private func displayBubble(_ text: String, seconds: Double) {
        bubble = text
        bubbleUntil = Date().addingTimeInterval(seconds)
        onBubble?(text)
    }
    func notify(_ text: String) {
        say(text)
        Notifications.post(text)
    }
    func setMode(_ mode: PetState) {
        wakeHit = nil
        manualMode = manualMode == mode ? .idle : mode
        restoreAnimation()
    }
    func singleClick() {
        let sleeping = baseState == .sleeping
        if sleeping && breakRemaining == 0 {
            if let prior = wakeHit, Date().timeIntervalSince(prior) < 4 {
                manualMode = .idle
                awakeUntil = Date().addingTimeInterval(300)
                wakeHit = nil
                say("醒啦！")
                animate(.happy)
            } else { wakeHit = Date() }
        } else if state == .idle { animate(.hit, seconds: 1.2) }
        if data.focus != nil || breakRemaining > 0 {
            showCountdown()
        }
    }
    private func showCountdown() {
        countdownUntil = Date().addingTimeInterval(4)
        displayBubble(focusLabel, seconds: 4)
    }
    func toggleFocus() {
        wakeHit = nil
        if data.focus == nil { startFocus() }
        else if paused { resume() }
        else { pause() }
    }
    func startFocus() {
        if data.focus != nil { stopFocus() }
        breakRemaining = 0
        data.focus = FocusRun(startedAt: Date(), planned: data.settings.focusMinutes, remaining: Double(data.settings.focusMinutes * 60))
        paused = false
        lastUptime = ProcessInfo.processInfo.systemUptime
        lastDate = Date()
        scheduleMicro()
        sound.play(data.settings.startSound)
        say("开始 \(data.settings.focusMinutes) 分钟专注。")
        persist()
        restoreAnimation()
    }
    func pause() {
        advanceFocus()
        guard data.focus != nil else { persist(); return }
        paused = true
        say("番茄钟已暂停。\(focusLabel)。", seconds: 4)
        persist()
        restoreAnimation()
    }
    func resume() {
        guard data.focus != nil, paused else { return }
        paused = false
        lastUptime = ProcessInfo.processInfo.systemUptime
        lastDate = Date()
        sound.play(data.settings.startSound)
        showCountdown()
        persist()
        restoreAnimation()
    }
    func stopFocus() {
        advanceFocus()
        guard let run = data.focus else { breakRemaining = 0; restoreAnimation(); return }
        FocusAccounting.record(segments: run.segments, planned: run.planned, completed: false,
                               startedAt: run.startedAt, endedAt: Date(), journal: &data.journal)
        data.focus = nil
        paused = true
        persist() // Journal and recovery state commit together: no double settlement after a crash.
        say("专注已结束，完成的整分钟已记录。")
        restoreAnimation()
    }
    func sleep() {
        pause()
        sound.stop()
    }
    func wake() {
        lastUptime = ProcessInfo.processInfo.systemUptime
        lastDate = Date()
        hydrationAt = Date().addingTimeInterval(Double(data.settings.hydrationMinutes * 60))
        scheduleWander()
    }
    private func scheduleMicro() {
        guard data.settings.microbreaks, let run = data.focus else { return }
        data.focus?.nextMicro = MicrobreakSchedule.next(settings: data.settings, remaining: run.remaining)
    }
    private func scheduleWander() {
        wanderAt = Date().addingTimeInterval(Double.random(in: Double(data.settings.wanderMin)...Double(data.settings.wanderMax)))
    }
    private func advanceFocus() {
        let uptime = ProcessInfo.processInfo.systemUptime
        let now = Date()
        let delta = max(0, uptime - lastUptime)
        defer { lastUptime = uptime; lastDate = now }
        guard var run = data.focus, !paused else { return }
        let elapsed = min(run.remaining, delta)
        guard elapsed > 0 else { return }
        let start = lastDate
        let end = start.addingTimeInterval(elapsed)
        if let last = run.segments.last, abs(last.end.timeIntervalSince(start)) < 0.1 {
            run.segments[run.segments.count - 1].end = end
        } else { run.segments.append(FocusSegment(start: start, end: end)) }
        run.remaining = max(0, run.remaining - elapsed)
        if let micro = run.microRemaining {
            if micro <= elapsed {
                run.microRemaining = nil
                run.nextMicro = MicrobreakSchedule.next(settings: data.settings, remaining: run.remaining)
                sound.play(data.settings.microEndSound)
                say("继续工作吧。")
            } else { run.microRemaining = micro - elapsed }
        } else if let next = run.nextMicro {
            if next <= elapsed && run.remaining > Double(data.settings.microSeconds) {
                run.microRemaining = Double(data.settings.microSeconds)
                run.nextMicro = nil
                sound.play(data.settings.microStartSound, complete: true)
                say("微休息 \(data.settings.microSeconds) 秒，听到第二声再继续工作。", seconds: Double(data.settings.microSeconds + 1))
            } else { run.nextMicro = next <= elapsed ? nil : next - elapsed }
        }
        data.focus = run
        if run.remaining <= 0 {
            FocusAccounting.record(segments: run.segments, planned: run.planned, completed: true,
                                   startedAt: run.startedAt, endedAt: end, journal: &data.journal)
            data.focus = nil
            paused = true
            breakRemaining = Double(data.settings.breakMinutes * 60)
            persist()
            sound.play(data.settings.finishSound, complete: true)
            animate(.success)
            notify("专注完成！休息 \(data.settings.breakMinutes) 分钟。")
        }
    }
    private func tick() {
        let delta = max(0, ProcessInfo.processInfo.systemUptime - lastUptime)
        // Process breaks before focus so a newly-created break is not immediately decremented.
        if breakRemaining > 0 {
            breakRemaining = max(0, breakRemaining - delta)
            if breakRemaining == 0 { sound.play(data.settings.breakSound, complete: true); notify("休息结束，准备好下一轮了吗？") }
        }
        advanceFocus()
        let now = Date()
        if now >= temporaryUntil && state != baseState { restoreAnimation() }
        if now < countdownUntil { displayBubble(focusLabel, seconds: countdownUntil.timeIntervalSince(now)) }
        if now >= bubbleUntil && !bubble.isEmpty { bubble = ""; onBubble?("") }
        if now >= hydrationAt {
            hydrationAt = now.addingTimeInterval(Double(data.settings.hydrationMinutes * 60))
            if data.settings.hydration { animate(.reminder); notify("喝点水，休息一下吧。") }
        }
        if now >= wanderAt {
            scheduleWander()
            if data.settings.wander && state == .idle && data.focus == nil { onWander?() }
        }
        if now >= gestureAt {
            gestureAt = now.addingTimeInterval(Double.random(in: 12...28))
            if state == .idle { animate([PetState.blink, .waving, .heart].randomElement()!) }
        }
        saveTicks += 1
        if saveTicks % 4 == 0 { readCommand() }
        if saveTicks >= 20 { saveTicks = 0; if data.focus != nil { persist() } }
    }
    private func readCommand() {
        let file = store.directory.appendingPathComponent("command.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            let commanded = PetState(rawValue: object?["state"] as? String ?? "idle") ?? .idle
            animate(commanded, seconds: 6)
            if commanded == .working || commanded == .sleeping { temporaryUntil = .distantFuture }
            if let message = object?["message"] as? String { say(message, seconds: 6) }
            try FileManager.default.removeItem(at: file)
        } catch { self.error = "无法读取 command.json：\(error.localizedDescription)" }
    }
    func saveDay(_ day: JournalDay) {
        var value = day
        value.settle(minutes: data.settings.focusMinutes)
        if let i = data.journal.firstIndex(where: { $0.date == day.date }) { data.journal[i] = value }
        else { data.journal.append(value) }
        persist()
    }
    func newChat() -> String {
        data.threads.removeAll { $0.messages.isEmpty }
        let thread = ChatThread()
        data.threads.append(thread)
        return thread.id
    }
    func archive(_ id: String) {
        guard let i = data.threads.firstIndex(where: { $0.id == id }) else { return }
        data.threads[i].archived.toggle()
        persist()
    }
    func send(_ text: String, threadID: String) async {
        guard !busy, let index = data.threads.firstIndex(where: { $0.id == threadID }) else { return }
        busy = true
        defer { busy = false }
        let settings = data.settings
        let memoryReply = settings.memory ? LocalMemory.process(text, facts: &data.facts) : nil
        let context = LocalMemory.context(thread: data.threads[index], threads: data.threads, facts: data.facts, enabled: settings.memory)
        data.threads[index].messages.append(ChatMessage(role: "user", content: text))
        if data.threads[index].messages.count == 1 { data.threads[index].title = String(text.prefix(32)) }
        data.threads[index].updated = Date()
        persist()
        animate(.working, seconds: 190)
        var screenshot: URL?
        defer {
            if let screenshot { try? FileManager.default.removeItem(at: screenshot) }
        }
        do {
            if settings.screenVision && settings.provider != "offline" { screenshot = try await ScreenCapture.capture() }
            let reply = try await ai.reply(text: text, context: context, settings: settings, screenshot: screenshot, memoryReply: memoryReply)
            guard let i = data.threads.firstIndex(where: { $0.id == threadID }) else { return }
            data.threads[i].messages.append(ChatMessage(role: "assistant", content: reply.text))
            data.threads[i].updated = Date()
            data.threads[i].summary = data.threads[i].messages.suffix(8).map { "\($0.role): \(String($0.content.prefix(180)))" }.joined(separator: "\n")
            persist()
            animate(reply.state)
            say(reply.text, seconds: 8)
        } catch {
            self.error = error.localizedDescription
            animate(.error)
        }
    }
}
