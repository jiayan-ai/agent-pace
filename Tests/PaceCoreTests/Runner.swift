import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, file: String = #fileID, line: Int = #line) throws {
    guard try condition() else { throw TestFailure(description: "\(file):\(line): assertion failed") }
}
func require<T>(_ value: T?, file: String = #fileID, line: Int = #line) throws -> T {
    guard let value else { throw TestFailure(description: "\(file):\(line): expected a value") }
    return value
}
func expectThrows<T>(_ operation: () throws -> T) throws {
    do { _ = try operation() } catch { return }
    throw TestFailure(description: "Expected an error")
}

@main
struct Runner {
    static func main() {
        let budget = BudgetTests()
        let client = ClientTests()
        let providers = ProviderTests()
        let keychain = KeychainTests()
        let resets = ResetTests()
        let cases: [(String, () throws -> Void)] = [
            ("日预算与逐点扣减", budget.testDailyAllowanceAndOneForOneSubtraction),
            ("超额显示负数且次日不重复扣减", budget.testSpendingBeyondBudgetShowsNegativeBalance),
            ("小数天数与不足一天", budget.testFractionalDaysAndFinalHours),
            ("跨天重新分配", budget.testNextDayRebalancesRemaining),
            ("重置与服务端修正", budget.testResetAndUsageDecreaseStartFreshBudget),
            ("缺失、过期与耗尽额度", budget.testMissingExpiredAndExhaustedData),
            ("预算保存与恢复", budget.testBudgetSurvivesPersistence),
            ("午夜与时区变化", budget.testDayBoundaryAndTimezoneChange),
            ("多额度窗口及排序", budget.testMultipleBucketsPreferredAndLongestCodexWindowFirst),
            ("兼容旧格式与空值", budget.testLegacyAndNullFields),
            ("只读连接流程", client.testReadOnlyHandshakeAndResponseDecoding),
            ("连接超时与进程退出", client.testTimeoutIsBounded),
            ("Claude 周额度、小时额度与精确重置时间", providers.testClaudeWindowsAndDates),
            ("Claude 缺失重置时间不虚构预算", providers.testClaudeMissingResetDoesNotInventBudget),
            ("切换平台、异步返回与独立预算", providers.testProviderIsolationAndPersistence),
            ("升级保留旧版超额记录", providers.testLegacyMigrationPreservesNegativeBalance),
            ("重置时间秒级浮动不清零当天记录", providers.testResetTimestampJitterKeepsDailySpending),
            ("桌面登录账户、组织与有效期", providers.testDesktopCredentialIdentityAndExpiry),
            ("桌面登录加密格式与无效数据", providers.testDesktopEncryptionFixture),
            ("后台钥匙串读取禁用弹窗", keychain.testBackgroundAccessDisablesUIAndRestoresState),
            ("读取失败恢复状态且无法静默时不访问", keychain.testDeniedAccessRestoresStateAndFailedGuardSkipsRead),
            ("仅显式连接可请求系统授权", keychain.testExplicitConnectionCanAskAndRestoresDisabledState),
            ("旧版本无历史接口仍能同步额度", client.testUnavailableHistoryDoesNotBreakQuotas),
            ("Reset 总数、部分明细与未知状态", resets.testResetCountsAndUnknownDetails),
            ("近月窗口、缺失日期与去重", resets.testRollingMonthAndMissingDays),
            ("星期偏好、趋势和稀疏历史", resets.testBusyWeekdayAndTrend),
            ("实际额度、忙闲模式与自然重置建议", resets.testAdviceUsesActualQuotaInsteadOfDailyOverspend),
            ("过期券与额度重置边界", resets.testExpiringCreditsAndResetBoundaries),
            ("历史持久化、旧数据迁移与账户隔离", resets.testActivityPersistenceAndAccountIsolation)
        ]
        var failed = 0
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") }
            catch { failed += 1; print("FAIL \(name): \(error)") }
        }
        print("\(cases.count - failed)/\(cases.count) checks passed")
        exit(failed == 0 ? 0 : 1)
    }
}
