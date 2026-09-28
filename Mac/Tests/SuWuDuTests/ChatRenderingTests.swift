import AppKit
import JavaScriptCore
import SwiftUI
import Testing
import WebKit
@testable import SuWuDu

struct ChatRenderingTests {
    @MainActor private func renderer() throws -> JSContext {
        let context = try #require(JSContext())
        let root = try #require(ChatMarkdownView.resourceURL).deletingLastPathComponent()
        for file in ["markdown-it.min.js", "katex.min.js", "renderer.js"] {
            context.evaluateScript(try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8))
            #expect(context.exception == nil)
        }
        return context
    }
    @Test @MainActor func rendersProvidedInductionReply() throws {
        let context = try renderer()
        let reply = #"""
        The induction doesn’t close with the **same constant**. If the hypothesis is \(T(n/2)\le c(n/2)\) and the merge work is at most \(dn\), then

        \[
        T(n)\le 2c(n/2)+dn=(c+d)n,
        \]

        which is **not** \(\le cn\). Writing \(2O(n/2)+O(n)=O(n)\) hides this increase in the constant. Each recursion level contributes \(\Theta(n)\), across \(\log n\) levels, so the correct bound is \(\Theta(n\log n)\).
        """#
        let html = try #require(context.objectForKeyedSubscript("renderChatMessage")?.call(withArguments: [reply])?.toString())
        #expect(html.contains("<strong>same constant</strong>"))
        #expect(html.contains("<strong>not</strong>"))
        #expect(html.components(separatedBy: "class=\"katex\"").count - 1 == 8)
        #expect(html.contains("katex-display"))
        #expect(!html.contains("math-fallback"))
    }
    @Test @MainActor func preservesCodeAndHandlesTablesFallbackAndUntrustedHTML() throws {
        let context = try renderer()
        func render(_ text: String) throws -> String {
            try #require(context.objectForKeyedSubscript("renderChatMessage")?.call(withArguments: [text])?.toString())
        }
        let code = try render(#"`\(x\)`"# + "\n\n```tex\n\\[x\\]\n```")
        #expect(!code.contains("class=\"katex\""))
        #expect(code.contains("<pre><code"))
        #expect(try render("| A | B |\n|---|---|\n| 1 | 2 |").contains("<table>"))
        #expect(try render(#"\(\unknownCommand{x}\)"#).contains("math-fallback"))
        #expect(try render(#"\(unfinished"#).contains("unfinished"))
        #expect(try render("$x^2$ and $$y^2$$").components(separatedBy: "class=\"katex\"").count - 1 == 2)
        #expect(!(try render("cost $5 and $10")).contains("class=\"katex\""))
        let unsafe = try render("<script>alert(1)</script>\n\n[bad](javascript:alert(1))\n\n![picture](https://example.com/tracker.png)")
        #expect(!unsafe.contains("<script>"))
        #expect(!unsafe.contains("href=\"javascript:"))
        #expect(!unsafe.contains("<img"))
    }
    @Test @MainActor func webViewLoadsLocalResourcesAndResizes() async throws {
        var height: CGFloat = 24
        var failed = false
        let parent = ChatMarkdownView(content: "**Hello** " + String(repeating: #"\(x^2\) text "#, count: 30),
            height: Binding(get: { height }, set: { height = $0 }),
            failed: Binding(get: { failed }, set: { failed = $0 }))
        let coordinator = ChatMarkdownView.Coordinator(parent)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(coordinator, name: "height")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 24), configuration: config)
        web.navigationDelegate = coordinator
        let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        defer { config.userContentController.removeScriptMessageHandler(forName: "height"); window.contentView = nil }
        let url = try #require(ChatMarkdownView.resourceURL)
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        for _ in 0..<100 {
            if height > 24 || failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!failed)
        #expect(height > 24)
        let rendered = try await web.evaluateJavaScript("document.querySelectorAll('.katex').length") as? Int
        #expect(rendered == 30)
        let wideHeight = height
        window.setContentSize(NSSize(width: 250, height: 24))
        for _ in 0..<50 {
            if height > wideHeight { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(height > wideHeight)
        let fontLoaded = try await web.evaluateJavaScript("document.fonts.check('14px KaTeX_Main')") as? Bool
        #expect(fontLoaded == true)
    }
}
