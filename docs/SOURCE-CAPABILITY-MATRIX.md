# 书源能力矩阵（2026-09-08 能力样本库）

- 数据源：`SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json`
- 样本数：13
- 采集方式：静态读取书源 JSON，统计字段、规则指令和声明标签；**不代表已对公网目标完成运行时验证**。
- 运行时证据：`SourceEngineLegadoCorpusTests`、`LegadoCapabilityBankTests`、`SourceEngineCLevelFixtureTests` 等 XCTest；公网可用性受目标站点、Cookie、验证码和网络环境影响，必须单独记录。
- 相关文档：`docs/legado-js-compatibility-matrix.md`、`docs/JSON-IOS-COMPATIBILITY.md`

## 1. 总览

| 能力 | 覆盖 | 说明 |
|---|---:|---|
| Search | 13/13 | 全部存在 `searchUrl` 和 `ruleSearch` |
| Detail | 13/13 | 全部存在 `ruleBookInfo` |
| TOC | 13/13 | 全部存在 `ruleToc` |
| Content | 13/13 | 全部存在 `ruleContent` |
| Explore | 13/13 | 13 个样本均声明 `enabledExplore=true` |
| CookieJar | 10/13 | `enabledCookieJar=true` 的源 |
| JS 规则/脚本 | 10/13 | 至少包含 `<js>` 或 `@js:` |
| POST | 7/13 | `searchUrl` 中声明 `method=POST` |
| 非 UTF-8 编码 | 4/13 | 规则中出现 GBK/GB18030 声明 |
| 加密/编码处理 | 6/13 | AES/Base64/Crypto 等字样或 JS 调用 |
| 字体/图文反爬 | 4/13 | 字体、`webJs`、`imageStyle` 等线索 |
| 目录/正文分页 | 12/13 | `nextTocUrl` / `nextContentUrl` / `page` 线索 |
| 元数据扩展 | 8/13 | `wordCount` / `updateTime` 至少一项 |
| VIP/付费字段 | 1/13 | 番茄小说含 `isVip` / `isPay` / `payAction` |

> 统计是“字段存在”而不是“站点可用”。例如 `enabledExplore=true` 只说明源声明了发现页；是否能返回内容仍取决于 `exploreUrl`、登录态和目标站点。

## 2. 逐源能力

图例：`S` 搜索、`D` 详情、`T` 目录、`C` 正文；`E` 发现页、`K` CookieJar、`JS` 脚本规则、`P` POST、`GBK` 非 UTF-8、`CR` 加密/编码、`F` 字体/图文、`PG` 分页、`M` 元数据、`VIP` 付费字段。

| # | 书源 | 复杂度 | 主链 | 扩展与风险 |
|---:|---|---|---|---|
| 1 | 第一版主网🔞 | B | S D T C | E, JS, GBK, PG, M；正文含 `replaceRegex` |
| 2 | 🔞🔲第一版主999 | C | S D T C | E, K, JS, P, GBK, CR, F, PG, M；Cloudflare/浏览器验证线索 |
| 3 | 📪第一版主820 | C | S D T C | E, K, JS, P, GBK, CR, F, PG, M；`searchUrl` 为 `@js:` |
| 4 | 要撸小说 | C | S D T C | E, JS, P, CR, PG, M；`@put` 变量进入搜索体 |
| 5 | 久久小说网 | B | S D T C | E, K, P；POST 搜索 |
| 6 | 希望中文 | C | S D T C | E, K, JS, P, GBK, PG, M；先请求首页取 token/act |
| 7 | 风读小说 | C | S D T C | E, JS, F, PG；`webJs` + 字体资源 |
| 8 | 六月中文网 | A | S D T C | E, K, PG；规则较轻 |
| 9 | 爱下电子书 | B | S D T C | E, K, JS, PG, M；`@js:` 规则 |
| 10 | 速读谷 | A | S D T C | E, K, PG, M；CSS 规则较集中 |
| 11 | 番茄小说 | B | S D T C | E, K, JS, P, PG, M, VIP；JSONPath、`@put`、`downloadUrls`、`payAction` |
| 12 | 小原文学网 | B | S D T C | E, K, P, PG, M；Cookie 清理 + POST |
| 13 | 新版笔趣阁 | A | S D T C | E, K, PG；相对路径和属性选择器 |

## 3. 字段覆盖与实现状态

### 3.1 `ruleSearch`

样本出现字段：

`author`, `bookList`, `bookUrl`, `checkKeyWord`, `coverUrl`, `intro`, `kind`, `lastChapter`, `name`, `updateTime`, `wordCount`

- `checkKeyWord` 已进入 `SearchBook` 并由 `SearchResultParser` 过滤，见 `SourceReadSwift/Core/Models/BookModels.swift`、`SourceReadSwift/Core/Rules/SearchResultParser.swift`。
- `wordCount` / `updateTime` 已进入搜索结果模型和 UI 行。
- `bookList` 支持 HTML/CSS/XPath、JSONPath 和 JS 返回 HTML/JSON 的混合路径。

### 3.2 `ruleBookInfo`

样本出现字段：

`author`, `canReName`, `coverUrl`, `downloadUrls`, `init`, `intro`, `kind`, `lastChapter`, `name`, `tocUrl`, `updateTime`, `wordCount`

- `wordCount` / `status` / `updateTime` / `kind` 已进入 `BookDetail`，见 `BookModels.swift`、`BookDetailParser.swift`。
- `tocUrl`、`coverUrl`、`init` 在主链中已有使用。
- `downloadUrls` 在样本中出现，但当前引擎没有下载链路消费；属于已知边界，不应在 UI 上伪造“可下载”。

### 3.3 `ruleToc`

样本出现字段：

`chapterList`, `chapterName`, `chapterUrl`, `formatJs`, `isPay`, `isVip`, `isVolume`, `nextTocUrl`, `preUpdateJs`, `updateTime`, `wordCount`

- `chapterList` / `chapterName` / `chapterUrl` / `nextTocUrl` / `updateTime` / `isVip` 已进入目录模型和阅读 UI。
- `isVolume`：已进入 HTML 与 JSON 两条目录解析链。规则命中为真的行按卷标题处理：不生成章节、写入后续章节的 `volumeName`，由 `ChapterListPresenter.volumeHeader` 在卷边界渲染标题。与 Legado“保留卷行”的模型差异是：本项目的章节模型不承载伪章节，因此卷行被消费而不是原样保留；跨页目录的 `currentVolume` 目前按页重置，跨页续卷仍是开放点。
- `preUpdateJs`：**当前没有执行点**，规则中的值会被保留/展示，但不会参与目录刷新。
- `formatJs`：已在全量目录（含分页）收集完成、章节索引定稿后执行。脚本变量为 `title`、1-based `index`（与 Legado `index + 1` 对齐）、`chapter`、`gInt`；返回值替换章节标题，空值/`undefined`/`null`/单章异常回退原标题，不影响其余章节。支持 `@js:` 与 `<js>...</js>` 包装，顶层 `return` 会以函数包装重试一次。
- `wordCount`：目录字段可被解析，并已在目录/章节列表副标题展示：`ChapterListPresenter.metadataLabel` 输出 `更新 <时间> · <字数>`；回归 `ChapterListMetadataTests.testChapterListPresenterBuildsMetadataLabelFromUpdateAndWordCount`、`SourceMetadataChainTests.testChapterListPresenterBuildsMetadataLabelFromUpdateAndWordCount`。

### 3.4 `ruleContent`

样本出现字段：

`content`, `imageDecode`, `imageStyle`, `nextContentUrl`, `payAction`, `replaceRegex`, `sourceRegex`, `title`, `webJs`

- `content` / `nextContentUrl` / `replaceRegex` / `webJs` 已有主链处理。
- `imageStyle`：已在数据模型（`ChapterContent` / `ChapterContentCacheEntry`）、排版策略（`ReaderImageStyle` / `ReaderImageSizingPolicy`）与双端渲染层（滚动模式原生 TextKit `NSTextAttachment` 内嵌、翻页模式 `ReaderIllustrationView` 全宽/居中铺满）完整落地，并支持书源自定义请求头（防盗链 Referer/UA）透明转发。
- `imageDecode`：v1.0.26 已从 URL 重写扩展到字节负载：识别 `data:image/...;base64,...`、裸 base64、`java.ajaxBytes` 的 `byte[]` JSON 数组、数字键对象四类形态，按魔数接受 png/jpg/gif/webp/bmp/tiff/heic/avif，单图上限 32 MB；解码结果经 `srdata://` 注册表进入阅读器，普通 URL 与非法负载保持原路径。仍不覆盖“源分多次返回切片、客户端按坐标拼图”的 Canvas 场景。
- `payAction`：已进入阅读器主链。纯 `http(s)://` 直接打开购买页、不进入 JS；`{{…}}` 模板逐段求值；`@js:` / `<js>` 走 JavaScriptCore；结果按 Legado `isTrue` 语义分类。购买成功后失效本章缓存并刷新。v1.0.24 已补 `BookChapter.isPay`，按钮条件为 `hasLogin && isVip && isPay != true`。
- `title`：v1.0.24 已实现。正文 HTML / JSON 响应上执行 `ruleContent.title`，HTML 在 document root 求值（兼容 `<h1>` 在正文容器外），空值或失败回退目录标题；回归 `ContentParserTests` 4 个用例。
- `sourceRegex`：仍需按具体源确认是否进入正文元数据链；没有运行时证据时标记为“待验证”，不能写成已完整兼容。

### 3.5 顶层字段

样本出现：

`bookSourceComment`, `bookSourceName`, `bookSourceUrl`, `complexity`, `enabledCookieJar`, `enabledExplore`, `exploreUrl`, `header`, `inputPath`, `labels`, `ruleBookInfo`, `ruleContent`, `ruleSearch`, `ruleToc`, `searchUrl`

- `inputPath` 是样本采集来源，不应在导入后写回书源配置。
- `complexity` / `labels` 可用于诊断和分级，不应作为运行时能力保证。

## 4. 缺口优先级

| 优先级 | 缺口 | 影响 | 处理建议 |
|---|---|---|---|
| 已完成（P0） | `isVolume` 目录链路 | 分卷目录平铺、卷标题丢失 | 已实现 HTML/JSON 卷行消费与 `volumeHeader` 边界渲染；回归 `ChapterListMetadataTests.testHTMLVolumeRowsBecomeVolumeNamesAndAreNotChapters`、`testJSONVolumeRowsSupportBooleanAndStringFlags` |
| 已完成（P0） | `formatJs` 目录链路 | 依赖 JS 生成章节名的源出现空名/原名 | 已在全量目录后执行，1-based index、单章失败回退；回归 `ChapterListMetadataTests.testFormatJsRunsAfterPaginationWithOneBasedIndex` |
| 已完成（P1） | `preUpdateJs` 目录刷新 | 目录刷新前无法清理/更新状态 | 已在 TOC 请求前执行并支持 `book.setReverseToc`；回归 `ChapterListMetadataTests.testReverseTocFlagReversesCollectedChapterList` |
| 已完成（P1） | `imageStyle` 渲染排版 | 漫画与插图小说排版不当、全宽铺满失效 | 已完成 ReaderImageStyle、双模式适配与防盗链 Header 转发；回归 `ReaderImageStyleTests` |
| 已完成（P1） | `imageDecode` 字节负载 | 图文/反爬源正文插图缺失 | v1.0.26 四类负载解码 + `srdata://` 注册表 + 阅读器渲染；`InlineImagePipelineTests` 7 个用例。仅“多切片 Canvas 拼图”仍需真实样本 |
| 已完成（P1） | `payAction` 付费动作 | VIP/付费源无法从阅读器触发购买 | 已实现 URL/模板/JS 求值、`isTrue` 分类、购后缓存失效与刷新；回归 `PayActionTests`；`isPay` 见下一行 |
| 已完成（P1） | `isPay` 字段 | 已购买章节可能仍显示「购买本章」 | `BookChapter.isPay: Bool?`（旧缓存为 nil）；HTML/JSON 独立解析 `isPay/paid/purchased`；缓存与 `withIndex`/`withTitle` 透传；按钮改为 `hasLogin && isVip && isPay != true`；回归 `ChapterListMetadataTests.testHTMLChapterIsPayIsParsedSeparatelyFromIsVip`、`testJSONChapterIsPaySupportsBooleanStringAndMissingValue`、`JSCoreRuntimeTests.testChapterBridgeExposesIsPayAsBoolean` |
| 已完成（P1） | `ruleContent.title` 正文标题 | 标题只在正文中给出的源显示目录标题 | 已在正文 HTML/JSON 响应上执行 title 规则，空/失败回退 `chapter.title`，回填 `ChapterContent.title`；回归 `ContentParserTests.testHTMLContentTitleRuleOverridesTOCTitle`、`testJSONContentTitleRuleOverridesTOCTitle` |
| 已完成（P1） | `java.*` 未实现 API | 调用即 TypeError，整条规则失败 | v1.0.25 在 prelude 末尾用 Proxy 降级到原生 dispatcher，记录 `bridge.error java.<name>` 并返回空串；回归 `JSCoreRuntimeTests.testUnknownJavaMethodDegradesAndRecordsBridgeDiagnostic` |
| P2（已决策） | `downloadUrls` 未消费 | 详情页下载入口不可用 | 当前不解析也不渲染入口，不存在死按钮；实现前提是完整下载队列/进度/重试，不做半成品 |
| 已完成（P1） | 目录逐章 `wordCount` | 信息缺失，不影响阅读 | 已在紧凑目录与完整目录副标题渲染 `更新 <时间> · <字数>`；`ChapterListPresenter.metadataLabel` 有测试覆盖 |
| P2（语义待固定） | `nextContentUrl` 多值 | 极少数源只读第一页 | 上游源码已不可访问；先用离线 fixture 固化“数组/换行多值”的真实行为，再实现合并 |
| P2（语义待固定） | `replaceRegex` 合并顺序 | 跨页替换范围可能不一致 | 同上：先固化“合并后替换”的可复现样本，再调整执行位置，单 URL 源必须零回归 |

## 5. 回归入口

```bash
# GitHub Actions（本机无 Xcode）
# 1. 运行 iOS workflow
# 2. 运行 Unsigned IPA workflow
# 3. 失败时查看 job/step，不在本地伪造编译结果
```

本地静态检查：

```powershell
cd 'D:\Gemini反重力\SourceReadSwift2'
Get-ChildItem SourceReadSwift -Recurse -File -Include *.swift |
  Select-String -Pattern 'isVolume|preUpdateJs|formatJs|imageDecode|payAction|downloadUrls'
```

新增能力时必须同时补：

1. 模型字段（可选、向后兼容）；
2. 解析器分支；
3. UI 展示或明确不展示；
4. fixture/XCTest；
5. 能力矩阵状态更新。

---

## 6. 更正与补充（2026-10-27，v1.0.60）

- §4 中 `sourceRegex` 的“接入正文元数据链”判断已更正：Legado 的 `sourceRegex` 是 WebView 资源嗅探正则，落点在 `WebViewFallback`，不在 `HtmlRuleExtractor` / `JSONRuleExtractor` / `ContentParser`。证据：Legado `BackstageWebView.kt` 的 `SniffingWebClient.onLoadResource`。
- 新增确认的 P0 缺口：`webJs` 未注入 WebView（当前只作为启用信号，`SourceEngine.swift:801`）、`overrideUrlRegex` 未实现。
- 新增确认的 P1 缺口：Java 兼容类缺少 `BigInteger`、`ByteBuffer`、`TextUtils`、`TimeUnit`、`SecretKeyFactory`/`DESKeySpec`、`BufferedInputStream`/`InputStreamReader`、`StringBuffer`（对照栖阅 `packages_stub.js`）。
- 完整评估与修复路线：`docs/书源解析能力评估-1.0.60.md`。
