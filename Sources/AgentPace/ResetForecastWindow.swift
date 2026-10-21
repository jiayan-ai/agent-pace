import AppKit
import SwiftUI
import WebKit
import PaceCore

/// A normal, app-owned browser window. No DOM scraping, script bridge, or account credentials.
@MainActor
final class ResetForecastWindow: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ResetForecastWindow()
    @Published var loading = false
    @Published private var failedToLoad = false
    @Published private var languageRevision = 0
    var error: String? { failedToLoad ? L("预测网站暂时无法加载。可以重试，或在浏览器中打开。") : nil }
    func refreshLanguage() { languageRevision += 1 }
    private var window: NSWindow?
    let webView: WKWebView

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: ResetForecastBrowser(browser: self))
            let window = NSWindow(contentViewController: host)
            window.title = "Agent Pace · Will Codex Reset"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1000, height: 800)
            window.setContentSize(NSSize(width: min(860, available.width - 40), height: min(700, available.height - 80)))
            window.minSize = NSSize(width: 560, height: 420)
            window.delegate = self
            window.center()
            self.window = window
        }
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        failedToLoad = false
        loading = true
        webView.load(URLRequest(url: ResetRadarLinks.forecast, timeoutInterval: 25))
    }
    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        loading = false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        self.failedToLoad = true
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(url.scheme == "https" || url.absoluteString == "about:blank" ? .allow : .cancel)
            return
        }
        if url.scheme == "https", ["willcodexreset.com", "www.willcodexreset.com"].contains(url.host?.lowercased() ?? "") {
            decisionHandler(.allow)
        } else {
            if navigationAction.navigationType == .linkActivated, url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url, url.scheme == "https" { NSWorkspace.shared.open(url) }
        return nil
    }
}

private struct ResetForecastBrowser: View {
    @ObservedObject var browser: ResetForecastWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Will Codex Reset").font(.headline)
                    Text(L("社区预测 · 公告不等于账户到账")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if browser.loading { ProgressView().controlSize(.small) }
                Button(L("刷新")) { browser.reload() }
                Link(L("在浏览器打开"), destination: ResetRadarLinks.forecast)
            }.padding(12)
            if let error = browser.error {
                Text(error).font(.callout).foregroundStyle(.orange).padding(12)
            }
            Divider()
            ForecastWebView(webView: browser.webView)
        }.frame(minWidth: 540, minHeight: 380)
    }
}

private struct ForecastWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
