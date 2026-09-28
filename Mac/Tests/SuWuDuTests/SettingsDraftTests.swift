import Testing
@testable import SuWuDu

struct SettingsDraftTests {
    @Test func editsStayLocalAndSavePreservesLivePositionAndMenuChanges() {
        let initial = Settings()
        var draft = SettingsDraft(initial)
        draft.value.focusMinutes = 40
        draft.value.codexModel = "chosen-model"
        #expect(initial.focusMinutes == 25)
        var live = initial
        live.windowX = 500
        live.wander = true
        let saved = draft.applying(to: live)
        #expect(saved.focusMinutes == 40)
        #expect(saved.codexModel == "chosen-model")
        #expect(saved.windowX == 500)
        #expect(saved.wander)
    }
    @Test func switchingCharacterUpdatesDefaultNameButKeepsCustomName() {
        var draft = SettingsDraft(Settings())
        draft.value.skin = "shenqing"
        #expect(draft.applying(to: Settings()).petName == "沈青")
        draft.value.petName = "青青"
        #expect(draft.applying(to: Settings()).petName == "青青")
    }
}
