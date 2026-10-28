# SourceReadSwift 1.0.97 (Build 98) 交接

- 日期：2026-10-29
- 版本：MARKETING_VERSION 1.0.97 / CURRENT_PROJECT_VERSION 98
- 本地分支：`codex/reader-feedback-fixes`
- 推送分支：`codex/swift-v2-lifetime-reader`

## 1. 本轮提交

| SHA | 内容 |
|---|---|
| `b34bbc3` | 版本号 bump 到 1.0.97 (98) |
| `464d71d` | 修复规则脚本归一化编译错误（`normalizeRuleScript` 返回 String 却被当作对象取 `.normalizedScript`） |
| `d462e0d` | 源库：重建茶马小说全链路；重建 bqg128 搜索（JSON）+ 目录 + webView 正文 |

## 2. 引擎层四个可修点（代码现状）

| 点 | 位置 | 状态 |
|---|---|---|
| Java `String.length()` 改属性 | `LegadoJavaScriptCompatibility.rewriteJavaStringLengthCalls` | 已实现，规则脚本走 `normalizeRule`，`file.length()` 保留 |
| `java.createSymmetricCrypto(...).encryptHex` | `JSCoreRuntime.java.createSymmetricCrypto`（encryptHex/decryptHex）+ `LegadoHostServices.cipher` | 已实现，DES/3DES 走 `kCCAlgorithmDES/kCCAlgorithm3DES` |
| `_.java` 全局别名 | `JSCoreRuntime.swift:1527-1531` | 已实现 |
| 相对 URL 兜底 | `SearchURLResolver` / `DynamicURLResolver.absolutize` | 已实现 |

本轮新增：`LegadoJavaScriptCompatibility.normalizeRule(_:)` 返回完整 `LegadoJavaScriptNormalization`，诊断证据保留原始脚本与 feature 列表；`JSCoreRuntime` 改用它，修掉 `value of type 'String' has no member 'normalizedScript'`。

## 3. 源库（docs/sources/shareBookSource11-fixed-1.0.95.json）

76 条，启用 70 条。本轮修复 2 条空壳：

### 茶马小说 `https://www.chamabooks.net`
- 搜索：`/search?s={{key}}&p={{page}}`（实测 `斗破苍穹` 1 条、`系统` p1/p2 各 20 条）
- 列表：`#main-list .novel-item`；书名 `h4.novel-subject a`；作者 `.misc-value a`；分类 `.category`；字数 `.word-count`；简介 `p.novel-desc`
- 详情：`h1`（书名+作者）、`.info .small`、`.novel-summary-content`
- 目录：`select.pg-sel option`，实测 1645 章（value=章节 URL，text=章节名）
- 正文：`#novel-content`，实测 3017 字

### bqg128 `https://www.bqg128.cc`
- 搜索：`/user/search.html?q={{key}}` 返回 JSON 数组，字段 `url_list / url_img / articlename / author / intro`（实测 `总裁` 100 条；版权词如 `斗破苍穹` 返回 `1`，属站点过滤）
- 详情：`h1`、`.info .small span:eq(0)`（作者）、`.info .cover img`、`.intro dd`
- 目录：`.listmain a`，实测 179 章
- 正文：`#content`，章节页有 `getsite` cookie 校验，`chapterUrl` 追加 `,{"webView":true}`

### 仍为空壳/上游不可达（15 条中剩余）
- 言情小说网 `m.bgnovel.com`：搜索可用（POST `/e/search/index.php`，`keyboard` 参数；`总裁` 18KB 有结果），但站点是 103 页分页阅读、无目录页，需专门降级方案
- 肉书屋 `m.roushuwu7.com`：首页读取超时 20s+，搜索 POST `/s.php` 参数名未确认，暂缓
- 365小说 `shukuge.com`：搜索仅前端 JS，首页 8KB
- 阅友 `m.suixkan.com`：SPA，搜索接口未定位
- 米读 `api.midukanshu.com`：纯 API + 签名
- 宝华书院：JS 挑战
- 台湾小说 / 御书屋：TLS/CF 上游不可达
- 漫蛙：漫画站，非小说

## 4. 登录系统（已有，本轮核对）

- 入口：设置 → 书源登录中心；书源管理右上角钥匙按钮；源卡片「网站 / 登录」菜单。
- 页面：已登录/未登录分组、搜索、左滑退出、Cookie 计数。
- 两种登录方式：
  1. `loginUi` 非空：原生表单 → `engine.login(source:credentials:)`，凭据写入 `persistentState`，供 `source.getLoginInfoMap()` 读取。
  2. `loginUi` 为空：内置 WKWebView 打开 `loginUrl` 或回退 `bookSourceUrl` 首页；`didFinish` 与「完成」按钮都会把 `WKWebsiteDataStore.default()` 全部 cookie 写入 `SourceCookieStore`。
- Cookie 注入：`SourceRequest` 的 `storeSetCookieHeaders` 在请求时按 host（含父域）+ path 匹配附加 Cookie；`SourceCookieStore` 已做 RFC6265 父域匹配。
- 待真机验证：登录后搜索/目录/正文是否带 Cookie（LAN 恢复后跑全量复测即可覆盖）。

## 5. 局域网测试服务

- App 内「Web 写源与传输」页 `onAppear` 才启动 HTTP 服务，端口 8080。
- 当前状态：`http://192.168.31.205:8080` **无监听**；全网段扫描仅路由器 `192.168.31.1:8080` 开放；本机 IP 为 `192.168.31.222`。
- 恢复步骤：iPhone 打开 App → 进入「Web 写源与传输」→ 保持前台 → 电脑 `Invoke-WebRequest http://192.168.31.205:8080/api/status` 应返回 200。
- 导入源库：`python tools/lan_import.py docs/sources/shareBookSource11-fixed-1.0.95.json`（分批 ≤1.7MB）。
- 全量复测：`lan_source_check.py --base http://192.168.31.205:8080 --keyword 斗破苍穹 --concurrency 3 --timeout 150`。

## 6. CI

| run | commit | 工作流 | 结果 |
|---|---|---|---|
| 40740559522 / 40740561593 | 464d71d | iOS / Unsigned IPA | 本轮触发，pending/in_progress |
| 40741799679 / 40741799730 | d462e0d | iOS / Unsigned IPA | pending |

## 7. 下一步

1. CI 绿后 `fetch_ipa.py` 出 1.0.97 包。
2. 用户恢复 LAN 服务 → 导入源库 → 全量复测 76 条。
3. 言情小说网降级方案（103 页分页 → 章节映射）。
4. 登录链路真机验证（登录 → 搜索 → 目录 → 正文 cookie）。
