# 书源解析兼容性补篇（v1.0.76）

> 基线：`docs/SOURCE_COMPAT_1_0_75.md`（997 条源统计、URL 层对照、真实源回归集）
> 本篇只记录 v1.0.76 的解析语义补齐与验证结果。
> 对照实现：Legado `AnalyzeByJSoup.kt`（本地 `E:\codex-temp\sourceread\refs\legado`）
> 验证：iOS run `40613012622` / job `122569378462` = 1186 tests / 0 failures

## 一、Legado 索引语法：逐条对照

权威实现：`AnalyzeByJSoup.kt` L250-477 `ElementsSingle.getElementsSingle`。

### 1.1 两种写法

| 写法 | 分隔符语义 | 例子 | 结果 |
|---|---|---|---|
| 旧式 | `:` 是**索引分隔符**，不是区间 | `tag.div.-1:10:2` | 取第 -1、10、2 个 |
| 旧式排除 | `!` 前缀 + `:` 分隔 | `tag.div!0:3` | 排除第 0、3 个 |
| 旧式排除（多段） | 段数不限 | `li!0:1:2:3:4` | 排除前 5 个 |
| 新式 | `[...]` 内 `:` 是**区间** | `tag.div[-1, 3:-2:-10, 2]` | 并集 |
| 新式排除 | `[!...]` | `tag.div[!0,2]` | 排除第 0、2 个 |

实现：`parseIndexItems(_:allowRanges:)`。`allowRanges: true` 只在 `[...]` 内；旧式一律 `false`。这正是 1.0.75 之后出现回归的原因——把 `li!0:1:2:3:4` 当区间解析，只剩第一段，精华书阁目录归零。`5ceda53` 恢复“多段独立索引”。

### 1.2 区间展开规则（逐行镜像）

| Legado 行为 | 我们的实现 |
|---|---|
| `start` 省略 = 0；`end` 省略 = `len-1` | 同 |
| 负索引 `+ len` | 同 |
| `start`/`end` 同侧越界 → 丢弃该区间 | 同 |
| 单侧越界 → 裁剪到 `0` / `len-1` | 同 |
| `start == end` 或 `step >= len` → 只取 `start` | 同 |
| `step < 0` → `step + len`（`-step >= len` 时取 1） | 同 |
| `end > start` 正向、`end < start` 反向 | 同 |
| 结果去重且保序 | 同（按出现顺序去重） |

### 1.3 容易写错的三个点

1. **`[1:-1]` 含末元素**。Legado 的 `end` 是闭区间端点，`1:-1` = `1...(len-1)`；按 Python 切片理解会少最后一章。
2. **旧式冒号不是区间**。`ul li.1:3` 是第 1 和第 3 个，不是 1 到 3。
3. **`[-1:0]` 用来整表反向**，不是“空区间”。

### 1.4 测试

`SourceReadSwiftTests/LegadoIndexSyntaxTests.swift`（11 条）覆盖：区间解析、括号翻译、尾部区间、内部区间、越界、反向、排除列表、普通列表、旧式冒号、步长、多段排除。

## 二、`@html` / `@all`：outerHtml 语义

Legado `AnalyzeByJSoup.kt` L229-237：

```kotlin
"html" -> {
    elements.select("script").remove()
    elements.select("style").remove()
    val html = elements.outerHtml()
    if (html.isNotEmpty()) textS.add(html)
}
"all" -> textS.add(elements.outerHtml())
```

我们的实现（`HtmlRuleExtractor.swift`）：

| 规则 | v1.0.75 及以前 | v1.0.76 |
|---|---|---|
| `@html` | 元素内部 HTML / 文本 | 先删 `script`/`style`，再返回整段 outerHtml |
| `@all` | 多元素文本按行拼接 | 多元素 outerHtml 直接拼接 |

影响面：用 `@html` 保留段落标签、或用它做二次清洗的源。`all` 常用于 `chapterList@all` 之类的整块再解析。

`HtmlAttributeSemanticsTests`（3 条）锁定：`html` 去脚本、`html` 保留外层标签、`all` 拼接 outerHtml。

## 三、JSON 列表前导点

QQ阅读 `ruleSearch.bookList = ".bookList[*]"`，真实响应：

```json
{"code":0,"data":{"pageNo":1,"bookList":[{"bid":468914,"title":"斗破苍穹", ...}]}}
```

Jayway JSONPath 的 `.bookList` 从根开始找不到，但 Legado 的 `AnalyzeByJSonPath` 对列表规则会做深度匹配。我们的降级：

```swift
if path.hasPrefix("."), !path.hasPrefix(".."), !path.contains("||"), !path.contains("&&") {
    let descendant = "$.." + String(path.dropFirst())
    ...
}
```

只在直接路径 0 行时触发；`$..bookList[*]` 走既有 `**` 深度扫描（`tokenize` 将 `..` 归一为 `**`）。`JSONListDescendantTests`（2 条）锁定“降级命中”与“直接命中优先”。

## 四、`Packages.okhttp3` 桥

997 条源里有一部分把 HTTP 请求写在 `<js>` 块里（醉读小说、顶点小说一类），调用形态是：

```js
var client = new Packages.okhttp3.OkHttpClient();
var request = new Packages.okhttp3.Request.Builder()
    .url(url)
    .addHeader('User-Agent', ua)
    .build();
var body = client.newCall(request).execute().body().string();
```

v1.0.75 之前 `Packages.okhttp3` 为 undefined，首行抛异常后被源自己的 `catch (e) {}` 吞掉，表现为“搜索为空 / 正文为空”。

v1.0.76 的映射：

| JS API | 落到 |
|---|---|
| `Request.Builder.url/addHeader/header/post/method/build` | 生成带 `__urlString/__method/__body/__headerMap` 的请求对象 |
| `OkHttpClient.newCall(request).execute()` | `__makeConnect(url)` + 套 header/method/body + `execute()` |
| `RequestBody.create` | 字符串 |
| `MediaType.parse` | 字符串 |

`OkHttp3BridgeTests`（3 条）：Builder 生成 URL、GET 带 header 返回 body、POST 转发 body。

## 五、真实源回归

### 5.1 搜索 17 条

| 源 | 行数 | 源 | 行数 |
|---|---|---|---|
| ⚡📂错层小说 | 1 | 松鹤阅读 | 18 |
| 错层小说网 | 1 | 精华书阁手机版 | 20 |
| 笔趣阁[biquge7] | 18 | 看书网 | 17 |
| 开心文学网 | 15 | 阅友小说（优） | 5 |
| 中文万维（优） | 20 | 穿越小说（优） | 100 |
| 茶马小说（优++） | 1 | 起步新榜（优） | 20 |
| QQ阅读 | 10 | 新笔趣阁 | 18 |
| 笔趣阁[biqusa] | 50 | 影书小说[修复] | 50 |
| 爱看书网（优） | 20 | | |

### 5.2 目录 6 条

| 源 | 解析 | Legado 模拟 | 规则 |
|---|---|---|---|
| ⚡📂错层小说 | 4 | 4 | `#allchapter dd` |
| 错层小说网 | 4 | 4 | `id.allchapter@tag.dl@tag.dd@tag.a` |
| 精华书阁手机版 | 20 | 20 | `li!0:1:2:3:4@a` |
| 笔趣阁[biquge7] | 1838 | 1838 | `class.list@li@tag.a` |
| 看书网 | 100 | 100 | `.row[-1]@a` |
| 开心文学网 | 30 | 30 | `.chapterNum@li@a` |

## 六、剩余缺口与测量口径

| 项 | 规模 | 现状 | 处置 |
|---|---|---|---|
| `concurrentRate` | 5 / 997 | 未实现 | 真机出现限流再实现 |
| `options.js` | 1 / 997 | 未实现 | `java.toast` 提示，收益≈0 |
| `@result` | 0 / 997 | 未实现 | 不做 |
| `||` 回退顺序 | 43 搜索 / 16 目录 | 首个非空 | 等反例 |
| `&&` 组合 | 6 搜索 / 19 目录 | 首个顶层操作符切分 | 等反例 |

## 七、验证

```text
iOS run 40613012622 / job 122569378462
Executed 1186 tests, with 0 failures
SEARCH 17 条全部 >= expectedMinimum
TOC 6 条与 emulated 完全一致
```
