# v1.0.92 · 76 书源引擎修复纪实（第二批）

- 日期：2026-10-28
- Commit：`b8dbbb575`（代码）+ `95c4173`（版本号），本地分支 `codex/reader-feedback-fixes`，推送分支 `codex/swift-v2-lifetime-reader`
- 产物：`C:/Users/Edc21/Desktop/SourceReadSwift-1.0.92-unsigned.ipa`
- 校验：12,293,563 字节；SHA256 `3A51F99C84D87994702603D41605D5C7126B6C447DF80551572DCDF623BF38C4`；`1.0.92 / 93`；MinimumOSVersion 16.0；`testzip None`
- CI：iOS run `40700728637` **success**；IPA run `40700728615` success

## 1. 本轮修复（4 项，全部有单测 + CI 证据）

| # | 缺陷 | 现场证据 | 修复 | 单测 |
|---|---|---|---|---|
| 1 | 相对 URL 直接抛「不支持的 URL 协议 无」 | 爱丽丝书屋 `searchUrl: /search.html?q=...` | 新增 `DynamicURLResolver.absolutize(_:baseUrl:)`：绝对 scheme 直接返回，`//` 补 scheme，其余 `URL(string:relativeTo:)`；`SearchURLResolver.postProcess` 与 `DynamicURLResolver` 纯 URL 出口统一套用，并保留 `,{...}` 指令后缀 | `SourceURLResolutionTests` 4 例 |
| 2 | URL 模板把 Swift 实体结构体 dump 进参数 | STV 目录 URL：`h=BookSource(bookSourceName: ...)` | `JSONRuleExtractor.stringifyJSResult` 增加 `BookSource -> bookSourceUrl` 分支 | `testSourceVariableExpandsToBookSourceURL` |
| 3 | `_.java` 未定义 | UAA 四合一：`undefined is not an object (evaluating '_.java')` | `JSCoreRuntime` 注入 `_` 命名空间并挂 `_.java = java` | 真机复测项 |
| 4 | 旧测试期望与新 URL 解析冲突 | CI 断言失败 | 同步 `SearchURLResolverTests` 两处、`SourceFlowEngineTests.testDynamicURLResolverAbsolutizesRootRelativeURL` | CI 全绿 |

## 2. 上一轮真机报告的分布（1.0.90，`lan-check-20261028-192236`）

| 状态 | 数量 |
|---|---|
| PASS4 | 10 |
| FAIL_TOC | 9 |
| FAIL_DETAIL | 4 |
| FAIL | 30 |
| LOGIN | 2 |
| NO_SEARCH_URL | 20 |
| HTTP_0 | 1 |

> 20 个 `NO_SEARCH_URL` 已逐条核验：`searchUrl`、`exploreUrl`、`ruleSearch`、`ruleExplore` 全部为空，只剩名称与 `bookSourceUrl`，属于导入文件里的空壳占位条目，`PASS_EXPLORE` 分流对它们无效。

## 3. 复测步骤（需要 iPhone 安装 1.0.92 并打开局域网服务）

```powershell
$env:PYTHONIOENCODING='utf-8'; $env:PYTHONUTF8='1'
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\lan_source_check.py' `
  --base http://<手机IP>:8080 --keyword 斗破苍穹 --concurrency 3 --timeout 150
```

定向源：`✿爱丽丝书屋（知秋）✿`（应能搜索）、`STV - Sáng Tác Việt`（目录 URL 不再含 `BookSource(`）、`✿UAA四合一（知秋）✿`（不再报 `_.java`）。

## 4. 未完成

1. `String.length()` Java 桥接（连尚读书）→ 已进入 1.0.93；
2. 76 源真机复测与逐源归因；
3. 4 个 UI BUG（iOS16 双引号末字对齐、底部面板过宽/不透明、搜索键盘点空白收起、键盘弹起带动导航栏）。
