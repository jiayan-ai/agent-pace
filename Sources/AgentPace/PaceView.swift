import SwiftUI
import ServiceManagement
import PaceCore

struct PaceView: View {
    @ObservedObject var store: PaceStore
    var openWindow: (() -> Void)?
    @State private var showExplanation = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmClaudeConnection = false
    private var accent: Color { store.provider == .codex ? Color(red: 0.32, green: 0.35, blue: 0.87) : Color(red: 0.77, green: 0.42, blue: 0.29) }
    private var overBudget: Bool { (store.validBudget?.overBudget ?? 0) > 0 }
    private var balanceColor: Color { overBudget ? .red : accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Picker("额度来源", selection: Binding(get: { store.provider }, set: store.selectProvider)) {
                ForEach(UsageProvider.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("切换 Codex 或 Claude Code")
            if let selected = store.selected {
                if store.windows.count > 1 {
                    Picker("额度窗口", selection: Binding(get: { store.selectedID }, set: store.choose)) {
                        ForEach(store.windows) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden()
                    .accessibilityLabel("选择额度窗口")
                }
                hero
                metrics(selected)
                if let budget = store.validBudget { todayProgress(budget) }
                else {
                    Label("等待最新额度，确认今天的预算", systemImage: "clock.arrow.circlepath")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if store.provider == .codex { ResetInsightsView(store: store) }
                if store.stale {
                    Label("显示上次记录，尚未确认最新额度", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let error = store.error { errorMessage(error) }
                if store.provider == .claude, !store.claudeEnabled || store.error != nil { claudeConnection }

                if let error = store.persistenceError { errorMessage(error) }
                explanation
            } else {
                VStack(spacing: 14) {
                    Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "gauge.with.dots.needle.0percent")
                        .font(.system(size: 46, weight: .light)).foregroundStyle(accent)
                    Text(store.isRefreshing ? "正在读取你的额度" : "等待额度数据")
                        .font(.title3.weight(.semibold))
                    Text(store.error ?? (store.provider == .codex ? "使用这台 Mac 已登录的 ChatGPT / Codex 账户。" : "使用 Claude 桌面应用中 Code 的订阅额度。"))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !store.isRefreshing {
                        if store.provider == .claude { claudeConnection }
                        else { Button("重新同步") { store.refresh() }.buttonStyle(.borderedProminent).tint(accent) }
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 45)
            }
            footer
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .alert("连接 Claude 桌面", isPresented: $confirmClaudeConnection) {
            Button("取消", role: .cancel) { }
            Button("继续连接") { store.connectClaude() }
        } message: {
            Text("为了复用 Claude 桌面登录，小工具需要读取钥匙串中的 Claude Safe Storage，加密密钥可用于解密本机登录凭证。这不是仅查看额度的专用授权。\n\n当前代码仅使用登录凭证查询额度，不保存令牌。macOS 可能要求你输入登录钥匙串密码；密码由系统验证。之后会每 5 分钟自动刷新，你可以随时断开连接。")
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("Agent Pace").font(.system(size: 16, weight: .semibold))
                Text("每日额度节奏").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let selected = store.selected {
                Text(selected.label.replacingOccurrences(of: "\(store.provider.shortTitle) · ", with: ""))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text((overBudget ? "今日预算已超额" : "今天还可以用") + (store.stale ? " · 上次记录" : ""))
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: overBudget ? "exclamationmark.circle.fill" : "sparkle")
                    .foregroundStyle(balanceColor.opacity(0.75))
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(store.validBudget.map { number($0.leftToday) } ?? "—")
                    .font(.system(size: 62, weight: .medium, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 28, weight: .regular, design: .rounded))
            }.foregroundStyle(balanceColor).accessibilityElement(children: .combine)
            Text("占这个周期总额度的百分比")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 19)
                .fill(LinearGradient(colors: [balanceColor.opacity(0.10), balanceColor.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private func metrics(_ selected: MeteredWindow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Label("周期剩余", systemImage: "circle.dotted").font(.caption).foregroundStyle(.secondary)
                Text(selected.window.remaining.map { "\(number($0))%" } ?? "未知")
                    .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("已用 \(selected.window.usedPercent.map(number) ?? "—")%")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.quaternary).frame(width: 1, height: 66).padding(.trailing, 22)
            VStack(alignment: .leading, spacing: 7) {
                Label("距离重置", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(store.daysLeft.map { String(format: "%.2f", $0) } ?? "—")
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("天").font(.caption).foregroundStyle(.secondary)
                }
                Text(selected.window.resetDate.map(resetTime) ?? "时间未知")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 3)
    }

    private func todayProgress(_ budget: DailyBudget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日预算").font(.callout.weight(.medium))
                Spacer()
                Text("\(number(budget.allowance))%")
                    .font(.callout.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.10))
                    Capsule().fill(budget.overBudget > 0 ? Color.red : accent)
                        .frame(width: max(0, proxy.size.width * budget.progress))
                }
            }.frame(height: 7)
            HStack {
                Text("已用 \(number(budget.consumed))%")
                Spacer()
                Text("从 \(localTime(budget.startedAt)) 首次同步起")
            }.font(.caption).foregroundStyle(.secondary)
            if budget.overBudget > 0 {
                Text("今日已超出均摊预算 \(number(budget.overBudget)) 个百分点。")
                    .font(.caption).foregroundStyle(.red)
            } else if budget.leftToday <= 0 {
                Text("今天的均摊预算已用完。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var explanation: some View {
        DisclosureGroup("怎么算出来的", isExpanded: $showExplanation) {
            VStack(alignment: .leading, spacing: 8) {
                if let budget = store.validBudget {
                    Text("\(number(budget.startingRemaining))% ÷ \(String(format: "%.2f", budget.planningDays)) 天 = \(number(budget.allowance))% / 天")
                        .font(.callout.weight(.medium)).monospacedDigit()
                }
                Text("每天首次同步时，将剩余额度除以距重置的天数；不足 1 天按 1 天算。当天预算固定，再扣除首次同步之后用掉的额度。")
                Text("跨天、切换账户或额度重置后重新计算。百分比指总额度的百分点；这是均摊建议，实际使用仍受其他额度窗口限制。")
                if store.provider == .claude {
                    Text("Claude 各入口共享订阅额度。使用桌面应用的登录同步；登录过期时请打开 Claude 的 Code 页面后刷新。")
                    Text("当前 Claude 接口未提供 reset 券或账户月度历史，因此不推测券数，也不生成月度 reset 建议。")
                    if store.claudeEnabled {
                        Button("断开 Claude 连接") { store.disconnectClaude() }
                            .disabled(store.isRefreshing)
                    }
                }
                Toggle("登录 Mac 时启动", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch { loginError = "请在系统设置 → 通用 → 登录项中检查启动权限。" }
                    }
                if let loginError { Text(loginError).foregroundStyle(.orange) }
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 9)
        }.font(.caption).foregroundStyle(.secondary)
    }

    private func errorMessage(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private var claudeConnection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.claudeEnabled {
                Text("Claude 尚未连接。连接前会说明需要的登录权限。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button("连接 Claude 桌面") { confirmClaudeConnection = true }
                    .buttonStyle(.borderedProminent).disabled(store.isRefreshing)
                Button("打开 Claude") { store.openClaude() }.buttonStyle(.link)
            }
        }.font(.caption)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { store.refresh() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text(store.isRefreshing ? "同步中…" : "刷新")
                }
            }.disabled(store.isRefreshing).buttonStyle(.plain)
            Text(store.provider == .claude && !store.claudeEnabled ? "连接后自动同步" : store.snapshot.map { "\(localTime($0.fetchedAt)) 更新 · 每 5 分钟同步" } ?? "自动同步")
                .foregroundStyle(.tertiary).font(.system(size: 10))
            Spacer(minLength: 0)
            Menu {
                if let openWindow { Button("打开独立窗口", action: openWindow) }
                Button("退出 Agent Pace") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).frame(width: 20)
                .accessibilityLabel("更多选项")
        }.font(.caption).foregroundStyle(.secondary)
    }
}
