import Foundation
import ScreenCaptureKit

@MainActor enum ChatScreenCapture {
    static func reply(
        enabled: Bool,
        capture: () async throws -> URL = { try await ScreenCapture.capture() },
        respond: (URL?, String?) async throws -> CompanionReply
    ) async throws -> CompanionReply {
        var screenshot: URL?
        var notice: String?
        defer {
            if let screenshot { try? FileManager.default.removeItem(at: screenshot) }
        }
        if enabled {
            do { screenshot = try await capture() }
            catch is CancellationError { throw CancellationError() }
            catch {
                let failure = error as NSError
                if failure.domain == SCStreamErrorDomain && failure.code == SCStreamError.Code.userDeclined.rawValue {
                    notice = "本次未取得屏幕截图，系统拒绝了录屏访问；本次仅按文字回复。如果录屏开关已开启，开发版更新后可能需要退出应用，在系统设置中关闭再开启苏无度的录屏授权，然后重新打开应用。"
                } else {
                    notice = "本次截图失败，本次仅按文字回复。\(error.localizedDescription)"
                }
            }
        }
        try Task.checkCancellation()
        var reply = try await respond(screenshot, notice)
        if let notice { reply.text = "\(notice)\n\n\(reply.text)" }
        return reply
    }
}
