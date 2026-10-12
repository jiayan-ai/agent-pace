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

需要 macOS 13 或更新版本，并已安装、登录 ChatGPT / Codex 桌面应用，或 Codex CLI。下载包包含 Apple Silicon 和 Intel 两种架构；已在 Apple Silicon 上运行验证，Intel 尚未实机验证。应用使用本机现有的 Codex 登录状态，不需要填写 API Key。Claude 使用 **Claude 桌面应用中 Code 的登录**，不要求登录终端版。

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

使用官方 [Codex App Server 接口](https://learn.chatgpt.com/docs/app-server)：`initialize`、`account/read`、`account/rateLimits/read`、`account/usage/read`。不会调用 `turn/start` 或 `account/rateLimitResetCredit/consume`，不会创建聊天、发起模型推理或消耗重置券。

Codex 由已安装的 Codex 程序管理登录，小工具不读取其认证令牌。账户标识（ID 或邮箱）与工作区路由仅取哈希用于区分预算；不保存明文邮箱。额度快照、每日基线、reset 券信息和近 30 天日用量保存在 `~/Library/Application Support/CodexPace/state.json`，沿用旧名称以保留升级前的记录。历史只在本机分析，不上传给其他服务。错误信息不记录原始服务响应。

Claude 读取桌面应用 `config.json` 中的加密 OAuth 缓存，仅在内存中使用登录令牌，通过 `api.anthropic.com/api/oauth/usage` 和 `/api/oauth/profile` 查询额度与核对账户。解密通过 macOS 钥匙串中指定的 `Claude Safe Storage` 项目。不会保存令牌、轮换登录或修改 Claude 的配置，也不读取浏览器 Cookie。

首次使用默认不连接 Claude，也不访问其钥匙串。点击「连接 Claude 桌面」，阅读权限说明并选择「继续连接」后，才会请求系统授权。后台查询禁止弹出钥匙串对话框；没有权限时停止自动连接，等待用户手动重连。可在「怎么算出来的」中断开 Claude，停止后续访问；这不会撤销在系统钥匙串中已经授予的权限。

**授权范围：** `Claude Safe Storage` 是解密本机 Claude 登录资料所用的密钥，权限范围大于「只查看额度」。当前代码只用登录令牌查询额度与核对账户，这不是官方提供的额度专用授权。系统弹窗要求的是登录钥匙串密码，通常与 Mac 登录密码相同，密码由 macOS 处理。选择拒绝不会影响 Codex 功能。

Claude 的接口和桌面缓存格式并非稳定的第三方公开协议，升级可能需要适配。登录过期时，在 Claude 桌面应用进入 Code 并完成登录，再点刷新。没有有效数据时显示待同步或上次记录，不猜测重置时间。Claude 各入口共享订阅额度；此处显示的是订阅额度，不能单独分离桌面 Code 的消耗。

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

验证真实账户连接：

```sh
"dist/Agent Pace.app/Contents/MacOS/AgentPace" --check-connection
"dist/Agent Pace.app/Contents/MacOS/AgentPace" --check-claude
```

没有第三方依赖。使用 SwiftUI + AppKit，构建产物采用本机临时签名，未进行 App Store 分发或公证。自动发现 ChatGPT / Codex 标准安装路径及常见 CLI 路径；如果升级后的应用改变程序位置，需要更新发现逻辑。

Developer ID 签名、公证提交及票据装订流程见 [签名与公证](docs/NOTARIZATION.md)。脚本准备好并不等于 Apple 已接受公证；只有验收全部通过的产物才会带 `-notarized.zip` 后缀。

## 开发与反馈

自动检查在 macOS 上运行计算、数据解析、账户隔离和钥匙串交互测试，并构建应用。测试使用合成数据，不需要登录账户。

报告问题时可附 macOS 版本、应用版本和错误提示；请勿提交登录令牌、钥匙串密钥、Claude 配置文件或完整个人用量记录。

此项目与 OpenAI、Anthropic 无隶属关系。仓库暂未指定开源许可证。

## 退出与移除

点击面板右下角菜单 →「退出 Agent Pace」。如启用了登录启动，先关闭该选项，再删除应用。删除上述 Application Support 下的 `CodexPace` 文件夹可清除本地预算记录。
