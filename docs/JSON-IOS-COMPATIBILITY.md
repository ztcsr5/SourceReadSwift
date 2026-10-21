# JSON 书源在 iOS 上的兼容性报告

- 适用项目：`SourceReadSwift2`
- 目标格式：Android 开源阅读（Legado）JSON 书源
- 运行时：Swift + JavaScriptCore（无 Android Runtime、无 DOM、无 Java 反射）
- 结论先行：**主链已具备工程化兼容能力，但不是“100% 无差别兼容”**。当前应把兼容性定义为“可验证的能力矩阵 + 明确的降级边界”，而不是营销式全兼容。

## 1. 证据与范围

本报告只基于仓库内可复现的代码和测试，不把“函数名存在”当作“行为已验证”。

| 证据 | 位置 |
|---|---|
| JSONPath 实现 | `SourceReadSwift/Core/Rules/JSONRuleExtractor.swift` |
| JS 运行时与兼容 prelude | `SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift` |
| 同步化处理 | `SourceReadSwift/Core/JavaScript/LegadoJavaScriptCompatibility.swift` |
| 原生桥 | `SourceReadSwift/Core/JavaScript/LegadoNativeBridges.swift`、`LegadoHostServices.swift` |
| 编码 | `SourceReadSwift/Core/JavaScript/LegadoCharset.swift`、`Core/Network/ResponseTextDecoder.swift` |
| 字体反爬 | `SourceReadSwift/Core/JavaScript/QueryTTF.swift` |
| JSONPath 测试 | `SourceReadSwiftTests/JSONRuleExtractorTests.swift`、`LegadoAdvancedJsonSourceTests.swift` |
| JS/桥测试 | `LegadoJavaScriptCompatibilityTests.swift`、`LegadoNativeBridgeTests.swift`、`LegadoJavaCompatibilityTests.swift` |
| 端到端 fixture | `SourceEngineLegadoCorpusTests.swift`、`SourceEngineCLevelFixtureTests.swift`、`LegadoStage25CompatibilityTests.swift` |
| 能力样本库 | `SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json` |
| 目录元数据测试 | `SourceReadSwiftTests/ChapterListMetadataTests.swift` |

## 2. JSONPath 方言：支持什么，不支持什么

`JSONRuleExtractor` 不是 Jayway JsonPath 的完整移植，而是面向 Legado 书源的方言子集。

### 2.1 已实现

| 能力 | 形式 | 说明 |
|---|---|---|
| 根/成员 | `$.data.list`、`data.list` | 支持点号路径 |
| 递归下降 | `$..name` | 包含数组元素遍历，测试覆盖“数组元素只访问一次” |
| 通配 | `$[*]`、`$.*` | 数组/对象展开 |
| 索引 | `$[0]`、`$[-1]` | 负索引 |
| 切片 | `$[start:end]`、`$[start:end:step]` | 支持负 start/end/step |
| 联合 | `$['a','b']`、`$[0,2]` | 去重并保持首次出现顺序 |
| 过滤器 | `$[?(@.x == 1)]` | 支持 `=~`、`==`、`=`、`!=`、`>`、`<`、`>=`、`<=` |
| 集合谓词 | `in`、`nin`、`subsetof`、`anyof`、`noneof`、`contains`、`size`、`empty`、`exists` | 面向书源常见过滤 |
| 函数 | `length/size/count/value/match/search/keys/first/last/min/max/sum/avg/concat/append/index` | 过滤器内支持 `length/count/match/search/value` |
| 指令前缀 | `@json:` | 字符串化 JSON 自动解码 |
| 引号 key | `$['a-b']` | 支持特殊字符 key |
| 转换链 | `##regex##replacement`、`||`、`&&`、`%%` | 与规则转换器组合 |

### 2.2 明确差异

1. **不是完整 Jayway**：未实现所有函数、所有过滤器语法和所有类型强制规则。遇到新源时必须以 fixture 验证，不能假设 `$.` 开头就一定能跑。
2. **属性查找大小写敏感**：测试 `testJSONPathPropertyLookupIsCaseSensitiveLikeRJPath` 已锁定该行为；源字段大小写不一致时需要显式规则或兼容层。
3. **数组上的 bare member step 有扩展**：实现会对数组元素自动 map，这是为了贴近 Legado/rjpath 的书源写法，不等同于标准 JSONPath。
4. **对象上的过滤器只保留 value 为 object 的条目，并按 key 排序**：这是当前实现的确定性策略，和某些实现的“保留任意 value”不同。
5. **转换链是项目自己的规则层**：`##`、`||`、`&&`、`%%` 的行为由 `RuleTransformParser`/`JSONRuleExtractor` 定义，不应描述成 JSONPath 标准。

### 2.3 兼容策略

- 新增源先跑 `JSONRuleExtractorTests` 的最小表达式；
- 失败时记录“表达式 + 输入 JSON + 期望值 + 实际值”，不要只报“解析失败”；
- 对无法支持的语法，优先在书源导入阶段给出可读诊断，而不是运行时静默返回空。

## 3. JavaScriptCore：能力与边界

### 3.1 已接入的桥

`JSCoreRuntime` 注入了 `__nativeLegado`、`__nativeRule`、`__nativeJsoup`、`__nativeJXNode` 等桥，覆盖：

- 网络：`java.ajax/get/post/fetch/connect/ajaxAll/head`，响应状态、header、bytes、final URL；
- 解析：`java.getString/getStringList/getElements`，CSS/XPath/JSONPath，Jsoup/JXNode；
- 存储：`java.put/get/remove/getStr/putJson/getJson`；
- 编码/加密：Base64/Hex、MD5/SHA/RIPEMD160/HMAC、AES/DES/3DES、RSA、`createSymmetricCrypto/createAsymmetricCrypto/createSign`；
- 字符串/集合/正则：`StringBuilder`、`HashMap`、`ArrayList`、`Pattern/Matcher`；
- 时间/工具：`java.timeFormat`、`java.log` 等；
- 字体：`java.queryTTF` + `QueryTTF.swift`；
- ZIP：`java.unArchiveFile`、`getZipStringContent`、`getZipByteArrayContent`（ZIPFoundation）；
- 验证码：`java.getVerificationCode` 走 SwiftUI Sheet 人工闭环。

### 3.2 必须写清楚的 stub / 降级

| API | 当前行为 | 影响 |
|---|---|---|
| `java.androidId()` | 返回固定字符串 `a1b2c3d4e5f60718` | 依赖真实 Android ID 做设备绑定的源不可等价 |
| `java.longToast` | 后定义覆盖前定义，返回空字符串 | 只影响提示，不影响主链，但不能宣称完整 |
| `java.startBrowserAwait` | 返回空串/URL，不是真实交互浏览器 | Cloudflare/登录验证类源需要人工或 WebView 方案 |
| `java.openUrl` | 等同 `startBrowser` | 无真实外部浏览器闭环 |
| `java.getWebViewUA` | 存在多处定义，后定义生效，UA 与 Android WebView 不同 | 依赖 UA 的站点可能返回不同页面 |
| `java.htmlFormat` | 存在多处定义，后定义生效 | 清洗结果可能与 Android 版本有差异 |
| `java.un7zFile` / `unrarFile` | 返回空串并记录 unsupported | 7z/RAR 资源不可用；应改用 ZIP 或预解压 |
| `java.getVerificationCode` | 人工输入，无 OCR | 自动化程度受限，但不会伪造识别成功 |

### 3.3 Promise / await 的真实语义

`__syncPromise` 是同步 facade，不是事件循环：

- `java.ajax` 通过同步桥立即返回；
- `await` 在 `LegadoJavaScriptCompatibility.normalize` 中被剥离执行关键字；
- `Promise.then` 立即执行，不能等待真正的异步 I/O；
- 因此“Android 上能 await 的登录/验证码/浏览器流程”在 iOS 上不能原样成立。

这不是实现偷懒，而是 JavaScriptCore 回调与 Swift 并发模型之间的硬边界。正确做法是：

1. 对可同步完成的网络请求，走同步桥；
2. 对必须人工交互的流程，显式建模为 UI 状态机；
3. 对无法在单次规则执行内完成的流程，返回可诊断的 `verification-required` / `unsupported`，不返回假成功。

### 3.4 目录链路：`isVolume` / `formatJs`（已实现）

Legado 目录规则里两个直接影响目录展示的字段已经进入主链，并有 fixture 回归。

**`isVolume`（卷行）**

```json
{
  "ruleToc": {
    "chapterList": "$.data.chapters",
    "chapterName": "title",
    "chapterUrl": "url",
    "isVolume": "isVolume",
    "updateTime": "updateTime"
  }
}
```

卷行（`isVolume` 为 `true` / `"true"` / `"yes"` / `1` 等非空真值）不生成章节，而是写入后续章节的 `volumeName`；`false` / `"false"` / `"no"` / `"0"` / `null` / 空串按普通章节处理。HTML 与 JSON 两条解析路径行为一致，卷行跳过后章节 `index` 保持连续。当前边界：分页目录的卷标题不跨页继承，每页重新开始。

**`formatJs`（章节名格式化）**

```json
{
  "ruleToc": {
    "chapterList": "$.data.chapters",
    "chapterName": "title",
    "chapterUrl": "url",
    "formatJs": "@js: title + '（' + index + '）'"
  }
}
```

`formatJs` 在全量目录（含 `nextTocUrl` 分页）收集完成、章节索引定稿后执行；变量为 `title`、1-based `index`、`chapter`（LegadoBookChapterBridge）与 `gInt`（与 Legado `BookChapterList.kt` 的 `bindings["index"] = index + 1` 对齐）。返回空值 / `undefined` / `null` 或单章抛错时回退原标题，不影响其他章节；支持 `@js:` 与 `<js>...</js>` 两种包装，脚本顶层 `return` 会自动以函数包装重试一次。回归用例：`ChapterListMetadataTests.testFormatJsRunsAfterPaginationWithOneBasedIndex`。

这两项不改变“能力矩阵 + 降级边界”的口径：`preUpdateJs` 仍未执行，目录 `wordCount` 仍未在 UI 展示。

## 4. 为什么“完美兼容”很难

### 4.1 平台能力差异

| Android/Legado 依赖 | iOS 对应 | 结果 |
|---|---|---|
| Java/Android Runtime | 无 | `java.*` 只能做 Swift facade |
| Android WebView + DOM | WKWebView，但规则执行不在 DOM 内 | `document/window` 类脚本需要适配 |
| OkHttp/Java 网络栈 | URLSession + 同步桥 | 连接复用、拦截器、证书行为不同 |
| Android 文件系统/ContentResolver | App Sandbox | 路径、权限、导入方式不同 |
| Android 字体/图片解码 | CoreText/CoreGraphics | 字体 cmap、图片格式支持范围不同 |
| 后台执行模型 | iOS 后台限制 | 批量抓取/下载不能照搬 |

### 4.2 规则生态差异

- Android Legado 生态成熟，书源作者默认目标是 Android API；
- iOS 侧开源同类产品少，已知产品多闭源或未公开源，不能直接复用实现；
- 每个新源都可能引入新的 `java.*` 组合、WebView 行为、加密参数或字体映射；
- 因此兼容性不是“一次写完”，而是“能力矩阵 + fixture 回归 + 失败诊断”的持续工程。

### 4.3 产品边界

必须明确哪些能力是“支持”，哪些是“可诊断降级”：

- 支持：搜索、详情、目录、正文、分页、GBK、常见加密、ZIP、字体映射、基础 JS；
- 条件支持：Cookie、POST、动态 token、图片正文、人工验证码；
- 不支持/不伪造：真实 Android ID 绑定、7z/RAR、自动 OCR、真实付费解锁、无交互 Cloudflare 绕过。

## 5. 与市场产品的差异

- **Android Legado**：规则生态和运行时都围绕 Android，书源数量大，兼容成本低。
- **iOS 同类产品**：多数不开源，无法复用其桥接层；公开资料少，遇到问题只能自建 fixture。
- **本项目的可持续路径**：
  1. 用能力矩阵描述覆盖，而不是宣称 100%；
  2. 用 fixture 把“支持”变成可回归的测试；
  3. 对 stub 明确降级，避免用户以为功能已完整；
  4. 先保证主链稳定，再逐项补高价值 API。

## 6. 当前优先级建议

| 优先级 | 工作 | 验收 |
|---|---|---|
| P0（已完成） | `isVolume` / `formatJs` 目录链路 | `ChapterListMetadataTests` 5 个用例通过 |
| P0 | 为 `startBrowserAwait` / 验证码建立 UI 状态机 | 不再返回假成功，UI 有明确状态 |
| P1 | 把 JSONPath 方言差异写成可执行用例 | 每个差异至少一个 XCTest |
| P1 | 为 `java.*` stub 建立运行时诊断 | 调用时记录 API 名、源、章节、失败原因 |
| P2 | 图片正文 `imageDecode` / `imageStyle` | 明确原生渲染或 WebView 渲染边界 |
| P2 | 7z/RAR 替代方案 | 导入时提示 ZIP/预解压，不在运行时静默空值 |

## 7. 复现与验证

```powershell
cd 'D:\Gemini反重力\SourceReadSwift2'
# 本机无 Xcode，编译/XCTest 走 GitHub Actions
# 静态定位：
Get-ChildItem SourceReadSwift -Recurse -File -Include *.swift |
  Select-String -Pattern 'androidId|startBrowserAwait|un7zFile|imageDecode|payAction'
```

运行时验收必须满足：

1. 同一 fixture 在 Android Legado 与 iOS 引擎上的输出可对比；
2. 失败时输出具体规则、输入、期望、实际，而不是空字符串；
3. 任何 stub 都有 UI 或日志中的明确标识；
4. 公网源验证单独记录时间、网络、Cookie、验证码状态，不能混入离线回归结论。