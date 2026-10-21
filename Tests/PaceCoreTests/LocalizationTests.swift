import Foundation
@testable import PaceCore

struct LocalizationTests {
    func testLanguageResolutionAndPersistence() throws {
        try expect(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-US", "en"]) == .simplifiedChinese)
        try expect(AppLanguage.system.resolved(preferredLanguages: ["fr", "en-GB", "zh-Hans"]) == .english)
        try expect(AppLanguage.system.resolved(preferredLanguages: ["zh-TW"]) == .simplifiedChinese)
        try expect(AppLanguage.system.resolved(preferredLanguages: ["fr"]) == .english)
        try expect(AppLanguage.english.resolved(preferredLanguages: ["zh"]) == .english)
        let name = "AgentPace.LanguageChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try expect(AppLanguage.load(from: defaults) == .system)
        AppLanguage.english.save(to: defaults)
        try expect(AppLanguage.load(from: defaults) == .english)
        defaults.set("unsupported", forKey: "appLanguage")
        try expect(AppLanguage.load(from: defaults) == .system)
    }

    func testLiveTranslationAndInterpolation() throws {
        let previous = Localization.language
        defer { Localization.language = previous }
        let error = ClaudeUsageError.throttled(120)
        let message: LocalizedMessage = "近 30 天 · \(14) 天有记录 · \(9) 天活跃"
        let now = Date(timeIntervalSince1970: 1000)
        let window = UsageWindow(usedPercent: 40, windowDurationMins: 300, resetsAt: 11800)
        let pace = ClaudeSessionPace(window: window, now: now)
        let budget = DailyBudget.reconcile(previous: nil, window: window, now: now)
        Localization.language = .english
        try expect(L("今天还可以用") == "Available today")
        try expect(message.text == "Last 30 days · 14 recorded · 9 active")
        try expect(error.errorDescription?.contains("2 minutes") == true)
        try expect(pace.heading == "Suggested hourly allowance" && pace.countdown == "3h 0m")
        try expect(pace.allowance == 20)
        let untrusted = "Account {1} · 50%"
        try expect(L("\(untrusted) · 今日已超额 \(7) 个百分点") == "Account {1} · 50% · Over today's budget by 7 percentage points")
        Localization.language = .simplifiedChinese
        try expect(message.text == "近 30 天 · 14 天有记录 · 9 天活跃")
        try expect(error.errorDescription?.contains("2 分钟") == true)
        try expect(pace.heading == "接下来每小时建议可用" && pace.countdown == "3 小时 0 分钟")
        try expect(DailyBudget.reconcile(previous: nil, window: window, now: now) == budget)
    }

    func testCatalogArgumentsAndEnglishCoverage() throws {
        let expression = try NSRegularExpression(pattern: "\\{[0-9]+\\}|%\\.0f")
        func placeholders(_ value: String) -> [String] {
            let text = value as NSString
            return expression.matches(in: value, range: NSRange(location: 0, length: text.length))
                .map { text.substring(with: $0.range) }.sorted()
        }
        try expect(EnglishStrings.values.count >= 205)
        for (key, value) in EnglishStrings.values {
            try expect(!value.isEmpty)
            let han = try NSRegularExpression(pattern: "\\p{Han}")
            try expect(han.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) == nil)
            try expect(placeholders(key) == placeholders(value))
        }
    }
}
