import Foundation
import Testing
@testable import SuWuDu

struct AppearancePreviewTests {
    @Test @MainActor func sliderAndSkinPreviewNotifyImmediatelyWithoutSaving() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let original = model.data.settings
        var changes: [Double] = []
        var skins: [String] = []
        model.onAppearanceChanged = {
            changes.append(model.displayedScale)
            skins.append(model.displayedSkin)
        }
        for scale in [0.4, 0.7, 1.2] { model.previewAppearance(skin: "suwudu", scale: scale) }
        model.previewAppearance(skin: "shenqing", scale: 1.2)
        #expect(changes == [0.4, 0.7, 1.2, 1.2])
        #expect(skins == ["suwudu", "suwudu", "suwudu", "shenqing"])
        #expect(model.data.settings == original)
        // Timer/position saves during an open settings window cannot commit its preview.
        model.persist()
        let (saved, _) = try model.store.load()
        #expect(saved.settings.skin == original.skin)
        #expect(saved.settings.scale == original.scale)
        var animatedSkin = ""
        model.onStateChanged = { _ in animatedSkin = model.displayedSkin }
        model.animate(.working)
        #expect(animatedSkin == "shenqing")
    }

    @Test @MainActor func cancelRestoresLiveSettingsAndClearsPreviewOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        var notifications = 0
        model.onAppearanceChanged = { notifications += 1 }
        model.previewAppearance(skin: "shenqing", scale: 1.4)
        model.changeSettings { $0.scale = 0.6; $0.wander = true }
        #expect(model.displayedScale == 1.4)
        model.endAppearancePreview()
        model.endAppearancePreview() // Cancel button followed by windowWillClose.
        #expect(notifications == 2)
        #expect(model.displayedSkin == "suwudu")
        #expect(model.displayedScale == 0.6)
        #expect(model.data.settings.wander)
    }

    @Test @MainActor func saveThenCloseRetainsThePreviewedAppearance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        var draft = SettingsDraft(model.data.settings)
        draft.value.skin = "shenqing"
        draft.value.scale = 1.1
        model.previewAppearance(skin: draft.value.skin, scale: draft.value.scale)
        model.changeSettings { $0 = draft.applying(to: $0) }
        model.endAppearancePreview()
        #expect(model.displayedSkin == "shenqing")
        #expect(model.displayedScale == 1.1)
        let (saved, _) = try model.store.load()
        #expect(saved.settings.skin == "shenqing")
        #expect(saved.settings.scale == 1.1)
    }
}
