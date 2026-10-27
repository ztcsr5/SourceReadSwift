# CODEX 交接 — v1.0.69 / v1.0.70（Build 70 / 71）

> **分支**：`codex/reader-feedback-fixes`
> **代码提交**：`2319dcd`（URL 编码与伪协议）→ `ea1e258`（stage29 期望值）→ `325e6a5`（WebView 嗅探 + Java 兼容类）→ `fc7f997` / `1472b09`（嗅探测试修正）
> **日期**：2026-10-28
> **上一版**：v1.0.68 (Build 69) / `eae2e94`
> **本轮输入**：继续完善书源解析；用户指出「1、2 前面不是改过了吗」——确认 1.0.69 的 URL 编码与分页对齐是上一轮遗留的未提交改动，本轮先收口，再做 WebView 反爬语义

---

## 一、v1.0.69：把「搜索解析为空」的一类根因收口

### 1.1 `{{key}}` 改用 Java `URLEncoder` 语义

`LegadoRuleResolver.percentEncode` 之前用 `.urlQueryAllowed`，`& = + ? / :` 全部原样保留。用户搜「剑来&x」时 query 被 `&` 截断，站点返回空页，诊断里表现为「搜索解析结果为空」。现在按 `java.net.URLEncoder` 逐字节处理：

- 保留 `A-Z a-z 0-9 . - _ *`；
- 空格 → `+`；
- 其余字节 → `%XX`（UTF-8 / GBK 双路径）。

对应测试：`SearchURLResolverTests`
- `abc def` → `abc+def`；
- `剑来&x=1` → `%E5%89%91%E6%9D%A5%26x%3D1`；
- GBK 源 `中文` → `%D6%D0%CE%C4`；
- `LegadoStage29CompatibilityTests` 的端到端期望同步为 `Matrix+Reader`。

### 1.2 伪协议不再进 URLSession

`SourceRequestBuilder.resolveURL` 现在识别 `javascript:` / `about:` / `file:` 等非网络协议，剥掉前缀后相对 source host 解析；`URLSessionSourceNetworkClient` 在发请求前 guard 只允许 `http/https/data`，`-1000` 错误带上 URL 片段。对应诊断里 31 条「URL 格式非法或解析异常」。

### 1.3 分页测量与渲染同一 alignment

`ReaderPageLayoutEngine.measureHeight / lineMetrics` 增加 `alignment` 参数，默认 `.justified`；`ReaderView` 的标题测量显式传 `.natural`。新增 `paragraphStyle(alignment:)` 作为唯一来源，测试锁定默认值、标题值与 `pushOut` 策略。

---

## 二、v1.0.70：WebView 三个 Legado 语义落地

`docs/书源解析能力评估-1.0.60.md` 列的 P0 缺口，本轮全部接上：

| 字段 | Legado 语义 | 本项目实现 |
|---|---|---|
| `sourceRegex` | 嗅探页面内 XHR/fetch，URL 命中正则时把响应体作为正文 | `WebViewFallback.sniffingSource` 在 document start 挂钩 `XMLHttpRequest.open/send` 与 `window.fetch`，响应存入 `window.__sourcereadResources`；页面稳定后取回 JSON 数组，`firstBody(in:matching:)` 选第一条命中 |
| `webJs` | 页面加载后执行脚本，返回值可作为正文 | `evaluateJavaScript` 后在主线程取结果；字符串直接用，JSON 对象/数组序列化后用 |
| `overrideUrlRegex` | 拦截命中正则的跳转 | `decidePolicyFor navigationAction` 命中即 `.cancel` |

`LegadoSourceEngine.ruleWebViewAssets(source:)` 从 `ruleContent.fields` 读取三个字段（兼容根级 `raw` 的手写源）；`content` / `toc` 阶段只要存在 `sourceRegex` 或 `webJs` 就强制走 WebKit，因为普通 HTTP 响应只是空壳。

### 2.1 新增测试

`WebViewResourceSniffingTests`（9 条）：
- 捕获 JSON 解码、坏 JSON 返回空；
- 第一条 URL 命中、无命中、非法正则；
- 大小写不敏感匹配；
- `ruleWebViewAssets` 读取 `ruleContent`、根级回退、空白视为缺失。

`LegadoJavaCompatibilityTests` 新增 4 条：
- `java.math.BigInteger`：`2^13 mod 15 = 2`、hex/dec、`compareTo`、`bitLength`、`intValue`；
- `java.lang.StringBuffer`：append / deleteCharAt / insert / reverse；
- `java.util.concurrent.TimeUnit`：秒/毫秒/分钟换算按 Java 截断；
- `TextUtils.join` 保留 `isEmpty`。

JS 层用 Node 24 单独跑过同一段 shim：输出 `hex=2, eq=true, bits=8, intValue=255, appended=ab12, edited=aX12, reversed=cba, millis=2000, seconds=2, minutes=60000, joined=a,b,c`。

### 2.2 明确没有做的

- `BufferedInputStream` / `ByteBuffer` / `SecretKeyFactory` + `DESKeySpec` 仍未实现（DES 需要完整分组算法，不能只做壳）；
- WebView 嗅探只有纯逻辑单测，没有 WKWebView 端到端 fixture（CI 无本地 HTTP 服务）；
- `overrideUrlRegex` 只拦主框架导航，WKWebView 公共 API 不能拦任意子资源；
- XPath 方言边界未动。

---

## 三、验证

| 项 | 值 |
|---|---|
| v1.0.69 iOS run | `40586973620` / job `122480919833` — **1129 tests / 0 failures** |
| v1.0.69 IPA run | `40586973507` |
| v1.0.69 产物 | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.69-unsigned.ipa`，12,185,173 B，SHA256 `8CED82011AFFE1218BC2C87914A3B05A1DEE2A813471829DCAA9CC0B30A386D0` |
| v1.0.70 iOS run | `40592742506` / job `122500858798` — **1142 tests / 0 failures** |
| v1.0.70 IPA run | `40592742458` |
| v1.0.70 产物 | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.70-unsigned.ipa`，12,196,165 B，SHA256 `AFB31739073490EE430EFCFB00B6C5FAD533E6AB36703B297973FCE9EA8E7E28` |
| 版本 | `1.0.70 / 71`，MinimumOSVersion 16.0，Bundle `com.edc21.SourceReadSwift` |

---

## 四、下一轮建议（按影响排序）

1. **真机验证 WebView 嗅探**：找 3–5 个声明 `sourceRegex` 的 App-API 源，开飞行模式外的真实网络跑搜索→目录→正文，确认返回体不是空壳。
2. **Java 加密类**：`SecretKeyFactory` + `DESKeySpec`（DES/3DES 轮函数）优先，其次 `ByteBuffer`。
3. **XPath 方言冻结**：从真实源抽 20 条表达式做脱敏 fixture，不能翻译时输出 `bridge.error` 诊断，不再静默空值。
4. **诊断分级**：`搜索结果为空` 再细分「选择器未命中 / 命中但字段空 / 响应空」，直接给书源编辑页建议。
5. **iOS 16 真机矩阵**：书架搜索框压导航栏、详情页/主页封面空白、分页顶部留白，仍待真机结论。

---

## 五、关键文件

```
Core/Rules/LegadoRuleResolver.swift            percentEncode（Java 语义）
Core/Network/SourceRequestBuilder.swift        resolveURL + isNetworkScheme
Core/Network/SourceRequest.swift               scheme guard + -1000 URL 片段
Core/Network/WebViewFallback.swift             嗅探 / webJs / overrideUrlRegex
Core/Engine/SourceEngine.swift                 ruleWebViewAssets + 强制 WebKit
Core/JavaScript/JSCoreRuntime.swift            BigInteger / StringBuffer / TimeUnit / TextUtils.join
Features/Reader/ReaderPageLayoutEngine.swift   paragraphStyle(alignment:)
Tests/WebViewResourceSniffingTests.swift       9 条
Tests/LegadoJavaCompatibilityTests.swift       +4 条
```
