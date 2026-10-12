# Developer ID 签名与公证

此流程用于 GitHub 等 App Store 以外的分发。需要付费 Apple Developer Program 的有效团队、包含私钥的 **Developer ID Application** 证书，以及可访问该团队公证服务的凭据。创建 Developer ID 证书需要 Account Holder 权限。参见 [Apple 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。

## 一次性配置

1. 登录 [Apple Developer 账户](https://developer.apple.com/account/)，确认会员资格和团队。没有会员资格时由账户持有人完成注册、协议与付款。
2. 在 Xcode 的账户证书管理，或 Apple 网站 Certificates, Identifiers & Profiles 中创建 Developer ID Application 证书并安装到本机钥匙串。网站流程需要本机生成的 CSR；创建 CSR 时的私钥留在本机。不要把证书私钥或 `.p12` 提交到 GitHub。
3. 执行 `security find-identity -v -p codesigning`，应能看到有效的 Developer ID Application 身份。只有证书而没有对应私钥不能签名。
4. 在本机交互式终端配置公证凭据：

```sh
xcrun notarytool store-credentials agent-pace-notary
```

按提示输入 Apple ID、Team ID 和 App 专用密码；专用密码由账户持有人在 Apple 账户中创建。不要将密码、恢复码、私钥粘贴到聊天、脚本、命令行参数或仓库。该命令会验证凭据并保存到本机钥匙串。也可按 Apple 文档使用团队允许的 App Store Connect API 密钥。

## 构建、提交、取回票据

把以下示例替换为 `find-identity` 返回的准确名称或 SHA-1。身份名称不是密码。

```sh
export AGENT_PACE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export AGENT_PACE_NOTARY_PROFILE='agent-pace-notary'
bash scripts/notarize-release.sh submit
```

脚本会预检证书及钥匙串 profile，构建两个架构，使用 Hardened Runtime 和安全时间戳签名，并提交 ZIP。应用不需要绕过库验证或允许未签名代码的额外 entitlement。提交不阻塞等待 Apple 处理。

```sh
bash scripts/notarize-release.sh status
bash scripts/notarize-release.sh finish
```

只有服务端状态为 `Accepted`，`finish` 才会对原提交的应用装订票据，并依次运行 `stapler validate`、`codesign --verify --deep --strict` 和 Gatekeeper `spctl --assess`。全部通过后输出 `dist/Agent-Pace-VERSION-universal-notarized.zip` 及 SHA-256 文件，再上传至对应 GitHub Release。

提交记录和原始上传包保留在被 Git 忽略的 `dist/notarization/VERSION/`；不要在等待期间删除。相同版本已有提交记录时脚本拒绝重复提交。如果上传中断但结果不明，先用 `xcrun notarytool history --keychain-profile agent-pace-notary` 查证，再恢复相应 submission ID；不要盲目重传。被拒绝的日志可以用 `notarytool log` 获取，`finish` 在 `Invalid` 或 `Rejected` 时也会保存日志。修改二进制后需要重新签名并公证，不能复用旧票据。

普通 `bash scripts/build.sh` 在没有 `AGENT_PACE_SIGN_IDENTITY` 时仍只做临时签名，便于开发。它不声称已通过公证。公证脚本在未配置 Developer ID 时直接失败。

完整流程以 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) 和 [自定义公证工作流](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) 为准。
