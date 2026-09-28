import Foundation
import ScreenCaptureKit
import Testing
@testable import SuWuDu

struct ChatScreenCaptureTests {
    @Test @MainActor func deniedCaptureStillRepliesWithoutAnImage() async throws {
        var replies = 0
        let result = try await ChatScreenCapture.reply(enabled: true, capture: {
            throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        }) { image, notice in
            replies += 1
            #expect(image == nil)
            #expect(notice?.contains("系统拒绝") == true)
            return CompanionReply(text: "文字回复")
        }
        #expect(replies == 1)
        #expect(result.text.hasSuffix("文字回复"))
        #expect(result.text.contains("未取得屏幕截图"))
    }

    @Test @MainActor func successfulCaptureAttachesAndCleansUpImage() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let result = try await ChatScreenCapture.reply(enabled: true, capture: { path }) { image, notice in
            #expect(image == path)
            #expect(notice == nil)
            #expect(FileManager.default.fileExists(atPath: path.path))
            return CompanionReply(text: "图片回复")
        }
        #expect(result.text == "图片回复")
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test @MainActor func disabledCaptureDoesNotRequestAccess() async throws {
        _ = try await ChatScreenCapture.reply(enabled: false, capture: {
            Issue.record("Disabled screen vision must not request capture")
            throw CancellationError()
        }) { image, notice in
            #expect(image == nil)
            #expect(notice == nil)
            return CompanionReply(text: "文字回复")
        }
    }

    @Test @MainActor func cancellationDoesNotSendTextFallback() async {
        do {
            _ = try await ChatScreenCapture.reply(enabled: true, capture: { throw CancellationError() }) { _, _ in
                Issue.record("Cancelled capture must not send a request")
                return CompanionReply(text: "")
            }
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError) }
    }
}
