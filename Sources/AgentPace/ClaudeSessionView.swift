import SwiftUI
import PaceCore

struct ClaudeSessionView: View {
    let pace: ClaudeSessionPace
    let stale: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("5 小时额度 · 距离重置", systemImage: "timer")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if pace.isFinalHour {
                        Text("即将重置").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
                Text(pace.countdown)
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.8).lineLimit(1)
                Text(pace.awaitingReset ? "等待同步确认新一轮额度" :
                        pace.resetDate.map { "\(resetTime($0)) 重置" } ?? "同步后显示实际重置时间")
                    .font(.caption).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent, in: RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 8) {
                Text(pace.heading + (stale ? " · 上次记录" : ""))
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(pace.allowance.map(number) ?? "—")
                        .font(.system(size: 52, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(pace.unit).font(.system(size: 18, weight: .medium))
                }.foregroundStyle(accent).accessibilityElement(children: .combine)
                Text(pace.isFinalHour
                     ? "不足 1 小时，显示本轮实际剩余额度。"
                     : "按剩余额度与剩余小时数动态均摊。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("百分比以本轮总额度为基准；仍受总周额度及模型限额约束。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(pace.awaitingReset ? "上轮剩余" : "本轮剩余").foregroundStyle(.secondary)
                    Spacer()
                    Text(pace.remaining.map { "\(number($0))%" } ?? "未知")
                        .fontWeight(.semibold).monospacedDigit()
                }
                if let remaining = pace.remaining {
                    ProgressView(value: remaining, total: 100).tint(accent)
                        .accessibilityLabel("5 小时额度剩余")
                }
            }.font(.callout).padding(.horizontal, 3)
        }
    }
}
