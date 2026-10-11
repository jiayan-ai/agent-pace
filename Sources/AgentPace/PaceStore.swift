import AppKit
import SwiftUI
import PaceCore

@MainActor
final class PaceStore: ObservableObject {
    @Published private var history = PaceHistory()
    @Published private var refreshing: Set<UsageProvider> = []
    @Published private var errors: [UsageProvider: String] = [:]
    @Published private var verified: Set<UsageProvider> = []
    @Published var now = Date()
    @Published var persistenceError: String?
    @Published private(set) var claudeEnabled = UserDefaults.standard.bool(forKey: "claudeDesktopConnectionEnabled")
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastAttempt: [UsageProvider: Date] = [:]
    private var retryAfter: [UsageProvider: Date] = [:]
    private let cacheURL: URL

    init() {
        cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexPace/state.json")
        if let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode(PaceHistory.self, from: data) {
            history = saved
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.onChange?()
                // Keep both daily baselines up to date even while one is hidden.
                for provider in UsageProvider.allCases {
                    let record = self.history[provider]
                    let crossedDay = record.snapshot.map { !Calendar.current.isDate($0.fetchedAt, inSameDayAs: self.now) } ?? false
                    let interval: TimeInterval = crossedDay ? 60 : 300
                    if self.now.timeIntervalSince(self.lastAttempt[provider] ?? .distantPast) >= interval {
                        self.refresh(provider: provider)
                    }
                }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    var provider: UsageProvider { history.selectedProvider }
    var snapshot: UsageSnapshot? { history[provider].snapshot }
    var selectedID: String { history[provider].selectedID }
    var isRefreshing: Bool { refreshing.contains(provider) }
    var error: String? { errors[provider] }
    var windows: [MeteredWindow] { snapshot?.response.windows ?? [] }
    var selected: MeteredWindow? { windows.first(where: { $0.id == selectedID }) ?? windows.first }
    var budget: DailyBudget? {
        guard let selected, let snapshot else { return nil }
        return history[provider].budgets["\(snapshot.accountKey)/\(selected.id)"]
    }
    var stale: Bool {
        guard verified.contains(provider), let snapshot else { return true }
        return error != nil || now.timeIntervalSince(snapshot.fetchedAt) > 660
    }
    var validBudget: DailyBudget? {
        guard let budget, Calendar.current.startOfDay(for: now) == budget.dayStart,
              budget.timeZoneID == Calendar.current.timeZone.identifier,
              budget.resetAt > now.timeIntervalSince1970 else { return nil }
        return budget
    }
    var menuTitle: String {
        guard let budget = validBudget else { return "\(provider.shortTitle) \(isRefreshing ? "同步中" : "待同步")" }
        return "\(provider.shortTitle) \(stale ? "≈" : "")\(number(budget.leftToday))%"
    }
    var daysLeft: Double? { selected?.window.resetDate.map { max(0, $0.timeIntervalSince(now) / 86400) } }
    func choose(_ id: String) { history[provider].selectedID = id; persist(); onChange?() }
    func selectProvider(_ value: UsageProvider) {
        guard value != provider else { return }
        history.selectedProvider = value
        now = Date()
        persist()
        onChange?()
        if stale { refresh() }
    }
    func refreshAll() { for provider in UsageProvider.allCases { refresh(provider: provider) } }
    func refresh() { refresh(provider: provider) }
    func connectClaude() {
        claudeEnabled = true
        UserDefaults.standard.set(true, forKey: "claudeDesktopConnectionEnabled")
        refresh(provider: .claude, allowKeychainPrompt: true)
    }
    func disconnectClaude() {
        claudeEnabled = false
        UserDefaults.standard.set(false, forKey: "claudeDesktopConnectionEnabled")
        verified.remove(.claude)
        errors[.claude] = nil
        onChange?()
    }
    func openClaude() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Claude.app"))
    }

    private func refresh(provider: UsageProvider, allowKeychainPrompt: Bool = false) {
        // No Claude credential access at all until the user explicitly connects.
        guard provider != .claude || claudeEnabled else { return }
        guard !refreshing.contains(provider), Date() >= (retryAfter[provider] ?? .distantPast) else { return }
        refreshing.insert(provider)
        lastAttempt[provider] = Date()
        onChange?()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result {
                switch provider {
                case .codex: return try CodexClient.fetch()
                case .claude: return try ClaudeClient.fetch(allowKeychainPrompt: allowKeychainPrompt)
                }
            }
            Task { @MainActor in
                guard let self else { return }
                self.refreshing.remove(provider)
                self.now = Date()
                // Disabling the connection also discards any in-flight result.
                guard provider != .claude || self.claudeEnabled else { return }
                switch result {
                case .success(let current):
                    self.errors[provider] = nil
                    self.retryAfter[provider] = nil
                    self.verified.insert(provider)
                    // Commit to the provider that started this request, even if
                    // the user has switched the toggle while it was loading.
                    self.history[provider].ingest(current)
                    self.persist()
                case .failure(let failure):
                    self.errors[provider] = (failure as? LocalizedError)?.errorDescription ?? "额度同步失败，请稍后重试。"
                    if case ClaudeUsageError.keychainPermission = failure {
                        self.claudeEnabled = false
                        UserDefaults.standard.set(false, forKey: "claudeDesktopConnectionEnabled")
                        self.verified.remove(.claude)
                    }
                    if case ClaudeUsageError.throttled(let seconds) = failure {
                        self.retryAfter[provider] = Date().addingTimeInterval(seconds)
                    }
                }
                self.onChange?()
            }
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: cacheURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
            persistenceError = nil
        } catch { persistenceError = "今日记录暂时无法保存；重新打开后会重新计算预算。" }
    }
}

func number(_ value: Double) -> String { String(format: "%.1f", value) }
func localTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}
func resetTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M 月 d 日 HH:mm"
    return formatter.string(from: date)
}
