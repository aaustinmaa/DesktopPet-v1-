import Foundation
import Testing
@testable import SuWuDu

struct ClaudeSettingsTests {
    @Test func preClaudeModelSettingsDecodeWithoutLosingExistingChoices() throws {
        var original = Settings()
        original.provider = "claude"
        original.codexModel = "saved-codex-model"
        original.reasoning = "high"
        original.claudeModel = "sonnet"
        original.claudeEffort = "medium"
        let encoded = try JSONEncoder().encode(original)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "claudeModel")
        legacy.removeValue(forKey: "claudeEffort")

        let decoded = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))

        #expect(decoded.provider == "claude")
        #expect(decoded.claudeModel == nil)
        #expect(decoded.claudeEffort == nil)
        #expect(decoded.codexModel == "saved-codex-model")
        #expect(decoded.reasoning == "high")
    }

    @Test func claudeChoicesSurviveSaveIndependentlyOfChatGPTChoices() throws {
        var settings = Settings()
        settings.claudeModel = "opus"
        settings.claudeEffort = "max"
        settings.codexModel = "saved-codex-model"
        settings.reasoning = "low"

        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
    }

    @Test func savingClaudeEditsPreservesConcurrentChatGPTAndWindowChanges() {
        var initial = Settings()
        initial.claudeModel = "sonnet"
        initial.claudeEffort = "high"
        var draft = SettingsDraft(initial)
        draft.value.claudeModel = "opus"
        draft.value.claudeEffort = nil
        var live = initial
        live.codexModel = "new-codex-model"
        live.reasoning = "xhigh"
        live.windowX = 650

        let saved = draft.applying(to: live)

        #expect(saved.claudeModel == "opus")
        #expect(saved.claudeEffort == nil)
        #expect(saved.codexModel == "new-codex-model")
        #expect(saved.reasoning == "xhigh")
        #expect(saved.windowX == 650)
    }

    @Test func unrelatedDraftDoesNotOverwriteLiveClaudeChoices() {
        let initial = Settings()
        var draft = SettingsDraft(initial)
        draft.value.focusMinutes = 30
        var live = initial
        live.claudeModel = "sonnet"
        live.claudeEffort = "medium"

        let saved = draft.applying(to: live)

        #expect(saved.claudeModel == "sonnet")
        #expect(saved.claudeEffort == "medium")
        #expect(saved.focusMinutes == 30)
    }

    @Test func normalizedClaudeChoicesUseNilForDefaultsAndRejectUnknownEffort() {
        var settings = Settings()
        settings.claudeModel = "  future-account-model\n"
        settings.claudeEffort = " high\n"
        settings.normalize()
        #expect(settings.claudeModel == "future-account-model")
        #expect(settings.claudeEffort == "high")

        settings.claudeModel = " \n"
        settings.claudeEffort = "ultra"
        settings.normalize()
        #expect(settings.claudeModel == nil)
        #expect(settings.claudeEffort == nil)

        settings.claudeEffort = "xhigh"
        settings.normalize()
        #expect(settings.claudeEffort == "xhigh")
        settings.claudeEffort = " "
        settings.normalize()
        #expect(settings.claudeEffort == nil)
    }
}
