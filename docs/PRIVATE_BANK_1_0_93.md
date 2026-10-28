# v1.0.93 · 76 书源引擎修复纪实（第三批）

- 日期：2026-10-28
- Commit：`4c1f09b10`（JSON.parse(result)）+ `456767e29`（jsLib length 作用域），推送分支 `codex/swift-v2-lifetime-reader`
- 产物：`C:/Users/Edc21/Desktop/SourceReadSwift-1.0.93-unsigned.ipa`
- 校验：12,298,780 字节；SHA256 `D4A19B66269885B4C7C549C7A7116E48D4475535D05DC69504FE627352011261`；`1.0.93 / 94`；MinimumOSVersion 16.0；`testzip None`
- CI：iOS run `40707761226` **1255 tests / 0 failures / TEST SUCCEEDED**；IPA run `40707761218` success

## 1. 本轮修复（2 项）

| # | 缺陷 | 现场证据 | 修复 | 单测 |
|---|---|---|---|---|
| 1 | `JSON.parse(result)` 在 JavaScriptCore 收到桥接字典，抛 `[object Object]` 语法错误 | 含遇見 `tocUrl`：`JSON.parse(String(result)).Data.BookId` 失败 → 回退 bookUrl（`/books/{id}`，没有 `/chapters`）→ 目录 0 章；番茄APP 详情 / 搜索字段全部 `JSON.parse(String(result))` | `JSONRuleExtractor.evaluateRawJS`：当规则把 `result` 喂给 `JSON.parse` 时，按 Rhino 语义传入**当前对象**的 JSON 文本（正文级=响应体、列表项=条目 JSON、详情=init 产物） | `testJSRuleJSONParseResultUsesCurrentObjectJSONText` 等 3 例 |
| 2 | `rev.length()` Java 字符串方法在 JS 字符串上不存在 | 连尚读书 `TypeError: rev.length is not a function (In 'rev.length()')`，jsLib 的 `did_to_decimal` 中断搜索 | `LegadoJavaScriptCompatibility.normalizeJavaScriptLibrary`：**只对 jsLib** 做 `.length()` → `.length` 词法级重写（跳过字符串/模板/注释/正则） | `testJavaStringLengthCallIsRewrittenToPropertyRead` 等 3 例 |

### 关键回归教训（已写进测试）

全局重写 `.length()` 会破坏宿主门面：`StringBuilder(...).length()`、`java.getFile(...).length()` 是真实方法。首轮 CI（`4c1f09b10`）因此失败 3 个用例，随后把重写作用域收窄到 jsLib：

- `LegadoJavaCompatibilityTests.testStringBufferAppendInsertDeleteAndReverse`
- `LegadoStage10CompatibilityTests.testStringBuilderMutations`
- `LegadoNativeBridgeTests.testFilesystemObjectAndBinaryWriteFacadeStayInSandbox`

## 2. 76 源结构盘点（本轮逐条核验）

| 分类 | 数量 | 结论 |
|---|---|---|
| 空壳占位条目 | 20 | `searchUrl` / `exploreUrl` / `ruleSearch` / `ruleExplore` 全空，只有名称+域名。`PASS_EXPLORE` 分流救不了，必须换完整源 |
| 上游已死 | 3 | 速读谷（HTTP 500 ×3）、有听网（HTTP 404）、集书阁（连接超时） |
| 需要登录 | 2 | 少年梦、番茄四合一：HTTP 401 |
| 依赖自建聚合服务端 | ≥5 | 书山聚合、聚合书库、聚合书源、圣灵聚合（`total_chapters: 0`）、木里番茄（PyFQ 轮询） |
| 引擎可修 | 其余 | 按真机日志逐条归因 |

> 因此“76 个全绿”在现有 JSON 上不成立：天花板是 56 个；其中 5 个依赖外部服务端。

## 3. 复测（需要 iPhone 装 1.0.93 并打开局域网服务）

```powershell
$env:PYTHONIOENCODING='utf-8'; $env:PYTHONUTF8='1'
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\lan_source_check.py' `
  --base http://<手机IP>:8080 --keyword 斗破苍穹 --concurrency 3 --timeout 150
```

检测脚本本轮升级：

1. `EMPTY_PLACEHOLDER`：空壳源本地判定，不再浪费请求；
2. `--alt-keywords 九叔,女配,顾少,柯南`：搜索 0 条自动换词复测，消除女频/轻小说的假阴性；
3. 报告新增实际命中词 `keyword` 字段。

定向观察：`含遇見(加发现页)`（目录 URL 必须含 `/chapters`）、`🍅番茄小说(APP)`（详情应解析）、`连尚读书[官方]`（搜索不再报 length）、`⭐百度小说` / `爱书音` / `STV`（1.0.91/92 修复项）。

## 4. 未完成

1. 真机复测与逐源归因（等 1.0.93 装机 + LAN 服务）；
2. 4 个 UI BUG：iOS16 双引号末字对齐、阅读器底部面板过宽/不透明、搜索键盘点空白收起、键盘弹起带动导航栏。
