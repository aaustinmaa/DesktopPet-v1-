import Foundation
import Testing
@testable import SuWuDu

final class AppModelTests {
    @Test @MainActor func testPauseRestartAndResumeExcludeOfflineTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.settings.startSound = "silent"
        data.settings.microbreaks = false
        let model = AppModel(store: store, loaded: data)
        model.startFocus()
        try await Task.sleep(nanoseconds: 100_000_000)
        model.pause()
        let remaining = try #require(model.data.focus?.remaining)
        #expect(remaining < 1500)
        try await Task.sleep(nanoseconds: 100_000_000)
        model.pause()
        #expect(model.data.focus?.remaining == remaining)

        let restored = AppModel(store: store, loaded: try store.load().0)
        #expect(restored.paused)
        #expect(restored.data.focus?.remaining == remaining)
        restored.resume()
        try await Task.sleep(nanoseconds: 100_000_000)
        restored.pause()
        #expect(try #require(restored.data.focus?.remaining) < remaining)
    }

    @Test @MainActor func testStoppingRecoveredFocusSettlesOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        let start = Date().addingTimeInterval(-125)
        var data = AppData()
        data.focus = FocusRun(startedAt: start, planned: 25, remaining: 1375,
                              segments: [FocusSegment(start: start, end: start.addingTimeInterval(125))])
        let model = AppModel(store: store, loaded: data)
        model.stopFocus()
        model.stopFocus()
        let restored = try store.load().0
        #expect(restored.focus == nil)
        #expect(restored.journal.reduce(0) { $0 + $1.total } == 2)
    }

    @Test @MainActor func testOfflineChatPersistsReplyAndMemoryWithoutScreenCapture() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.settings.provider = "offline"
        data.settings.screenVision = true
        let model = AppModel(store: store, loaded: data)
        let thread = model.newChat()
        await model.send("请记住：测试喜欢茶", threadID: thread)
        #expect(model.error == nil)
        #expect(!(model.busy))
        let restored = try store.load().0
        #expect(restored.facts == ["测试喜欢茶"])
        #expect(restored.threads.first?.messages.map(\.role) == ["user", "assistant"])
        #expect(restored.threads.first?.messages.last?.content == "记住了：测试喜欢茶")
    }
}
