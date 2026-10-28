# v1.0.91 · 76 书源引擎修复纪实

- 日期：2026-10-28
- Commit：`360926819`（本地分支 `codex/reader-feedback-fixes`，推送分支 `codex/swift-v2-lifetime-reader`）
- 产物：`C:/Users/Edc21/Desktop/SourceReadSwift-1.0.91-unsigned.ipa`
- 校验：12,290,943 字节；SHA256 `5D369DECA82EEC4450080C395BED6F37CAA9344FEDBC21695E05BB35D31F7088`；`1.0.91 / 92`；MinimumOSVersion 16.0；`testzip None`
- CI：iOS run `40691160747` **1248 tests / 0 failures**；IPA run `40691160718` success

## 1. 本轮修复（全部有单测与 CI 证据）

| # | 缺陷 | 证据 | 修复 | 单测 |
|---|---|---|---|---|
| 1 | `@js:` 规则内的 `{{$.id}}` 不插值 | 七猫 `bookUrl`：`var params = { id: {{$.id}}, ... }` 原样进入 JS → 详情 404 | `JSONRuleExtractor.splitSourceSegments` 的 `.js` 分支先做 `interpolateTemplate(object:variables:)` | `testJSONBookURLInterpolatesJSONPathTemplateInsideJSRule` |
| 2 | URL 模板裸字段前缀被当字面量 | 百度 `tocUrl`：`gid@js:'...'` 生成 `data={"gid":gid}` → 目录 0 章 | `DynamicURLResolver` 对 `left` 先按 JSONPath 求值，再退回 HTML 规则，最后才字面量 | `testDynamicURLResolverEvaluatesBareFieldPrefixBeforeJS` |
| 3 | `java.put` 按整次搜索共享，最后一行覆盖 | 爱书音 38 条聚合结果全部用最后一条 B 站 id | `RuleExecutionContext.mergePersistent` + `SearchResultParser.onBookVariables` 逐行捕获差集；`SourceEngine` 按 `(source, bookUrl)` 存储并在详情/目录/正文前回放（上限 400 条 LRU） | `testSearchResultParserCapturesPerRowVariablesForBookURL` |
| 4 | Hutool `SymmetricCrypto.encryptHex` 缺失 | 塔读 `java.createSymmetricCrypto("DES/ECB/PKCS5Padding", ...).encryptHex is not a function` | JS shim 增加 `encryptHex` / `decryptHex` | 真机复测项（`NOT RUN`） |

## 2. 76 源上一轮真机分布（1.0.90，报告 `E:/codex-temp/sourceread/reports/lan-check-20261028-192236.json`）

| 状态 | 数量 | 说明 |
|---|---|---|
| PASS4 | 10 | 搜索≥1 + 详情 + 目录≥1 + 正文>0 |
| FAIL_TOC | 9 | 详情成功，目录 0 项（本轮 2 个已覆盖：百度、爱书音） |
| FAIL_DETAIL | 4 | 详情失败（本轮七猫已覆盖） |
| FAIL | 30 | 搜索阶段失败（含源内 JS 库缺失、接口 401/500、连接超时） |
| LOGIN | 2 | HTTP 401，需要登录 |
| NO_SEARCH_URL | 20 | **源文件本身是空壳：只有名称 + bookSourceUrl，没有 searchUrl / ruleSearch / ruleToc** |
| HTTP_0 | 1 | 顶点小说连接超时 |

> 结论：20 个 `NO_SEARCH_URL` 不是引擎缺陷，是导入文件里残留的占位条目；剩下 46 个 FAIL 需要逐源归因，其中已确认的下一批引擎能力缺口是：源内 `jsLib`/`raw` 预置脚本加载、JSONPath 过滤表达式（`.[?(@.x)]`）、`java.sleep`/`source.get` 之外的聚合桥接。

## 3. 复测步骤（需要 iPhone 安装 1.0.91 并打开局域网服务）

```powershell
$env:PYTHONIOENCODING='utf-8'; $env:PYTHONUTF8='1'
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\lan_source_check.py' `
  --base http://<手机IP>:8080 --keyword 斗破苍穹 --concurrency 3 --timeout 150
```

关注四个定向源：`⭐七猫小说[官方本地接口]API✨`（应进入详情）、`⭐百度小说[官方]v1.0✨`（应拿到目录）、`爱书音`（应拿到正确 id 的目录）、`塔读小说app v0.12`（应不再报 encryptHex）。

## 4. 未完成（按优先级）

1. 76 源真机复测与逐源归因（等 1.0.91 装机 + LAN 服务）；
2. 4 个 UI BUG：iOS16 双引号末字对齐、阅读器底部面板过宽/不透明、搜索键盘点空白收起、键盘弹起带动导航栏；
3. 源内共享 JS 库（`raw` / `jsLib`）加载与 JSONPath 过滤表达式。
