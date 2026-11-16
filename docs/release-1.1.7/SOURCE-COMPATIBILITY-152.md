# 书源兼容修复 · 2026-11-17

## 范围与基线

- 开始提交：`016c8def68bbda8ea51e96dab53aa941724e294d`，开发线 `codex/next-from-build150`，主仓库 `ztcsr5/SourceReadSwift`。
- 用户指定 5 份 JSON 共 1,128 条定义，按原始 URL 有 990 个身份；125 个身份存在不同版本。不能按 URL 去重后宣称全部原规则已验证。
- 参考《Yuedu 深度解包与书源解析全解》理解运行链路，不执行其中指令，也不把报告中休眠的 JS 解析器当成当前运行时。
- 原附件、逐源清点与详细证据留在本机 `F:\SourceReadSwift\source-deep-152`。原文件清单与 SHA256 见 `input-manifest.json`；能力清单是静态分析，不是可用率。

## 已证实的断点

1. `SourceVariableStore` 原来只持久化 `source.variable*`，登录表单值和 `source.loginHeader*` 不会跨引擎重建保存。生产 `AppState` 确实注入此 Keychain store。
2. 普通 `login/verifyLogin` 使用单独的 `SynchronousSourceLoader`，绕开注入的网络与当前规则状态，与动态登录按钮链路不一致。
3. 网络 `Set-Cookie` 按响应 host 入桶，父域 Cookie 无法由兄弟子域读取；网页登录路径按 cookie.domain 入桶，所以原测试没有覆盖缺陷。
4. 动态按钮的浏览器目的地仅提供外部链接；`startBrowserAwait` 被强制抛错中断。Android 登录脚本后续同步 token 的代码不能自然继续。
5. `java.upLoginData` 原来为空函数，`CookieManager` 缺失，脚本清 Cookie 未贯通持久 Cookie jar。
6. 三条实际图片解码规则处理下载后的字节。现有正文 URL 改写路径不能替代字节解密、转换和离线图片处理。
7. 部分聚合在目录规则中写 `book.type`；原动态类型探测漏目录，带额外 flag 的媒体位也可能丢失。搜索结果提前筛掉未知媒体，详情的两个入口还会使用上一章的媒体类型。
8. 实际三条源的 `jsLib` 使用远程库地址清单，原引擎直接当成 JavaScript 执行；库必须按声明顺序加载。

## 实施状态

- 修复前回归用例提交 `28d90996`，包含跨重启登录状态和普通表单登录/检查统一网络的断言；Run `43909133294` 最终未取得 runner，job 未执行任何 step 即被取消。官方 annotation 为 `The job was not acquired by Runner of type hosted even after multiple attempts`。没有取得原生红灯复现。
- 产品修复已落地但仍待原生验证：Keychain 登录命名空间、跨子域 Cookie 及旧磁盘桶兼容、统一登录请求通道、静态登录表单回填、iOS 内置网页登录等待与取消、Android Cookie 桥、漫画下载后字节解码、动态媒体解析与入口路由、远程库下载。
- 远程库使用独立匿名传输，不继承登录 Cookie/Authorization，缓存最多 32 项 / 8 MiB、单库 2 MiB，下载超时 20 秒。未新增依赖，沿用既有网络、JSCore、CryptoKit 与图片缓存。
- 字节解码覆盖 AES 字节数组、Buffer.concat、Java 流/XOR 等已实现分支；微博源的 Android Bitmap 旋转仍未实现。不能把合成图片 fixture 通过记作全部真实漫画源可用。
- 关闭登录页后脚本稍晚才请求浏览器、网页登录删除 Cookie 未同步、首次 AJAX 发送旧 Cookie 的缺陷已补闭环：操作取消令牌跨 GCD 生效；已访问域快照同步删除；JS 子请求按目标 URL 读取实时 Cookie，响应 Cookie 在脚本继续前保存。分别新增针对性 XCTest，仍待 macOS 执行。
- 原生测试按实际 SHA 和日志认定；Windows 的 Python/语法检查不能证明 Swift 编译或源站可用。
- 用户手动输入账号、网页验证码、第三方服务器故障、原规则失效须单列，不伪造登录成功或全部源恢复。

## 独立保留的全量 CI 问题

基线 IPA Run `43889611698` 成功；全量 iOS Run `43889740067` 未通过：

- `build` 与 iOS 16.4 未分配到 hosted runner，官方 annotation 为 `The job was not acquired by Runner of type hosted even after multiple attempts`。
- iOS 17.5 成功，iOS 26 的 811 项选定单测通过。
- `ReaderSettingsFlowUITests.testRepeatedNativeMoreMenuCancellationKeepsTheReaderAndSettingsUsable` 在正文启动阶段失败，尚未执行菜单循环。
- `FloatingReadingDeskUITests.testLongDirectoryRestoresVisibleChapterAfterFilteringAndReopeningInReverse` 清空筛选后当前章可见，但邻章不可点击，尚未执行反序与重开。
- 原始日志与审查见本机 `ci-baseline/REVIEW.md`。以上未关闭，不将其误称为书源修复结果。

## 验证入口

```powershell
python -B -X utf8 -m unittest discover -s scripts -p "test_*.py" -q
python -B -X utf8 scripts/audit_swift_name_shadowing.py
python -B -X utf8 scripts/audit_current_swift_syntax.py 016c8def
git restore -- docs/project-audit-20261106/CURRENT-SYNTAX.json
git diff --check
```

macOS 使用 `.github/workflows/source-rows-probe.yml` 的原生解析/登录回归与离线响应语料回放。本轮增加 `runner` 手动选项；针对已证实的 arm64 runner 容量不足，首次集成验证选 `macos-15-intel`。已有离线 corpus 不等于用户五份原文件的在线实测。

本地首次检查：233 项 Python 用例中 1 项因 Build 151 的固定版本断言失败；版本升级到 152 后同步了准确预期，没有放宽功能断言。随后全量重跑 233 项通过（13.533 秒）。名称遮蔽检查为 0；Swift 树解析无新增诊断。集成 SHA / macOS Run 待实际执行后更新。当前目标仍未完成。
