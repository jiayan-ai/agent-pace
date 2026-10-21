import AppKit
import WebKit
import PaceCore

/// An app-owned browser session. Claude desktop and its protected storage are
/// deliberately not consulted, including on startup and during migration.
@MainActor
final class ClaudeWebSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        return view
    }()
    private var window: NSWindow?
    private var popup: NSWindow?
    private var completion: ((Result<UsageSnapshot, Error>) -> Void)?
    private var requestID: UUID?
    private var executing = false
    private var lastResult: Result<UsageSnapshot, Error>?
    private lazy var syncButton = NSButton(title: L("同步额度"), target: self, action: #selector(syncNow))
    private var onSync: (() -> Void)?
    private let message = NSTextField(wrappingLabelWithString: L("在下方 claude.ai 登录，完成后点击「同步额度」。无需 Mac 钥匙串密码。"))
    private let origin = NSTextField(labelWithString: "https://claude.ai")
    private let organizations = NSPopUpButton()
    private var organizationIDs: [String] = []
    private var selectedOrganization: String {
        get { UserDefaults.standard.string(forKey: "claudeWebOrganization") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "claudeWebOrganization") }
    }

    func showLogin(onSync: @escaping () -> Void) {
        self.onSync = onSync
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("Agent Pace · 连接 Claude")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 640, height: 500)
            let sync = syncButton
            sync.bezelStyle = .rounded
            organizations.target = self
            organizations.action = #selector(chooseOrganization)
            organizations.isHidden = true
            origin.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            origin.textColor = .secondaryLabelColor
            message.font = .systemFont(ofSize: 12)
            let actions = NSStackView(views: [origin, organizations, sync])
            actions.distribution = .fill
            actions.spacing = 12
            let header = NSStackView(views: [message, actions])
            header.orientation = .vertical
            header.alignment = .leading
            header.spacing = 8
            header.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
            let root = NSView()
            for view in [header, webView] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
            NSLayoutConstraint.activate([
                header.leadingAnchor.constraint(equalTo: root.leadingAnchor), header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                header.topAnchor.constraint(equalTo: root.topAnchor), webView.topAnchor.constraint(equalTo: header.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: root.leadingAnchor), webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
            window.contentView = root
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webView.url == nil { loadUsagePage() }
        else { onSync() }
    }

    func refreshLanguage() {
        window?.title = L("Agent Pace · 连接 Claude")
        syncButton.title = L("同步额度")
        if let popup, let view = popup.contentView as? WKWebView {
            popup.title = L("Claude 登录 · ") + (view.url?.host ?? "")
        }
        if organizations.numberOfItems > 0 { organizations.item(at: 0)?.title = L("选择组织…") }
        switch lastResult {
        case .success?: message.stringValue = L("已连接，额度已同步。可以关闭此窗口，之后每 5 分钟自动刷新。")
        case .failure(let error)?: message.stringValue = error.localizedDescription
        case nil: message.stringValue = L("在下方 claude.ai 登录，完成后点击「同步额度」。无需 Mac 钥匙串密码。")
        }
    }

    @objc private func syncNow() { onSync?() }
    @objc private func chooseOrganization() {
        let index = organizations.indexOfSelectedItem
        guard organizationIDs.indices.contains(index) else { return }
        selectedOrganization = organizationIDs[index]
        onSync?()
    }

    func fetch(completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion
        let id = UUID()
        requestID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self, self.requestID == id else { return }
            self.finish(.failure(ClaudeUsageError.network))
        }
        if webView.isLoading { return }
        if ClaudeWebAPI.isClaudeOrigin(webView.url) { query(id: id) }
        else { loadUsagePage() }
    }

    private func loadUsagePage() {
        webView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    private func query(id: UUID) {
        guard requestID == id, !executing else { return }
        guard ClaudeWebAPI.isClaudeOrigin(webView.url) else { finish(.failure(ClaudeUsageError.notSignedIn)); return }
        executing = true
        // Isolate from page scripts and pass the organization as structured data.
        webView.callAsyncJavaScript(ClaudeWebAPI.script, arguments: ["selectedOrganization": selectedOrganization],
                                   in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.requestID == id else { return }
            do {
                guard let json = try result.get() as? String, let data = json.data(using: .utf8), data.count < 1_000_000 else {
                    throw ClaudeUsageError.invalidResponse
                }
                let reply = try JSONDecoder().decode(ClaudeWebReply.self, from: data)
                self.updateOrganizations(reply.organizations ?? [])
                let snapshot = try reply.snapshot()
                self.selectedOrganization = reply.organization ?? ""
                self.finish(.success(snapshot))
            } catch let error as ClaudeUsageError { self.finish(.failure(error)) }
            catch { self.finish(.failure(ClaudeUsageError.network)) }
        }
    }

    private func updateOrganizations(_ values: [ClaudeOrganization]) {
        guard !values.isEmpty else { return }
        organizationIDs = values.map(\.uuid)
        organizations.removeAllItems()
        organizations.addItem(withTitle: L("选择组织…"))
        // Placeholder is intentionally not a valid organization choice.
        organizationIDs.insert("", at: 0)
        organizations.addItems(withTitles: values.map(\.name))
        organizations.selectItem(at: organizationIDs.firstIndex(of: selectedOrganization) ?? 0)
        organizations.isHidden = values.count == 1 && (selectedOrganization.isEmpty || values[0].uuid == selectedOrganization)
    }

    private func finish(_ result: Result<UsageSnapshot, Error>) {
        lastResult = result
        let callback = completion
        completion = nil
        requestID = nil
        executing = false
        switch result {
        case .success:
            message.stringValue = L("已连接，额度已同步。可以关闭此窗口，之后每 5 分钟自动刷新。")
            if popup != nil { popup?.close(); popup = nil; window?.makeKeyAndOrderFront(nil) }
        case .failure(let error): message.stringValue = error.localizedDescription
        }
        callback?(result)
    }

    func disconnect(completion: @escaping () -> Void) {
        finish(.failure(ClaudeUsageError.notSignedIn))
        onSync = nil
        webView.stopLoading()
        popup?.close(); popup = nil
        window?.close()
        selectedOrganization = ""
        webView.loadHTMLString("", baseURL: nil)
        // This store belongs to Agent Pace; other apps' sessions are untouched.
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            completion()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else {
            // OAuth popups share our data store. When they return to Claude,
            // try the read-only quota request; do not close them until it succeeds.
            popup?.title = L("Claude 登录 · ") + (webView.url?.host ?? "")
            if ClaudeWebAPI.isClaudeOrigin(webView.url) { onSync?() }
            return
        }
        origin.stringValue = webView.url.map { "\($0.scheme ?? "https")://\($0.host ?? "")" } ?? ""
        if let id = requestID { query(id: id) }
        else if window?.isVisible == true, ClaudeWebAPI.isClaudeOrigin(webView.url) { onSync?() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView, requestID != nil { finish(.failure(ClaudeUsageError.network)) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.webView(webView, didFail: navigation, withError: error) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Visible login may navigate to the user's HTTPS identity provider.
        // No custom URL schemes, insecure HTTP, or desktop-app authentication hooks.
        // srcdoc is used by normal embedded verification frames (Cloudflare's
        // documented WebView requirements). Keep the engine's default UA/CSP.
        let allowed = url.scheme == "https" || ["about:blank", "about:srcdoc"].contains(url.absoluteString)
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard window?.isVisible == true, action.request.url?.scheme == "https" else { return nil }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        let child = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        child.title = L("Claude 登录 · ") + (action.request.url?.host ?? "")
        child.isReleasedWhenClosed = false
        child.contentView = view
        child.center()
        popup?.close()
        popup = child
        child.makeKeyAndOrderFront(nil)
        return view
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView !== self.webView { popup?.close(); popup = nil; loadUsagePage() }
    }
}
