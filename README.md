# Agent Pace

一个 macOS 菜单栏小工具，告诉你：按照剩余额度和重置时间，**今天还可以用多少个百分点**。

A native macOS menu bar app that turns your remaining Codex / Claude subscription usage into a daily budget. Switch providers, track your pace, and see overspending as a red negative balance.

## 功能

- Codex / Claude Code 一键切换，菜单栏显示当天还可用的额度。
- 按剩余额度和重置时间均摊；当天预算固定，再扣减实际消耗。
- 超过预算显示红色负数，两个平台和各额度窗口分别保存记录。
- 每 5 分钟刷新，支持登录 Mac 时启动。
- Codex reset 券数量、有效期同步；结合近 30 天账户日用量给出使用建议。
- 原生 SwiftUI + AppKit，无第三方库，不自动消耗额度。

## 打开

从 [Releases](https://github.com/jiayan-ai/agent-pace/releases/latest) 下载对应版本的 `Agent-Pace-…-universal.zip`，解压后将 **Agent Pace.app** 拖入「应用程序」文件夹，再双击打开。无需安装开发工具或编译源码。本文描述当前源码功能；已发布安装包的功能以对应 Release 说明为准。

当前下载包采用临时签名，尚未取得 Apple Developer ID 签名及公证。macOS 首次打开可能阻止运行；确认下载来源后，可按 [Apple 官方说明](https://support.apple.com/en-us/102445) 在「系统设置 → 隐私与安全性」选择「仍要打开」。不需要关闭系统安全检查。

面板顶部的开关可切换 **Codex / Claude Code**，菜单栏随之显示「Codex 14.3%」或「Claude 16.8%」一类的数字，点击查看详情。首次运行会自动打开独立窗口；之后可以从面板右下角的菜单再次打开窗口。关闭窗口后，小工具继续在菜单栏运行。

需要 macOS 13 或更新版本，并已安装、登录 ChatGPT / Codex 桌面应用，或 Codex CLI。下载包包含 Apple Silicon 和 Intel 两种架构；已在 Apple Silicon 上运行验证，Intel 尚未实机验证。应用使用本机现有的 Codex 登录状态，不需要填写 API Key。Claude 需要在 **Agent Pace 的连接窗口中登录一次**，之后复用会话自动刷新；无需登录终端版，也不访问 Claude Safe Storage。请使用与 Claude 桌面 Code 相同的账户。

已连接的平台每 5 分钟各自同步一次；切换会保留各自的今日预算、已用记录和所选额度窗口。也可手动刷新。系统从睡眠中醒来会刷新。可以在「怎么算出来的」中选择登录 Mac 时启动。

## 计算方式

每天首次成功同步时：

```text
剩余额度 R = clamp(100 − 已用百分比, 0, 100)
剩余天数 D = max(1, 距重置的秒数 ÷ 86400)
今日预算 B = R ÷ D
今日额度余额 = min(当前剩余额度, B − 当天首次同步后增加的已用百分比)
```

例如，剩余 70%，7 天后重置，今天预算为 10%。随后再用 4 个百分点，今天还可用就是 6%，而不是刷新后再拿剩余额度重新除一次。

超过今日预算时显示负数：菜单栏沿用系统默认颜色和统一字重，详情面板的数字与进度条变红。例如预算 10%、当天用了 17%，显示 **−7.0%**。次日按真实剩余额度重算，不会重复扣除超额部分。菜单栏面板固定在按钮下方，并根据屏幕限制高度；展开说明或屏幕较小时可在面板内滚动。

- 天数保留小数，不足 24 小时按 1 天算，此时可以安排使用全部余额。
- 今日预算在当天固定，跨本地午夜后的首次成功同步重新分摊。时区变更、账户切换、重置时间明显变化或已用比例下降时，重新建立基线。
- 重置时间的秒级浮动不会清空当天记录，避免接口返回的小误差反复重算预算。
- 首次同步前的当天用量没有可靠的百分比历史，因此不推测；面板明确显示记录起点。
- 本地保存预算，退出重开不会把当天的已用额度清零。
- 两个平台默认展示最长周期（通常为周额度）；Claude 还提供 5 小时及服务端返回的模型额度窗口。存在多个额度窗口时可以切换，每个窗口独立计算。不同窗口的百分比分母不同，不直接取最小值，也不保证其他窗口不会先限额。
- 数据缺失不当成 0；到达重置时间后先等待新数据，不擅自假设恢复到 100%。离线时标注上次记录，菜单栏以「≈」提示。
- 百分比的变化以服务端返回的精度为准，显示一位小数并不代表数据有小数精度。

这是均摊使用建议，不会自动消耗额度。

## Reset 助手（1.3.0）

Codex 面板会同步可用 reset 总数及接口提供的每张券的有效期，并从官方 `account/usage/read` 接口读取最近 30 天的每日 Token 活跃度。展开「近 30 天模式与 Reset 明细」可查看图表、活跃天数、常见高用量星期和最近一周的变化。无需读取聊天记录或调用模型。

- 只统计过去 30 个完整日期，使用 UTC 日期轴处理接口日期，剔除当天的不完整数据；缺失日期不当作零。重复日期取最大一条，不累加。
- 至少 14 个有效日记录才生成模式建议。星期偏好至少需要该星期 3 个样本，均值向总体平均值平滑后超过总体 1.2 倍才提示；近 7 天至少 4 个样本、此前至少 7 个样本才计算趋势，1.35 倍以上标为近期较忙。
- 每个 Codex 窗口单独判断：接近耗尽的窗口在 6 小时内自然重置，优先等；已经耗尽且还需等超过 6 小时，提示有继续工作的需要时考虑 reset。
- 窗口余额不超过 10%，且近期较忙或今天 / 明天是常见高用量日，建议下一段集中工作前重新评估 reset。券在 3 天内到期时提示优先顺序，不建议为用券刻意消耗额度。
- 基础额度超过 11 分钟未确认，或已知券到期、窗口时间失效时，先要求同步。月度历史超过 6 小时未成功同步时不使用模式建议。历史接口不可用不影响基础额度。
- 可用总数以服务端为准；明细可能不完整。未返回数量显示未知，不推测为零。

这是可解释的本地规则建议。Token 活跃度不能直接换算成额度百分比，所以不声称准确预测耗尽时间；模型切换、套餐变化和未来工作计划也可能改变用量。**不会自动兑换 reset**，用户需要时回到 Codex 操作。当天均摊预算变为负数本身不构成重置理由。

Claude 当前使用的接口没有提供 reset 券或月度账户历史，因此暂不提供这部分建议，不会猜测券数。Codex 月度记录与额度记录按账户隔离，切换账户会清除旧账户的模式数据。

## 数据与隐私

Agent Pace 不需要 macOS「App 管理」（更新或删除其他应用）权限，也没有应用安装或自动更新功能。可关闭系统设置中的这项授权；「登录 Mac 时启动」是单独的可选登录项设置。

使用官方 [Codex App Server 接口](https://learn.chatgpt.com/docs/app-server)：`initialize`、`account/read`、`account/rateLimits/read`、`account/usage/read`。不会调用 `turn/start` 或 `account/rateLimitResetCredit/consume`，不会创建聊天、发起模型推理或消耗重置券。

Codex 由已安装的 Codex 程序管理登录，小工具不读取其认证令牌。账户标识（ID 或邮箱）与工作区路由仅取哈希用于区分预算；不保存明文邮箱。额度快照、每日基线、reset 券信息和近 30 天日用量保存在 `~/Library/Application Support/CodexPace/state.json`，沿用旧名称以保留升级前的记录。历史只在本机分析，不上传给其他服务。错误信息不记录原始服务响应。

Claude 使用 Agent Pace 自己的 WebKit 网页会话。点击「连接 Claude」，在 `https://claude.ai` 完成一次登录，然后点「同步额度」。与桌面 Code 使用同一账户即可查看共享的订阅额度；不读取 Claude 桌面的配置、OAuth 缓存、Safe Storage 或其他浏览器的 Cookie，也不会请求 Mac 钥匙串密码。旧版桌面连接不会自动迁移，需要重新连接一次。

会话由 WebKit 保存在 Agent Pace 的本地网站数据中，重启后可继续使用。额度同步仅对 `claude.ai` 发起组织列表和 usage 的 GET 请求；桥接给本机预算计算的内容仅包含组织标识、名称及额度窗口，不提取 Cookie 或密码。网页登录本身具有正常 Claude 账户权限，并非官方提供的「额度专用」授权。组织标识仅以哈希写入预算历史，所选组织 UUID 保存在本机偏好中。多组织账户需要明确选择；已选组织消失时不会默默改用另一个。

在「怎么算出来的」中断开连接，会停止同步并删除 Agent Pace 的网站会话；不会退出 Claude 桌面或其他浏览器的登录。登录失效、网页要求验证时停止后台重试并提示重新连接；限流时按服务端提示退避。网络失败仍保留上次记录，并明确标记为未确认。

Claude 的 usage 接口并非稳定的第三方公开 API，网页升级可能需要适配。Claude 或登录服务可能要求人工验证；若验证不支持内置浏览器，工具会保持未连接，不退回钥匙串解密或绕过网站验证。没有有效数据时显示待同步或上次记录，不猜测重置时间。Claude 各入口共享订阅额度；此处显示的是订阅额度，不能单独分离桌面 Code 的消耗。

## 从源码构建

需要 macOS 13+ 和 Swift 6 工具链（Xcode 16+ 或对应的 Apple Command Line Tools）。目前在 Apple Silicon Mac 上验证；Intel Mac 可尝试源码构建，尚未实机验证。

```sh
git clone https://github.com/jiayan-ai/agent-pace.git
cd agent-pace
```

在项目目录执行：

```sh
bash scripts/test.sh
bash scripts/build.sh
open "dist/Agent Pace.app"
```

构建同时支持 Apple Silicon / Intel 的下载包：

```sh
bash scripts/package-release.sh
```

验证真实账户连接（Claude 需先在工具内完成登录；诊断命令不会打开登录窗口）：

```sh
"dist/Agent Pace.app/Contents/MacOS/AgentPace" --check-connection
"dist/Agent Pace.app/Contents/MacOS/AgentPace" --check-claude
```

没有第三方依赖。使用 SwiftUI + AppKit + WebKit，构建产物采用本机临时签名，未进行 App Store 分发或公证。自动发现 ChatGPT / Codex 标准安装路径及常见 CLI 路径；如果升级后的应用改变程序位置，需要更新发现逻辑。

Developer ID 签名、公证提交及票据装订流程见 [签名与公证](docs/NOTARIZATION.md)。脚本准备好并不等于 Apple 已接受公证；只有验收全部通过的产物才会带 `-notarized.zip` 后缀。

## 开发与反馈

自动检查在 macOS 上运行计算、数据解析、账户隔离和网页会话桥接测试，并构建应用。测试使用合成数据，不需要登录账户。

报告问题时可附 macOS 版本、应用版本和错误提示；请勿提交登录令牌、钥匙串密钥、Claude 配置文件或完整个人用量记录。

此项目与 OpenAI、Anthropic 无隶属关系。仓库暂未指定开源许可证。

## 退出与移除

点击面板右下角菜单 →「退出 Agent Pace」。如启用了登录启动，先关闭该选项，再删除应用。删除上述 Application Support 下的 `CodexPace` 文件夹可清除本地预算记录。卸载前可先断开 Claude，以清除本工具保存的网页会话。
