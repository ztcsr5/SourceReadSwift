# HANDOVER · 1.0.103（书源引擎专项）

- 分支：`codex/reader-feedback-fixes`（推送分支 `codex/swift-v2-lifetime-reader`）
- 版本：1.0.103 / Build 104
- 生成时间：2026-10-29
- 依据：LAN 真机 `http://192.168.31.205:8080` 全量 76 源体检 + 源码静态核对

## 1. 本轮提交

| Commit | 内容 |
|---|---|
| `3ab1d59` | String 助手改为不可枚举（修 `for-in` 污染，七猫 bookUrl 签名错）；部分行 JS 错误透出 |
| `766aa10` | `JSON.parse(String(result))` 间接变量识别（木里/日落目录）；`@js:` exploreUrl 求值；调试端点新增 `step=explore` |
| `463028b` | `_.java` 在参数遮蔽时仍绑定到 `java` 桥（UAA 四合一） |
| `b01090e` | `java.getElements('$..items.*')` 返回 JSON 节点而非字符串（百度目录）；`<js>…</js>$[*]` 链式规则先把 JS 结果解析成 JSON（连尚/百度目录） |

新增测试：`testIndirectJSONParseOfResultReceivesJSONText`、`testJavaScriptExploreUrlProducesCategories`、`testUnderscoreJavaAliasSurvivesShadowedParameter`、`testGetElementsReturnsJSONPathNodes`、`testJSONPathAfterJSSegmentParsesJSONText`。

## 2. 76 源基线（1.0.98/99 真机，2026-10-29 11:57）

- 数据：`E:\codex-temp\sourceread\artifacts\sweep76_share11_1029b.json`
- 脚本：`E:\codex-temp\sourceread\scripts\sweep76_v3.py`
- 结果：**PASS4 = 8 / 76**

| 状态 | 数量 | 说明 |
|---|---|---|
| PASS4 | 8 | 免费追书、番茄小说TS、反代番茄、小原文学网×2、七猫听书、无错、有听网 |
| NO_SEARCH_URL | 20 | 其中 **20 条是空壳**：JSON 里只有 5 个字段（名称/URL/开关），没有任何规则 |
| FAIL_TOC | 7 | 圣灵聚合、含遇见(加发现页)、木里番茄、日落、百度、连尚、爱下 |
| FAIL_DETAIL | 4 | 七猫小说、七猫官方、番茄APP、STV |
| FAIL | 32 | 搜索层：列表未命中 / 站点返回错误 JSON / 相对 URL / 网络超时 |
| LOGIN | 3 | 少年梦、魔丸、番茄四合一（HTTP 401，需登录态） |
| 其它 | 2 | 爱书音（正文 0 字）、顶点（驱动超时） |

### 2.1 空壳条目核对（20 条）

`365小说` 等 20 条在 `shareBookSource11.json` 中只有：
`bookSourceName / bookSourceUrl / bookSourceType / enabled / enabledExplore / customOrder / weight`——
没有 `searchUrl`、`exploreUrl`、任何 `rule*`。**这不是引擎问题，必须补规则**。

站点存活探测（2026-10-29，10s 超时）：

- 可达 15：得奇(deqixs.co)、书音FM、bqg128、小说狂人(czbooks)、爱奇电子书、七猫API、言情(bgnovel)、365小说(shukuge)、阅友(suixkan)、东滩、茶马(chamabooks)、天域(tianyu8)、夜读阁、米读API、八叉书库、宝华书院
- 不可达/异常 5：漫蛙(404)、肉书屋(超时)、台湾小说(403)、御书屋(SSL EOF)

结论：15 条可以通过「探站 → 写 search/detail/toc/content 规则」补齐；5 条先标记失效。


### 2.2 空壳补规则可行性抽样（bqg128）

- 搜索：`/user/hm.html?q=` 先种 `hm/hmt` Cookie，再 `/user/search.html?q=` 返回 54KB JSON 数组（`articlename/author/url_list/url_img/intro`），可写成 `@js` 两步 searchUrl + `$[*]` 列表。
- 目录：详情页 `.listmain dd a`，绝对链接。
- 正文：`/book/<id>/<n>.html` 首次访问只返回 “加载中……”，需要 `getsite` Cookie 并跳转 `/userverify`；纯 HTTP 拿不到正文，必须 webView。
- 结论：空壳站里相当一部分带 JS 反爬（Cookie 校验/webView），补规则成本高于普通 HTML 站；建议按站点分批，先做无 JS 校验的（言情、天域、八叉等）。

## 3. 本轮修复对应的源（待 1.0.103 装机复测）

| 源 | 原失败 | 修复点 |
|---|---|---|
| 七猫小说 / 七猫官方 | FAIL_DETAIL | bookUrl `@js` 输出被 String 助手枚举污染 → 签名参数错 |
| 爱丽丝书屋 | 不支持的 URL 协议 | `bookSourceUrl` 非绝对 URL + 相对 searchUrl → `networkBaseURL` |
| 木里番茄 / 日落 | 目录 0 章 | `var raw = String(result); JSON.parse(raw)` 未命中 JSON 文本分支 |
| UAA 四合一 | `_.java` undefined | jsLib 形参 `_` 遮蔽全局 → 文本改写为 `java` |
| 百度小说 | 目录 0 章 | `java.getElements('$..items.*')` 返回字符串 |
| 连尚读书 | 目录 0 章 | `<js>…</js>$[*]` 链式 JSONPath 未解析 JS 文本 |
| 36 条 `@js:` exploreUrl | 发现页空白 | 新增 JS 分类求值 + 调试端点 `step=explore` |

## 4. 复测方法（装 1.0.103 后）

```powershell
$env:PYTHONIOENCODING='utf-8'
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\verify_named.py'
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\sweep76_v3.py'
```

`verify_named.py` 默认复测：七猫小说、七猫官方、爱丽丝、木里、日落、UAA、书旗、百度、连尚、爱下、圣灵、含遇见。

## 5. 仍未解决 / 下一批

1. **书旗小说（2 条）**：搜索命中 11 项但 bookUrl 为空，`GetUrl()`（jsLib）在无登录态下的行为需真机日志确认（`Token()` 分支）。
2. **爱下电子 / 圣灵 / 含遇见 目录**：需要真机日志确认 tocUrl 与 `init` 的组合；圣灵 toc 规则读取 `src` 变量，本轮未改。
3. **登录态（3 条）**：少年梦/魔丸/番茄四合一返回 401，需要书源登录面板 + `source.getLoginInfoMap()` 数据；这是功能缺口，不是解析缺口。
4. **空壳 15 条**：需要按站点逐条写规则（建议先做 bqg128、言情、天域、夜读阁、东滩、八叉）。
5. **UI/阅读模式队列**（上轮遗留，未在本轮改动）：顶部空白、状态栏、翻页模式章节标题重复、正文双引号 iOS16 对齐、P2 菜单过宽、搜索键盘收起、搜索时导航栏跟随上移。
