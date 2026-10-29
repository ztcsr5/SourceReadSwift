# 交接 1.0.99 · 书源引擎 WebView 误判修复

分支 codex/reader-feedback-fixes · 已推送 codex/swift-v2-lifetime-reader
提交：2949d3f（引擎 + 单测）、e678f01（单测类型修正）
详表：docs/SOURCE_SWEEP_1_0_99.md

## 一句话

找到并修掉了「HTTP 拿到完整结果页却报 0 节点」的引擎级根因：页面里出现一次
Cloudflare 品牌字样就把整页判成反爬挑战，强制走 WKWebView，而 WebView 的简化
DOM 丢掉全部规则目标。

## 代码改动

| 文件 | 改动 |
|---|---|
| SourceReadSwift/Core/Engine/SourceEngine.swift | shouldUseWebViewFallback 拆成硬/软标记；新增 hasCrawlableMarkup |
| SourceReadSwiftTests/WebViewFallbackHeuristicTests.swift（新） | 7 条单测 |

硬标记（仍直接 WebView）：cf-challenge / cf-browser-verification / __cf_chl /
cf_chl_opt / turnstile / just a moment / attention required / ddos-guard /
百度安全验证 / 人机验证

软标记（cloudflare / captcha / 安全验证）：仅当 body 没有可抓取结构时走 WebView
可抓取结构：>=6 个 <a，或含 article/table，或 >=6 个 <li>

## 本轮定位手段（可复用）

1. 8098 回显服务器：验证 App 发出的 method/path/headers/body。
2. 8097 回放服务器：把同一份 HTML 原样返回，验证解析器（15 条全中）。
3. 8099 实时转发：观察 App 是否在 HTTP 之后又发起 iPhone UA 请求（= 走了 WebView）。
4. 数 fwd_log 行数：单次请求 = 纯 HTTP；多次（含 css/js）= WebView。

脚本：E:\\codex-temp\\sourceread\\scripts\\{echo_server,replay_server,fwd_server}.py

## 真机库状态

992 条（enabledCount 991）。本轮写回 3 条：
- 抖音小说 searchUrl → POST /search/
- 车群小说 JS "/search," → "/search/,"
- 基本中文 bookSourceUrl → https://www.156zwcc.cc（旧 key 已删）

## E 类 99 条

- 旧 IPA 实测 76 PASS
- 引擎修复后（回放验证）80 PASS
- 89 条规则可用；10 条站点级失效（听蛙/看点 x2/蚂蚁 x4/五六/全本同人/八零）

## 待办

1. 新 IPA 装真机后复测 4 条（车群/抖音/基本中文/猫耳）确认 80/99。
2. 全量 992 条扫描时按限流表加间隔（23hh 35s、抖音 120s、乡土 3s）。
3. 检测脚本改为多关键词轮换 + 读 checkKeyWord。
