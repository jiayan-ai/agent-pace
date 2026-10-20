import SwiftUI
import PaceCore

struct ResetRadarView: View {
    @ObservedObject var store: PaceStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tibo · Reset 动态", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("公开消息").font(.caption2).foregroundStyle(.secondary)
            }
            if store.resetRadarEnabled {
                Text(store.resetRadarAssessment?.title ?? (store.resetRadarRefreshing ? "正在同步 Reset 动态…" : "等待公开消息"))
                    .font(.callout.weight(.semibold))
                Text(store.resetRadarAssessment?.detail ?? store.resetRadarError ?? "每 15 分钟检查公开 reset 记录。")
                    .font(.caption).foregroundStyle(.secondary)
                if let event = store.resetRadarAssessment?.event {
                    record(event)
                } else if let event = store.resetRadar?.feed.latest("global_reset", at: store.now) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("最近全局记录 · \(eventDate(event))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if let url = event.sourceURL { Link("原帖", destination: url).font(.caption) }
                    }
                }
            } else {
                Text("已关闭公开消息同步").font(.caption).foregroundStyle(.secondary)
            }

            Button {
                ResetForecastWindow.shared.show()
            } label: {
                Label("查看 24 / 48 小时预测", systemImage: "arrow.up.right.square")
                    .font(.callout.weight(.medium)).frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            Text("Will Codex Reset · 社区预测，不计入今日预算")
                .font(.caption2).foregroundStyle(.secondary)

            DisclosureGroup("记录与来源", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if store.resetRadarEnabled, let snapshot = store.resetRadar {
                        if let event = snapshot.feed.latest("global_reset", at: store.now) { record(event) }
                        if let event = snapshot.feed.latest("banked_reset", at: store.now) { record(event) }
                        if let date = snapshot.feed.archiveDate {
                            Text("来源更新：\(resetTime(date))")
                        }
                        Text("本机读取：\(resetTime(snapshot.fetchedAt))")
                        if let error = store.resetRadarError { Text(error).foregroundStyle(.orange) }
                        Text("日期按本机时区（\(TimeZone.current.identifier)）展示；只有日期的旧记录保留 UTC 日期。公告时间不等于账户到账时间。")
                    }
                    HStack(spacing: 14) {
                        Link("Tibo 的 X", destination: ResetRadarLinks.tibo)
                        Link("记录来源", destination: ResetRadarLinks.tracker)
                        Button(store.resetRadarRefreshing ? "同步中…" : "刷新动态") { store.refreshResetRadar() }
                            .disabled(!store.canRefreshResetRadar)
                    }
                    Toggle("自动同步公开 Reset 动态", isOn: Binding(get: { store.resetRadarEnabled }, set: store.setResetRadarEnabled))
                    Text("记录由 Codex Reset / Codex Resets 收录。预测在独立网页窗口中查看，不抓取页面上的概率。不会向这些网站发送你的账户、额度或使用历史。")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func eventDate(_ event: PublicResetEvent) -> String {
        event.dateOnlyLabel ?? event.date.map(resetTime) ?? "时间未知"
    }
    private func record(_ event: PublicResetEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.kindLabel).fontWeight(.medium)
                Spacer()
                if let url = event.sourceURL { Link("原始来源 ↗", destination: url) }
            }
            Text("\(event.timeLabel)：\(eventDate(event))")
            Text(event.verificationLabel)
            if let scope = event.scope, !scope.isEmpty {
                Text("适用范围：\(String(scope.prefix(160)))")
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
