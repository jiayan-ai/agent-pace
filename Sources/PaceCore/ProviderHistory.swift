import Foundation

public enum UsageProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, claude
    public var id: String { rawValue }
    public var title: String { self == .codex ? "Codex" : "Claude Code" }
    public var shortTitle: String { self == .codex ? "Codex" : "Claude" }
}

public struct ProviderHistory: Codable {
    public var snapshot: UsageSnapshot?
    public var budgets: [String: DailyBudget]
    public var selectedID: String
    public var activity: AccountActivity?
    public var activityFetchedAt: Date?

    public init(snapshot: UsageSnapshot? = nil, budgets: [String: DailyBudget] = [:], selectedID: String = "") {
        self.snapshot = snapshot
        self.budgets = budgets
        self.selectedID = selectedID
    }

    public mutating func ingest(_ current: UsageSnapshot, calendar: Calendar = .current) {
        if snapshot?.accountKey != current.accountKey {
            budgets = [:]
            activity = nil
            activityFetchedAt = nil
        }
        if let currentActivity = current.activity, currentActivity.dailyUsageBuckets != nil {
            activity = currentActivity.recent(now: current.fetchedAt)
            activityFetchedAt = current.fetchedAt
        }
        snapshot = current
        var next: [String: DailyBudget] = [:]
        for item in current.response.windows {
            let key = "\(current.accountKey)/\(item.id)"
            if let budget = DailyBudget.reconcile(previous: budgets[key], window: item.window, now: current.fetchedAt, calendar: calendar) {
                next[key] = budget
            }
        }
        budgets = next
        if !current.response.windows.contains(where: { $0.id == selectedID }) {
            selectedID = current.response.windows.first?.id ?? ""
        }
    }
}

public struct PaceHistory: Codable {
    public var providers: [String: ProviderHistory]
    public var selectedProvider: UsageProvider

    public init(providers: [String: ProviderHistory] = [:], selectedProvider: UsageProvider = .codex) {
        self.providers = providers
        self.selectedProvider = selectedProvider
    }

    public subscript(_ provider: UsageProvider) -> ProviderHistory {
        get { providers[provider.rawValue] ?? ProviderHistory() }
        set { providers[provider.rawValue] = newValue }
    }

    private enum CodingKeys: String, CodingKey { case providers, selectedProvider }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.providers) {
            providers = try container.decode([String: ProviderHistory].self, forKey: .providers)
            let selection = try container.decodeIfPresent(String.self, forKey: .selectedProvider) ?? "codex"
            selectedProvider = UsageProvider(rawValue: selection) ?? .codex
        } else {
            // Version 1 stored a single Codex record at the root. Preserve its budget.
            let legacy = try ProviderHistory(from: decoder)
            providers = [UsageProvider.codex.rawValue: legacy]
            selectedProvider = .codex
        }
    }
}
