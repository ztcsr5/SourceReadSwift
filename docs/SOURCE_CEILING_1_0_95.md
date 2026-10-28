# 76 条书源与轻悦时光：口径复核与引擎修复清单（1.0.95）

日期：2026-10-29
依据：`E:\codex-temp\sourceread\reports\lan-check-20261028-192236.json`（76 条真机报告）
代码基线：`678bd7151`（`codex/swift-v2-lifetime-reader`）

## 1. 先回答"这 76 条在轻悦时光里基本都能用"

不成立。轻悦时光跑的不是 Legado JSON 书源。

实测证据（本轮重新拉取，未改动）：

| 证据 | 内容 |
|---|---|
| `autobcb/qysg` README 首行 | "一款多平台可用的阅读软件，通过 webview 来运行书源以达到多平台兼容的效果。" |
| README「书源」章节 | 源文件是 JS 函数：`async function search(key,page)` / `info(bookurl)` / `chapter(tocUrl)` / `content(url)` / `getfinds()` / `find(url,page)` / `pay(bookurl,url)` / `getloginurl()` / `login()` / `imagedecrypt(url,image)` / `shouldOverrideUrlLoading(url)` |
| README 全文检索 | 没有 `bookSourceUrl` / `ruleSearch` / `ruleToc` / `ruleContent` 任何 Legado 字段；没有"导入 Legado 源"的入口说明 |
| `autobcb/qysg#9`「无法导入书源」 | 用户拿 Legado 能用的 JSON 导入失败，作者回复"为啥往订阅源里导入书源" |

结论：轻悦时光里的"能用的源"是它自己格式的 JS 源。拿这 76 条 Legado JSON 去对比，等于拿两种不同的文件格式对比解析率。

## 2. 那"没希望"从哪来——真机报告的真实分布

19:22 的 76 条报告（1.0.92 之前的构建）：

| 状态 | 数量 |
|---|---:|
| PASS4 | 10 |
| NO_SEARCH_URL（空壳条目） | 20 |
| FAIL（搜索阶段失败） | 30 |
| FAIL_TOC（目录 0 章） | 9 |
| FAIL_DETAIL（详情失败） | 4 |
| LOGIN | 2 |
| HTTP_0（超时无响应） | 1 |

失败按原因归并后，真正的"引擎缺陷"只占一部分，其余是上游站点或条目本身的问题。

## 3. 本轮已修的 4 个引擎缺陷（有真机日志证据）

| # | 缺陷 | 真机日志证据 | 修复位置 | 受益源 |
|---|---|---|---|---|
| 1 | 桥对象被写进 Legado `@put` 变量表，`java.get('source')` 返回 Swift 结构体描述 | STV 目录 URL 里出现 `&h=BookSource(bookSourceName: %22STV...` | `JSCoreRuntime.evaluate` 只把标量绑定进变量表 | STV - Sáng Tác Việt |
| 2 | `gid@js:` 左侧裸字段不解析，回落成字面量 | 百度小说目录 body 变成 `data={\"gid\":gid}`，响应 0 字节 | `DynamicURLResolver` 依次尝试 `字段` 与 `$.字段` | ⭐百度小说[官方]v1.0 |
| 3 | 列表平铺时未展开"字符串里再套一层 JSON" | 木里番茄 65,166 字符 / 魔丸 6,109 字符 / 日落小说 64,875 字符 / 含遇見 15,731 字符 → 目录 0 章 | `JSONRuleExtractor.appendFlattened` 二次反序列化 | 聚合/番茄系 |
| 4 | URL 选项 `,{...}` 被 `URL(string:)` 百分号编码后丢弃，POST 退化成 GET | 爱下电子目录 URL 变成 `/catalog,%7B%0A%20%20%22body%22...`，30s 超时 | `SourceURLDirective` 识别 `,%7B` 并解码后再解析 | ❤️爱下电子 |

单测：`JSONRuleExtractorTests` / `JSCoreRuntimeTests` / `SourceURLDirectiveTests` 各补 1–2 条回归用例。

## 4. 不是引擎能修的（有实测证据）

| 源 | 证据（本轮实测） |
|---|---|
| 七猫 `api-bc.wtzw.com/1784900` | 404；`/book/1784900`、`/api/v1/book/1784900` 同样 404 → 上游接口已变更 |
| 速读谷 ×3 | HTTP 500 |
| 有听网 | HTTP 404 |
| 集书阁 | 连接超时 |
| 少年梦 / 番茄四合一 | HTTP 401 登录墙 |

## 5. 剩余可修项（按收益排序）

1. **UAA 四合一**：`jsLib` 里 `function getApiUrl(path, data, _)` 被两参调用，`_` 为 `undefined`，`_.java` 直接抛错。这是源自身缺陷，需要改源（`_ = _ || this`）。
2. **塔读小说**：`java.createSymmetricCrypto("DES/ECB/PKCS5Padding","LAP^%O$8").encryptHex` + `document`/`navigator`，需要 DES 分支与浏览器 shim。
3. **书旗小说 ×2**：`bookList` 用 `.[?(@.bookName)]||.[?(@.title)]` 过滤型 JSONPath，接口实际结构是 `{aladdin:{...}, data:[10 本]}`，规则本身已过期。
4. **20 条空壳条目**：没有 `searchUrl/ruleSearch/ruleToc/ruleContent`，引擎无规则可执行；已重建 2 条（天域小说、爱奇电子书，PASS_FULL）。其余需逐条重写规则。
5. **诊断可见性**：`<js>` 列表规则抛异常时被报成"JSON 目录规则未命中（0 项）"，掩盖真实 JS 错误。这是下一步最该补的观测能力。

## 6. 当前口径

| 项 | 数量 | 依据 |
|---|---:|---|
| 已验证 PASS | 12 | 10（19:22 报告）+ 2（重建后真实 HTTP 全链路） |
| 本轮修复预期新增 | +5 ~ +7 | 上述 4 个缺陷覆盖的源，需真机复测确认 |
| 非引擎可修 | 14 | 见 §4（含重名条目按条目计） |
| 空壳待重写 | 18 | 20 − 2 已重建 |
