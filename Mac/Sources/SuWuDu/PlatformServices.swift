import AppKit
import AVFoundation
import Carbon
import ScreenCaptureKit
import Security
import ServiceManagement
import UserNotifications

enum Resources {
    static var root: URL { Bundle.main.resourceURL!.appendingPathComponent("Assets", isDirectory: true) }
    static func sprite(_ name: String) -> URL { root.appendingPathComponent("Sprites").appendingPathComponent(name) }
}

enum Keychain {
    private static let service = "com.suwudu.desktop-pet.openai"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }
    static func read() throws -> String {
        var value = query
        value[kSecReturnData as String] = true
        value[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let result = SecItemCopyMatching(value as CFDictionary, &item)
        if result == errSecItemNotFound { return "" }
        guard result == errSecSuccess, let data = item as? Data else {
            throw AppError.message("Keychain 读取失败：\(result)")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        if key.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw AppError.message("Keychain 删除失败：\(result)") }
            return
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        var result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var value = query
            value[kSecValueData as String] = Data(key.utf8)
            value[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(value as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw AppError.message("Keychain 保存失败：\(result)") }
    }
}

enum Notifications {
    static func request() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    static func post(_ text: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "苏无度 · 沈青"
            content.body = text
            // Audio is played by SoundService, avoiding a second system notification sound.
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

@MainActor protocol SoundPlaying {
    func play(_ id: String, complete: Bool)
    func stop()
}
extension SoundPlaying {
    func play(_ id: String) { play(id, complete: false) }
}

@MainActor final class SoundService: SoundPlaying {
    static let options: [(String, String)] = [
        ("gentle", "柔和木琴"), ("bell", "清亮钟声"), ("pixel", "像素提示"), ("classic", "经典铃铃"),
        ("custom_done", "Done"), ("custom_piano", "Piano"), ("custom_rock", "Rock"), ("custom_bell", "Bell"), ("silent", "静音")
    ]
    private var player: AVAudioPlayer?
    func stop() { player?.stop(); player = nil }
    func play(_ id: String, complete: Bool = false) {
        stop()
        guard id != "silent" else { return }
        do {
            let custom = ["custom_done": "Done", "custom_piano": "Piano", "custom_rock": "Rock", "custom_bell": "Bell"]
            if let name = custom[id] {
                player = try AVAudioPlayer(contentsOf: Resources.root.appendingPathComponent("Sounds/\(name).wav"))
            } else { player = try AVAudioPlayer(data: Self.wave(id, complete: complete)) }
            guard player?.prepareToPlay() == true, player?.play() == true else {
                throw AppError.message("音频设备未能开始播放铃声。")
            }
        } catch {
            stop()
            NSLog("Unable to play sound: %@", error.localizedDescription)
            NSSound.beep() // Match Windows' system-sound fallback instead of failing silently.
        }
    }
    static func wave(_ id: String, complete: Bool) -> Data {
        let notes: [Double]
        let duration: Double, gap: Double, amplitude: Double
        switch id {
        case "bell": notes = complete ? [659.25, 880, 1046.5] : [659.25, 880]; duration = complete ? 0.36 : 0.30; gap = complete ? 0.07 : 0.055; amplitude = 0.43
        case "pixel": notes = complete ? [523.25, 659.25, 783.99, 1046.5] : [659.25, 880]; duration = 0.105; gap = complete ? 0.028 : 0.030; amplitude = 0.25
        case "classic": notes = complete ? [783.99, 783.99, 1046.5, 783.99] : [783.99, 1046.5]; duration = complete ? 0.24 : 0.22; gap = complete ? 0.075 : 0.085; amplitude = 0.43
        default: notes = complete ? [523.25, 659.25, 783.99, 1046.5] : [523.25, 659.25, 783.99]; duration = complete ? 0.23 : 0.20; gap = complete ? 0.05 : 0.045; amplitude = 0.36
        }
        let rate = 44100
        var pcm = Data()
        for frequency in notes {
            let samples = Int((duration * Double(rate)).rounded(.toNearestOrEven))
            let attackSamples = max(1, Int((Double(rate) * (id == "pixel" ? 0.003 : 0.009)).rounded(.toNearestOrEven)))
            for sample in 0..<samples {
                let t = Double(sample) / Double(rate)
                let phase = 2 * Double.pi * frequency * t
                let bell = id == "bell" || id == "classic"
                let progress = Double(sample) / Double(max(1, samples - 1))
                let envelope = min(1, Double(sample) / Double(attackSamples)) * pow(1 - progress, bell ? 1.8 : 0.75)
                let wave: Double
                if id == "pixel" { wave = sin(phase) >= 0 ? 0.78 : -0.78 }
                else if bell { wave = sin(phase) * 0.72 + sin(phase * 2.01) * 0.19 + sin(phase * 3.98) * 0.09 }
                else { wave = sin(phase) * 0.82 + sin(phase * 2) * 0.12 }
                var value = Int16(max(-32767, min(32767, wave * envelope * amplitude * 32767))).littleEndian
                withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
            }
            pcm.append(Data(count: Int((gap * Double(rate)).rounded(.toNearestOrEven)) * 2))
        }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); number(UInt32(36 + pcm.count)); text("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(rate)); number(UInt32(rate * 2)); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

@MainActor enum ScreenCapture {
    static func capture() async throws -> URL {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw AppError.message("请在系统设置 → 隐私与安全性 → 屏幕录制中允许苏无度，然后重新打开应用。也可以关闭“看屏幕”继续聊天。")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else { throw AppError.message("没有可截取的显示器。") }
        let chatIDs = NSApp.windows.filter { $0.identifier?.rawValue == "chat" && $0.windowNumber > 0 }.map { CGWindowID($0.windowNumber) }
        let excluded = content.windows.filter { chatIDs.contains($0.windowID) }
        var frames: [(CGRect, CGImage)] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            frames.append((CGDisplayBounds(display.displayID), image))
        }
        let union = frames.reduce(CGRect.null) { $0.union($1.0) }
        let scale = min(1, 2560 / max(union.width, union.height))
        let width = max(1, Int(union.width * scale)), height = max(1, Int(union.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw AppError.message("无法创建截图。")
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        for (bounds, image) in frames {
            context.draw(image, in: CGRect(x: (bounds.minX - union.minX) * scale, y: (union.maxY - bounds.maxY) * scale,
                                          width: bounds.width * scale, height: bounds.height * scale))
        }
        guard let image = context.makeImage(), let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            throw AppError.message("截图编码失败。")
        }
        let directory = DataStore.applicationDirectory.appendingPathComponent("ScreenCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("screen-\(UUID().uuidString).jpg")
        try jpeg.write(to: path, options: .atomic)
        return path
    }
    static func cleanup() {
        let directory = DataStore.applicationDirectory.appendingPathComponent("ScreenCaptures", isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where file.lastPathComponent.hasPrefix("screen-") && file.pathExtension == "jpg" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

@MainActor final class RecoveryHotKey {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: () -> Void
    init(action: @escaping () -> Void) throws {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<RecoveryHotKey>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { hotkey.action() }
            return noErr
        }, 1, &type, context, &handler)
        guard installed == noErr else { throw AppError.message("无法安装恢复快捷键处理器。") }
        let id = EventHotKeyID(signature: 0x53574455, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &key)
        guard result == noErr else {
            if let handler { RemoveEventHandler(handler) }; handler = nil
            throw AppError.message("⌃⌥P 已被占用。仍可使用菜单栏的“叫回桌宠”。")
        }
    }
    deinit {
        if let key { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }
}
