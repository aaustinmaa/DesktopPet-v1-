import Foundation
import AppKit
import AVFoundation
import Testing
@testable import SuWuDu

@MainActor private final class RecordingSound: SoundPlaying {
    var played: [String] = []
    func play(_ id: String, complete: Bool) { played.append(id) }
    func stop() {}
}

struct BehaviorTests {
    @Test @MainActor func tripleClickCancelsDoubleClickAndFourthClickDoesNotReopenChat() async throws {
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        var clicks: [Int] = []
        view.onClick = { clicks.append($0) }
        func click(_ count: Int) throws {
            let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: count, clickCount: count, pressure: 1))
            let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: count, clickCount: count, pressure: 0))
            view.mouseDown(with: down)
            view.mouseUp(with: up)
        }
        try click(1)
        #expect(clicks == [1])
        try click(2)
        try click(3)
        try click(4)
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.2) * 1_000_000_000))
        #expect(clicks == [1, 3])
        #expect(view.acceptsFirstMouse(for: nil))
    }

    @Test @MainActor func resumePlaysSelectedStartSoundButPauseDoesNot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var data = AppData()
        data.settings.startSound = "custom_bell"
        let sound = RecordingSound()
        let model = AppModel(store: try DataStore(directory: directory), loaded: data, sound: sound)
        model.toggleFocus()
        #expect(sound.played == ["custom_bell"])
        model.toggleFocus()
        #expect(model.paused)
        #expect(model.bubble.contains("暂停"))
        #expect(sound.played == ["custom_bell"])
        model.toggleFocus()
        #expect(!model.paused)
        #expect(sound.played == ["custom_bell", "custom_bell"])
        #expect(model.bubble == model.focusLabel)
        model.resume() // An already running timer must not replay the cue.
        #expect(sound.played.count == 2)
        model.pause()
        model.changeSettings { $0.startSound = "silent" }
        model.resume()
        #expect(sound.played.last == "silent")
    }

    @Test @MainActor func recoveredFocusAlsoPlaysStartCueOnResume() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var data = AppData()
        data.focus = FocusRun(startedAt: Date(), planned: 25, remaining: 800)
        let sound = RecordingSound()
        let model = AppModel(store: try DataStore(directory: directory), loaded: data, sound: sound)
        #expect(model.paused)
        model.toggleFocus()
        #expect(sound.played == [data.settings.startSound])
        #expect(model.data.focus?.remaining == 800)
    }

    @Test func microbreakMustFitBeforeFocusEnds() {
        var settings = Settings()
        settings.microMin = 3
        settings.microMax = 3
        settings.microSeconds = 10
        #expect(MicrobreakSchedule.next(settings: settings, remaining: 190) == nil)
        #expect(MicrobreakSchedule.next(settings: settings, remaining: 189) == nil)
        #expect(MicrobreakSchedule.next(settings: settings, remaining: 191) == 180)
    }

    @Test @MainActor func generatedAndImportedSoundsDecodeOnMac() throws {
        for id in ["gentle", "bell", "pixel", "classic"] {
            for complete in [false, true] {
                let player = try AVAudioPlayer(data: SoundService.wave(id, complete: complete))
                #expect(player.duration > 0.1)
                #expect(player.numberOfChannels == 1)
            }
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Bell", "Done", "Piano", "Rock"] {
            let player = try AVAudioPlayer(contentsOf: root.appendingPathComponent("Assets/Sounds/\(name).wav"))
            #expect(player.duration > 0.1)
        }
    }
}
