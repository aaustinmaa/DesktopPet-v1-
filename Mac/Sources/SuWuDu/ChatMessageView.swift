import SwiftUI
import WebKit

/// Each assistant bubble has a local, non-scrolling document that follows its content height.
struct ChatMessageBody: View {
    let content: String
    @State private var height: CGFloat = 24
    @State private var failed = false
    var body: some View {
        if failed {
            Text(content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ChatMarkdownView(content: content, height: $height, failed: $failed)
                .frame(height: height)
        }
    }
}

struct ChatMarkdownView: NSViewRepresentable {
    let content: String
    @Binding var height: CGFloat
    @Binding var failed: Bool
    static var resourceURL: URL? {
        // SwiftPM’s generated accessor searches beside the executable; app bundles
        // keep the copied resource bundle in Contents/Resources instead.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("SuWuDuMac_SuWuDu.bundle")
        let bundle = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
        return bundle.url(forResource: "index", withExtension: "html", subdirectory: "ChatRenderer")
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "height")
        let view = ChatBubbleWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        if let url = Self.resourceURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            DispatchQueue.main.async { failed = true }
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(view)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        (view as? ChatBubbleWebView)?.stopMonitoringScroll()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "height")
        view.navigationDelegate = nil
        view.stopLoading()
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: ChatMarkdownView
        var ready = false
        var rendered: String?
        init(_ parent: ChatMarkdownView) { self.parent = parent }
        func render(_ view: WKWebView) {
            guard ready, rendered != parent.content else { return }
            rendered = parent.content
            // Pass text as data, never interpolate a model reply into executable JavaScript.
            view.callAsyncJavaScript("updateMessage(source)", arguments: ["source": parent.content], in: nil, in: .page) { [weak self] result in
                if case .failure = result { self?.parent.failed = true }
            }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            let value = CGFloat(number.doubleValue)
            guard value.isFinite, value >= 0 else { return }
            let next = max(24, value)
            if abs(parent.height - next) > 0.5 { parent.height = next }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            render(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.failed = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.failed = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.failed = true }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(action.request.url == ChatMarkdownView.resourceURL ? .allow : .cancel)
            }
        }
    }
}

struct ChatCopyButton: View {
    let content: String
    let onDark: Bool
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(content, forType: .string)
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                copied = false
            }
        } label: {
            Text(copied ? "已复制" : "复制").frame(width: 40)
        }
        .buttonStyle(ChatCopyButtonStyle(onDark: onDark))
        .help("复制这条消息")
        .onDisappear { resetTask?.cancel(); copied = false }
    }
}
private struct ChatCopyButtonStyle: ButtonStyle {
    let onDark: Bool
    func makeBody(configuration: Configuration) -> some View {
        ChatCopyButtonSurface(configuration: configuration, onDark: onDark)
    }
}
private struct ChatCopyButtonSurface: View {
    let configuration: ButtonStyle.Configuration
    let onDark: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        configuration.label.font(.system(size: 10))
            .padding(.horizontal, 6).padding(.vertical, 2).frame(minHeight: 22)
            .foregroundStyle(hovered || configuration.isPressed || onDark ? Color.white : PetTheme.ink)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hovered ? PetTheme.accent : .clear, lineWidth: 1)
                        .scaleEffect(hovered ? 1 : 0.7)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(configuration.isPressed ? PetTheme.ink : hovered ? Color(red: 41/255, green: 93/255, blue: 101/255) : .clear)
                        .scaleEffect(hovered ? 0.7 : 1)
                }
            }
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .timingCurve(0.25, 0, 0.3, 1, duration: 0.3), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}
