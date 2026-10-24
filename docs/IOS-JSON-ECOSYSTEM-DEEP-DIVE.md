# iOS 端 Legado JSON 书源：生态现状与兼容性深度分析

- 项目：`SourceReadSwift2`（纸间）
- 分析日期：2026-10-24
- 分析范围：Legado 3.0 JSON 书源在 iOS/Swift 上的生态、运行时差异、当前实现边界与可执行路线
- 结论口径：**“能导入”不等于“能跑通”，“能跑通一个源”不等于“兼容一个生态”。本文只把有代码或可复现证据的能力写成“已支持”。**

## 0. 两个问题的直接回答

### 问题 1：为什么市面上 iOS 的 JSON 书源软件较少？源阅读等还未开源

**不是“没有”，而是“少、分散、深度参差、上架困难”。**

截至 2026-10-24 的 GitHub 搜索快照中，确实存在多个 iOS/macOS 的 Legado 兼容项目：

| 仓库 | Stars | 技术栈 | 许可 | 观察 |
|---|---:|---|---|---|
| `Kequans/legado-for-mac-pub` | 68 | Swift/SwiftUI | 公开仓库 | macOS 版，不是 iOS |
| `Aminark/legado-ios`（小浣熊阅读） | 53 | Swift/SwiftUI | GPL-3.0 | iOS 15+，侧载 IPA，明确不提供书源 |
| `FactorCitrus/Legado-iOS`（橘阅） | 20 | Swift/SwiftUI | GPL-3.0 | 声明兼容 Legado 3.0 书源与 WebDAV |
| `bennytsai1234/Night-Reader` | 16 | Dart/Flutter | GPL-3.0 | Android 为主；README 明确 iOS 版“没有在 iPhone 上实际测试过” |
| `tomcat117853/LegadoReader-iOS` | 9 | Swift | 公开仓库 | 小型实现 |
| `zhong228/ShuYue`（书悦） | 8 | Swift | 公开仓库 | 声明兼容 Legado/阅读 3.0 |
| `ztcsr5/SourceReadSwift`（本项目） | 0 | Swift/SwiftUI | 当前仓库 | 自建兼容层与 fixture |

这个快照说明三件事：

1. **生态存在，但规模远小于 Android**：头部项目只有几十 stars，和 Legado Android 主仓库不在一个量级。
2. **分发方式以侧载为主**：小浣熊阅读明确写“没有付费 iOS 开发者账号，暂不上架 App Store”，提供 IPA + 自签/TrollStore；Night-Reader 的 iOS 版也是未签名 IPA。原因不是单纯的“技术不行”，而是 App Store 审核、数字内容/IAP、第三方书源版权风险共同作用。
3. **闭源产品（如用户提到的源阅读）无法复用实现**：没有源码就只能做行为观察，不能复用其 Java/JS 桥、Cookie 管理、WebView 登录或图片解码管线；这会显著抬高每一个兼容点的研发成本。

### 问题 2：JSON 想在 iOS 上“完美兼容”为什么难？

因为 Legado 书源不是一份静态 JSON 规范，而是**“JSON 配置 + Rhino JavaScript + Java/Android 宿主 API + Jsoup/CSS + Jayway JSONPath + OkHttp + WebView + Android 文件/字体/图片能力”**的组合协议。iOS 没有 Android Runtime，也没有 Rhino；JavaScriptCore 只提供 JS 语言本身，`java.*`、`android.*`、`importClass`、`Packages`、`load` 这些全部要由 Swift 重新实现。每多一个宿主 API，就多一个兼容面；而书源作者可以任意组合这些 API，所以这是一个**开放集合**，不存在“写完某一天就 100%”的终点。

更准确的目标不是“完美兼容”，而是：

> **可验证的能力矩阵 + 明确的降级边界 + 可诊断的失败原因 + 可持续的 fixture 回归。**

## 1. 为什么 iOS 侧产品少：四个真实约束

### 1.1 分发与审核约束

- App Store 审核指南 2.5.2 要求 App 自包含、不得下载并执行改变 App 功能的代码；4.7 对 HTML5 小程序/游戏有额外条件；5.2.2 涉及第三方知识产权；3.1.1 要求数字内容使用 IAP。书源阅读器天然接近这些边界。
- 结果：多数项目选择 IPA 侧载、AltStore/Sideloadly、TrollStore 或自签，免费账号 7 天过期；这会劝退普通用户，也让开发者缺少稳定收入。
- 这不是说“绝对不能上架”，而是上架需要产品形态、内容合规、IAP 与审核沟通的整体设计，成本远高于“做一个解析器”。

### 1.2 内容与版权约束

- Legado 本身不提供书源；书源由用户导入。阅读器若预置、推荐或变相提供盗版源，风险会迅速放大。
- iOS 审核对“可访问第三方盗版内容”的敏感度高于纯本地工具；这也是很多项目只做“空壳 + 用户自行导入”的原因。
- 对开发者而言，最安全的定位是：**本地规则引擎 + 用户自备源 + 不内置书源/书库 + 明确 DMCA/下架通道**。

### 1.3 经济与维护约束

- 书源站点经常改版、加验证、换加密、换域名；兼容层需要持续维护。
- iOS 开发者数量、侧载意愿、付费意愿都小于 Android；一个 50 stars 的项目很难支撑全职维护。
- GPL-3.0 项目之间不能随意闭源复用；如果参考了 GPL 实现， derivative work 的许可义务必须认真处理。**本项目不复制这些项目的代码，只把它们当作行为参照和测试思路来源。**

### 1.4 工程约束

- Android 侧有现成 Java/Rhino/OkHttp/Jsoup/Android WebView；iOS 侧需要从零搭：
  - `java.*` 的 Swift facade；
  - 同步网络桥（JSCore 内 `java.ajax` 必须“看起来同步”）；
  - SwiftSoup 替代 Jsoup；
  - 自研 JSONPath 方言；
  - WKWebView 登录/验证码状态机；
  - CoreText/CoreGraphics 字体与图片管线；
  - iOS 沙盒下的文件、下载、后台任务。
- 这些不是“写一个 JSON 解析器”能覆盖的，任何一个环节都可能成为某个书源的硬阻塞。

## 2. “完美兼容”的 12 个技术断层

| # | 断层 | Legado/Android | iOS 现实 | 本项目现状 |
|---:|---|---|---|---|
| 1 | JS 引擎 | Rhino，含 `java.*`、`importClass`、`Packages`、`load` | JavaScriptCore，只有标准 JS + 自建 bridge | 已注入 `java`/`source`/`book`/`chapter`/`cookie`/`cache` 等大量 facade；仍是开放集合 |
| 2 | Java/Android API | 任意 Java 类、`android.*`、`Context`、`SharedPreferences` | 无 JVM、无 Android Runtime | 常用 API 已桥接；未实现的调用必须显式诊断，不能静默空值 |
| 3 | DOM/CSS | Jsoup + 扩展伪选择器 | SwiftSoup，选择器/行为不完全一致 | `HtmlRuleExtractor` 自建 `@textNodes`/`@abs:` 等处理；需持续补 fixture |
| 4 | JSONPath | Jayway JsonPath | 自研方言子集 | `JSONRuleExtractor` 已覆盖常见路径/过滤/函数；不是完整 Jayway |
| 5 | 正则 | Java `Pattern` | `NSRegularExpression` | `\Q...\E`、占有量词、命名组、Unicode 属性等存在差异 |
| 6 | 网络栈 | OkHttp，连接池/拦截器/TLS 指纹 | URLSession | 行为、重定向、Cookie、TLS/HTTP2 指纹不同；Cloudflare 场景需 WebView |
| 7 | JS 内同步网络 | Rhino 阻塞调用 | JSCore 同步桥 + 信号量/超时 | 已实现；必须防死锁、超时和主线程阻塞 |
| 8 | 编码 | Java Charset，GBK/GB18030/Big5 | `String.Encoding`/CFString 转换 | 已有解码器；错标 header、BOM、混合编码仍需 fixture |
| 9 | 加密 | JCE 全量 Provider | CryptoKit/CommonCrypto + 自建 | 常见 AES/DES/3DES/RSA/HMAC 已桥接；SM4/GOST/自定义 KDF 未覆盖 |
| 10 | 图片 | `imageDecode` 可返回 `byte[]`/Bitmap，切片拼图 | Data → UIImage/CGImage | 当前以 URL 重写为主；字节级拼图是明确缺口 |
| 11 | 字体 | Android Typeface/TTF cmap | CoreText | `QueryTTF` 已做映射；加密字体/复杂 cmap 仍需补 |
| 12 | 文件/后台 | 任意路径、`un7z`、长时间后台 | App Sandbox、后台任务受限 | ZIP/EPUB 可用；RAR/7z、任意路径、长时批量下载需降级设计 |

补充三个经常被低估的差异：

- **Rhino 的 JS 语义不是 JavaScriptCore 的语义**：`Java.type`、`importClass`、`Packages`、`load`、Rhino 的 `String` 扩展、`java.lang` 自动装箱等，都不是标准 ECMAScript。
- **书源作者按 Android 调试**：他们看到的是 Legado 的 Debug 日志和 Android 行为；iOS 端必须能输出同等粒度的诊断，否则只能“猜”。
- **站点反爬在演进**：TLS 指纹、HTTP/2 指纹、Cloudflare Turnstile、验证码、字体混淆、图片切片，任何一项都可能让“昨天能用的源”今天失效。

## 3. 本项目的真实位置（不是营销口径）

### 3.1 已有工程资产

| 资产 | 位置 | 规模/作用 |
|---|---|---|
| JSONPath 方言 | `SourceReadSwift/Core/Rules/JSONRuleExtractor.swift` | ~101 KB，路径/过滤/函数/转换链 |
| HTML/CSS 规则 | `SourceReadSwift/Core/Rules/HtmlRuleExtractor.swift` | ~49 KB，Jsoup 风格选择器与指令 |
| JS 运行时 | `SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift` | ~276 KB，JSCore + 兼容 prelude |
| Java 原生桥 | `LegadoNativeBridges.swift`、`LegadoHostServices.swift` | ~122 KB，网络/加密/存储/解析 facade |
| 能力样本库 | `SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json` | 13 个真实源快照 |
| 回归 | `SourceReadSwiftTests` | 640+ XCTest（以 CI 实际结果为准） |

### 3.2 刚完成的 payAction 链路（v1.0.23）

本轮把 `ruleContent.payAction` 从“只透传字段”补成可执行链路：

- `PayActionPolicy`：纯 URL 不进入 JS；`{{...}}` 模板逐段求值；`@js:` / `<js>` 交给 runtime normalize；
- 分类对齐 Legado `isAbsUrl()` 与 `isTrue()`：`false/no/not/0/空/null` 为假，其余非空为真；
- `performPayAction`：同一 JS 上下文、Cookie、持久变量、同步网络桥；补齐 `isVip/updateTime/volumeName/wordCount` 变量；
- 购买成功：先 `ChapterContentCacheStore.invalidate`，再刷新目录（对应 Legado `BookContent.delContent` + `loadChapterList`）；
- 诊断：`payAction` 归入 `content` 诊断 stage，不再被静默丢弃；
- `isVip`：布尔字段不再被标题启发式函数覆盖；
- 菜单可见性：v1.0.24 已按 Legado `hasLogin && isVip && !isPay` 实现（`BookChapter.isPay: Bool?`，`nil` 视为未知并保留按钮）。

### 3.3 仍存在的明确缺口

| 优先级 | 缺口 | 影响 | 处理 |
|---|---|---|---|
| P1 | `imageDecode` 字节级拼图 | 少数漫画/反爬源图片不可用 | 建 Data → CGImage 管线，支持切片/拼图/解密 |
| 已完成（P1） | `ruleContent.title` | 正文页标题与目录不一致 | v1.0.24 已在 HTML/JSON 正文响应上执行 title 规则，空/失败回退目录标题；`ContentParserTests` 4 个用例 |
| 已完成（P1） | `isPay` 字段 | 买后仍显示“购买本章” | v1.0.24 目录模型增加 `Bool?`，HTML/JSON 独立解析，按钮条件 `isPay != true`；`ChapterListMetadataTests` / `JSCoreRuntimeTests` |
| P2 | `downloadUrls` | 详情页下载入口不可用 | 要么实现下载队列，要么 UI 隐藏，禁止半成品 |
| P2 | 目录 `wordCount` UI | 信息缺失 | 有值时在章节副标题展示 |
| P2 | `nextContentUrl` 多 URL | 少量源分页失败 | 支持数组/多值并逐页合并 |
| P2 | `replaceRegex` 执行顺序 | 多页合并后替换范围不一致 | 对齐 Legado 的“合并后替换”语义 |
| P2 | Java API 未实现诊断 | 失败只剩空值 | 所有 stub 记录 API 名、源、章节、原因 |

## 4. 可执行路线：把“兼容”变成工程指标

### 4.1 兼容等级（建议写进产品与文档）

| 等级 | 定义 | 验收 |
|---|---|---|
| L0 | 能导入 JSON、字段不丢 | 导入/导出 round-trip |
| L1 | 静态 HTML/JSON 搜索/详情/目录/正文 | fixture 全绿 |
| L2 | 常见 JS + `java.*` 桥 | 能力样本库端到端 |
| L3 | 登录、Cookie、验证码、WebView | 有明确 UI 状态机与人工步骤 |
| L4 | 图片/字体/加密/分页等高级能力 | 字节级 fixture + 真机验证 |
| L5 | 反爬/Cloudflare/TLS 指纹 | 明确“需人工/不支持”，不伪造成功 |

### 4.2 近期（P0/P1）

1. **CI 双绿**：iOS build + XCTest、Unsigned IPA 同一 SHA 通过；失败日志落到 `VERIFICATION.txt`。
2. **`ruleContent.title`（已完成，v1.0.24）**：正文解析后执行 title 规则，回填 `ChapterContent.title`；HTML/JSON 共 4 条测试。
3. **`isPay`（已完成，v1.0.24）**：`BookChapter` 增加可选字段，目录/缓存/JS bridge 透传；菜单可见性改为 `hasLogin && isVip && !isPay`。
4. **`downloadUrls` 决策**：没有下载队列就隐藏入口；不要显示“可下载”却点了没反应。
5. **Java stub 诊断**：未实现的 `java.*` 调用记录 API 名 + 源 + 章节 + 规则，不再静默返回空串。

### 4.3 中期（P1/P2）

1. **imageDecode 字节管线**：JS 返回 `byte[]`/Base64 → `Data` → 切片/拼图 → `UIImage`；用固定 fixture 做像素级对比。
2. **正则兼容层**：把 Java 常用语法（`\Q...\E`、命名组、Unicode 属性、替换引用）转成 NSRegularExpression 可执行形式；不能转的显式报错。
3. **fixture 对拍**：同一书源在 Android Legado 与 iOS 引擎上跑同一输入，记录 JSON/HTML 输出差异；CI 只跑离线 fixture，公网验证单独记录。
4. **源健康度**：连续失败自动降级/禁用，并在书源详情展示失败 stage 与最后错误。
5. **WebView 登录状态机**：明确“需要登录/需要验证码/需要人机验证”的 UI，不在 JS 里假装成功。

## 5. 复现与证据

### 5.1 本地静态检查

```powershell
cd 'D:\Gemini反重力\SourceReadSwift2'
Get-ChildItem SourceReadSwift -Recurse -File -Include *.swift |
  Select-String -Pattern 'payAction|imageDecode|downloadUrls|isPay|ruleContent'
Get-ChildItem SourceReadSwiftTests -Recurse -File -Include *.swift |
  Select-String -Pattern 'PayAction|isVip|imageDecode'
```

### 5.2 生态快照复现

```powershell
# GitHub API（只读）
$h = @{ 'User-Agent' = 'codex' }
Invoke-RestMethod 'https://api.github.com/search/repositories?q=legado+ios&per_page=10&sort=stars' -Headers $h |
  Select-Object -ExpandProperty items |
  Select-Object full_name, stargazers_count, language, description
```

### 5.3 运行时验收

1. 同一 fixture 在 Android Legado 与 iOS 引擎上的输出可对比；
2. 失败输出必须包含：书源、stage、规则、输入摘要、期望、实际；
3. 任何 stub 都有 UI 或日志标识；
4. 公网源验证单独记录时间、网络、Cookie、验证码状态，不混入离线回归结论。

## 6. 参考

- Legado 源码（Android）：`gedoor/legado` 及其公开 fork；本项目参考了 `ContentRule`、`BookContent`、`ReadBookActivity`、`StringExtensions.isTrue/isAbsUrl` 的行为。
- 生态项目（仅行为参照，不复制代码）：
  - `Aminark/legado-ios`（GPL-3.0）
  - `FactorCitrus/Legado-iOS`（GPL-3.0）
  - `bennytsai1234/Night-Reader`（GPL-3.0）
- Apple 审核指南：2.5.2、4.7、5.2.2、3.1.1（以 Apple 当前公布文本为准）。
- 本项目内部文档：`docs/JSON-IOS-COMPATIBILITY.md`、`docs/SOURCE-CAPABILITY-MATRIX.md`、`docs/legado-js-compatibility-matrix.md`。

> 说明：GitHub stars 是 2026-10-24 的瞬时快照，只用于说明生态量级，不代表项目质量或许可可用性。引用 GPL 项目时只做行为对照与测试思路参考，不复制其代码。
