# CODEX 交接 — v1.0.71（Build 72）

> **分支**：`codex/reader-feedback-fixes`
> **代码提交**：`b876d89`
> **日期**：2026-10-28
> **上一版**：v1.0.70 (Build 71) / `8640fdc`
> **验证**：iOS run `40595399470` / job `122511649649` = **1143 tests / 0 failures**；IPA run `40595399610`
> **产物**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.71-unsigned.ipa`（12,197,026 字节，SHA256 `077D13628530E3A1252E7C19A0559B73E1C84D8AB51FD2F539713C84A06FD0DC`，`1.0.71 / 72`，MinimumOSVersion 16.0）

---

## 一、先回答「1、2 不是改过了吗」

| 用户指的第几项 | 结论 | 代码证据 |
|---|---|---|
| 1. 响应类型自动纠错（JSON 规则打 HTML 或反之） | **已经做了，本次没有重做** | `SearchResultParser.parse` L30-66 与 `ChapterListParser.parsePage` L44-80：先按探测结果走一套提取器，**空结果**时换另一套再解析；因为两条链路都用 `compactMap` 丢掉缺书名/缺链接的条目，所以「列表命中但字段全空」也会塌成空结果并触发互查。历史提交：搜索 `295fe30`（v1.0.6）、目录 `23e0834`（v1.0.43） |
| 2. 超时改成 20 秒 + 重试 | **半做过**：阶段级 20 秒和超时重试早就有，单请求还卡在 12 秒 | `SourcePipeline` L91 `timeout: TimeInterval = 20`、L157-165 超时后二次尝试；`SourceRequestBuilder.resolvedTimeout` 之前是 `?? 12`——请求 12 秒就断，慢源在 12-20 秒之间本来能返回，却先被单请求掐死，重试也只剩 8 秒 |

所以本轮只补真正缺的那一半：**把单请求预算对齐到阶段预算**，顺带把「空解析」拆成可执行的三种诊断。

---

## 二、本轮改动

### 2.1 单请求预算 12s → 20s

- 新增唯一常量 `SourceRequestBuilder.defaultTimeout = 20`，`resolvedTimeout` 的兜底值改为它；`directive.timeout` / `customConfig` / `raw` 的优先级与 `1...120` 夹取不变。
- 与 `SourcePipeline` 的阶段预算一致：死源最坏耗时仍是 20 秒（和旧的 12+8 相同），但 12-20 秒才返回的慢源现在能成功。
- Legado 上游 `HttpHelper.kt` 是 connect/read 各 15 秒；本项目取 20 秒是为了填满阶段窗口，属于有意偏差，改常量即可回退。

### 2.2 空解析诊断三级化

之前所有空结果只有一句「搜索解析结果为空」/「Chapter list is empty」，无法区分「选择器没命中」和「命中了但字段为空」。现在分别报：

| 阶段 | 新文案 |
|---|---|
| 搜索 HTML | `搜索列表规则未命中（0 个节点，响应 N 字符）` / `搜索列表命中 N 个节点但书名或链接为空` |
| 搜索 JSON | `JSON 列表规则未命中（0 项，响应 N 字符）` / `JSON 列表命中 N 项但书名或链接为空` |
| 目录 HTML | `目录规则未命中（0 个节点，响应 N 字符）` / `目录规则命中 N 个节点但章节名为空` |
| 目录 JSON | `JSON 目录规则未命中（0 项，响应 N 字符）` / `JSON 目录命中 N 项但章节名为空` |

分类器按 `SourceEngineError.empty` 分支判 `emptyResult`，不依赖文案，健康度统计不受影响。

### 2.3 测试与版本

- 新增 `BookSourceTests.testRequestBuilderDefaultsToThePipelineStageBudget`：无 directive / customConfig / raw 时 `request.timeout == 20`。
- 版本四处同步：`project.yml`、`Info.plist`、`AppVersion.swift`、`SearchURLResolverTests` → `1.0.71 / 72`。

---

## 三、验证证据

- CI run `40595399470`（iOS）：build success → test success，**1143 tests / 0 failures**（v1.0.70 为 1142，新增 1 条）。
- IPA run `40595399610`：`SourceReadSwift-unsigned-ipa` 12,099,609 B → 解包后 IPA 12,197,026 B；`CFBundleShortVersionString 1.0.71`、`CFBundleVersion 72`、`MinimumOSVersion 16.0`、`com.edc21.SourceReadSwift`。
- SHA256：`077D13628530E3A1252E7C19A0559B73E1C84D8AB51FD2F539713C84A06FD0DC`。

---

## 四、边界与下一轮

1. **991 源诊断无法在 Windows 复跑**：原始 `轻阅书源诊断数据_1792882175.json` 不在仓库，Swift 引擎依赖 Apple 平台；下一轮需要在真机/模拟器重新导出，才能验证新诊断文案的分布。
2. `nextTocUrl` 分页已实现（`SourceEngine` L1166-1238）；只有 `maxPages == 1` 且首页为空时直接失败，属边角。
3. 403 / Cloudflare / 412 的 `blocked` 文案已经是独立分类，P2 的「需要 WebView 登录或人工验证」提示尚未合并进诊断报告。
4. 真机 iOS 16 矩阵仍未执行；本版不宣称 iOS 16 体验通过。

## 五、复现

```bash
git show --stat b876d89
# 回归：无源级超时配置时，请求预算应为 20 秒
xcodebuild test -scheme SourceReadSwift -only-testing:SourceReadSwiftTests/BookSourceTests/testRequestBuilderDefaultsToThePipelineStageBudget
```
