import AppKit
import SwiftUI
import PaceCore

private final class MenuPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = PaceStore()
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenu = false
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "Agent Pace")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Agent Pace · 今天还可用的额度"
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hideMenu() }
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackingMenu = true }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackingMenu = false }
            }
        ]
        store.onChange = { [weak self] in self?.updateStatusItem() }
        store.onChange?()
        store.refreshAll()
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show-window") {
            showWindow()
            defaults.set(true, forKey: "hasLaunched")
        } else {
            // Reopening the app gives immediate access to its menu-bar panel.
            DispatchQueue.main.async { [weak self] in self?.showMenu() }
        }
    }

    @objc private func togglePopover() {
        if menuPanel?.isVisible == true { hideMenu() }
        else { showMenu() }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let overBudget = (store.validBudget?.overBudget ?? 0) > 0
        button.title = " " + store.menuTitle
        button.contentTintColor = nil
        button.toolTip = overBudget
            ? "\(store.provider.title) · 今日已超额 \(number(store.validBudget?.overBudget ?? 0)) 个百分点"
            : "\(store.provider.title) · 今天还可用的额度"
    }

    private func showMenu() {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        hideMenu()
        store.now = Date()

        // Use screen coordinates and a bounded viewport. A hosting controller's
        // changing intrinsic height must never reposition the panel above the bar.
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let size = NSSize(width: min(400, available.width), height: min(600, available.height))
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let x = min(max(anchor.midX - size.width / 2, available.minX), available.maxX - size.width)
        let y = min(max(anchor.minY - 6 - size.height, available.minY), available.maxY - size.height)

        let panel = MenuPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Agent Pace · 今日额度"
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.dismiss = { [weak self] in self?.hideMenu() }
        let content = ScrollView(.vertical) {
            PaceView(store: store, openWindow: { [weak self] in self?.showWindow() })
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        let host = NSHostingView(rootView: content)
        // AppKit owns the frame; SwiftUI content can grow only inside the scroll view.
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
        menuPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hideMenu()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            // AppKit must finish tracking Picker/Menu popups itself. Closing
            // their parent here can leave a hidden menu still tracking input.
            guard !self.trackingMenu else { return event }
            if event.window !== self.menuPanel,
               event.window !== self.statusItem.button?.window {
                self.hideMenu()
            }
            return event
        }
    }

    private func hideMenu() {
        menuPanel?.orderOut(nil)
        menuPanel = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }

    func applicationDidResignActive(_ notification: Notification) { hideMenu() }

    func showWindow() {
        hideMenu()
        if window == nil {
            let host = NSHostingController(rootView: PaceView(store: store))
            let newWindow = NSWindow(contentViewController: host)
            newWindow.title = "Agent Pace"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 400, height: 600))
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMenu()
        return true
    }
}

@main
struct AgentPaceApplication {
    @MainActor static func main() {
        // Small diagnostic command for verifying the real account integration without starting the UI.
        if CommandLine.arguments.contains("--check-connection") || CommandLine.arguments.contains("--check-claude") {
            do {
                let snapshot = try CommandLine.arguments.contains("--check-claude") ? ClaudeClient.fetch() : CodexClient.fetch()
                for item in snapshot.response.windows {
                    let budget = DailyBudget.reconcile(previous: nil, window: item.window, now: snapshot.fetchedAt)
                    print("\(item.label): 剩余 \(item.window.remaining.map(number) ?? "未知")%; 日均 \(budget.map { number($0.allowance) } ?? "未知")%; 重置 \(item.window.resetDate.map(resetTime) ?? "未知")")
                }
                if snapshot.response.windows.isEmpty { print("未返回额度窗口") }
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
