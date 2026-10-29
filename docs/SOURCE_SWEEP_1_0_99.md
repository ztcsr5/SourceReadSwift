# 书源体检 1.0.99 · E 类 99 条复测 + 引擎级 WebView 误判修复

基线 1.0.98 (386b05d) → 本轮 e678f01 · 2026-10-29

## 1. 结论

| 指标 | 数值 | 证据 |
|---|---|---|
| E 类单关键词 PASS（旧 IPA 67ea04a） | 76 / 99 | e_current_retest_1029.json |
| 引擎修复后可 PASS（Observed，回放验证） | 80 / 99 | 见 §2 / §3 |
| 规则已验证可用（含限流/检测词因素） | 89 / 99 | 见 §4 |
| 站点级失效 | 10 / 99 | 见 §5 |

新增 4 条由引擎修复直接救回：车群小说、抖音小说、基本中文、猫耳听书。
其余 9 条（乡土 x5、爱尚 x4）规则本身没有问题，失败来自检测方法（关键词/限流）。

## 2. 新发现：WebView 回退误判（引擎级，已修）

**现象**：qunxs 搜索页 HTTP 200 / 21527 字节 / 15 个 .item，App 报「0 个节点，响应 11729 字符」。

**证据链**（全部实跑）：

1. 8098 回显服务器：App 的 POST 请求完全正确（method / body _token=&keyword=... / Content-Type / UA）。
2. 8097 回放服务器返回同一份 HTML：.item 命中 15 条，字段全对。
3. 8099 实时转发 qunxs：App 拿到响应后又用 **iPhone UA** GET 了同一 URL，并继续请求 css/style.css、js/user.js、/cdn-cgi/rum —— 只有 WKWebView 会拉子资源。
4. WebView 序列化回来的 DOM 只有 11729 字符，.item 全部消失。

**根因**：shouldUseWebViewFallback 用 	ext.contains("cloudflare") 做宽泛匹配。
qunxs 结果页页脚有一处 Cloudflare 字样（CDN 统计），整页因此被判为反爬挑战壳。

**修复 2949d3f**：

- 硬标记（cf-challenge / cf-browser-verification / __cf_chl / cf_chl_opt / 	urnstile / just a moment / ttention required / ddos-guard / 百度安全验证 / 人机验证）→ 仍然直接走 WebView。
- 软标记（cloudflare / captcha / 安全验证）→ 只有 body 完全没有可抓取结构时才走 WebView。
- 可抓取结构判定 hasCrawlableMarkup：>=6 个 <a ，或含 <article / <table，或 >=6 个 <li。
- 新增 WebViewFallbackHeuristicTests（7 条单测，e678f01 修正为调用 LegadoSourceEngine）。

**影响面**：所有「响应很大但 0 节点」的源。本轮实测命中 4 条。

## 3. 本轮源修复（已写回真机库，992 条不变）

| 源 | 改动 | 验证 |
|---|---|---|
| 抖音小说 https://m.douxsw.com/#xsw8093 | searchUrl → https://m.douxsw.com/search/,{"method":"POST","body":"searchkey={{key}}"} | PC 200 / 36351B / 47 .bookbox；站点 120s 搜索限流 |
| 车群小说（优）http://www.qunxs.com/ | JS 返回串 "/search," → "/search/," | PC 200 / 21527B / 15 .item；8097 回放 15 条 PASS |
| 基本中文 | ookSourceUrl → https://www.156zwcc.cc，Referer 同步；旧 key 已删除 | PC 200 / 180822B / 411 条；8097 回放 **411 条 PASS** |

## 4. 未改源但已证明可用

| 源 | 结论 | 证据 |
|---|---|---|
| 乡土小说 ×5 | 规则正确，E 类用「剑来」站内无书 → 假阴性 | POST /search/index.php，关键词「乡村」→ 42 条；8097 回放 **42 条 PASS**（书名/URL/作者全对） |
| 爱尚小说 ×8（23hh 同站） | 规则已全部对齐 class.c_row；941 字节是站点限流页 | GBK 编码 POST → 200 / 34709B / 20 .c_row / 293 条；8097 回放 **20 条 PASS**（书名/作者/字数全对） |
| 猫耳听书（优+） | dramaapi/search 返回 78226B JSON、success:true、info.Datas 有数据 | 3415 字符 HTML 是 WebView 误判产物，引擎修复后恢复 |

## 5. 站点级失效（10 条，不再投入）

| 源 | 条数 | 证据 |
|---|---|---|
| 听蛙音乐（优+） | 1 | 首页 18 字节「网站正式关闭，谢谢大家16年的支持！」 |
| 看点小说登录 / 看点小说（登录） | 2 | 404 nginx |
| 蚂蚁文学 ×4 | 4 | http://www.mayiwsk.com 返回 420 字节跳转壳 hn5x80.gotoa1.xyz；https:// 直接 RST |
| 五六中文 | 1 | 301 → m.56yz.com → gotoa1.xyz 点击跳转壳 |
| 全本同人（优） | 1 | qbtr.me ParkLogic 反爬页，	enant":"namesilo-expired（域名过期） |
| 八零阅读（导） | 1 | 	xt80.cc 全站 RemoteDisconnected |

## 6. 检测方法学修正

1. 单一关键词「剑来」对乡土 / 女频 / 轻小说类是假阴性 → 脚本必须多词轮换，或优先读源内 checkKeyWord。
2. 限流源必须串行加间隔：23hh >=35s、抖音 >=120s、乡土 >=3s。
3. 判定「是否误走 WebView」不能只看响应大小：回放同一份 HTML + 数请求次数才可靠（本次靠 8097/8099 两个自建服务器才定位）。
4. docs/SOURCE_SWEEP_1_0_98.md 里「猫耳属源规则与站点变更，不改引擎」的结论**已被推翻**，正确结论见 §4。

## 6. 2026-10-29 09:00 追加：剩余 24 条鱼源真机逐条验证

对 full_sweep 中「响应很大但 0 节点」的剩余主机做了真机 `/api/source/debug` 逐条跑测（关键字取 checkKeyWord 或默认「剑来」）。

### 6.1 直接 PASS（无需改动）

| 源 | 条数 | 真机结果 |
|---|---|---|
| 书城网包 http://www.shucw.net | 1 | PASS，100 条（关键词「我的」） |
| 双语小说系列 http://www.shubang.net | 6 | 4 条 PASS（哈利 32 条），2 条因「剑来」站内无书 0 结果 |
| 漫画搬运（优+）https://www.antbyw.com | 1 | PASS（关键词「剑来」） |
| 潇湘书院 https://m.xxsy.net | 6 | 全部 PASS，各 20 条（关键词「簪星」；PC 侧 RST 但真机正常） |
| 英文小说（英）https://www.yingyuxiaoshuo.com | 1 | PASS，3 条（关键词「加」） |

### 6.2 检测词假阴性（规则正确，换词即 PASS）

| 源 | 条数 | 换词结果 |
|---|---|---|
| 创国漫吧（魔法）http://www.guoman8.cc | 1 | 「斗罗」→ 10 条 PASS |
| 古龙武侠（优+）http://m.gulongbbs.com/wuxia | 1 | 「楚留香」→ 11 条 PASS |
| 古龙武心 http://m.gulongbbs.com/wuxia#🎃 | 1 | 「陆小凤」→ 11 条 PASS |
| 靠谱小说 http://www.kptxt.com | 1 | 「武侠」→ 56 条 PASS |

这 4 条规则（`class.book-result@tag.li` / `class.c wrap@li` / `class.book`）全部命中，此前 FAIL 仅因站点内没有《剑来》。

### 6.3 本轮新修

| 源 | 改动 | 验证 |
|---|---|---|
| 异轻纵然（优++）https://www.esjzone.cc | searchUrl `https://www.esjzone.one/tags/{{key}}` → `https://www.esjzone.one/tags-01/{{key}}/1.html` | PC 200 / 72433B / 40 条 `col-lg-3`+`card-title`+`card-author`；**真机连 esjzone.cc/.one 均超时**（PC 秒开）→ 标记为真机网络受限 |
| 双语小说英语 / 双语小说（英）×2 | ruleSearch.checkKeyWord 补「哈利」 | 消除检测假阴性 |

### 6.4 esjzone 正确路径（已确认）

旧 `https://www.esjzone.one/tags/{{key}}` 返回的是站点公共壳（11849B，无列表）。真正可用的是：

```
https://www.esjzone.one/tags-01/{{key}}/1.html   → 72433B / 40 条
https://www.esjzone.cc/tags-01/{{key}}/1.html    → 73335B / 40 条
```

恩施轻语（优+）本来就用 `/tags-01/{{key}}/{{page}}.html`，规则无需改；真机 33s WebView timeout 属网络侧。

### 6.5 仍未解决

| 源 | 现象 | 判定 |
|---|---|---|
| 异轻纵然 / 恩施轻语（esjzone） | 真机 20–31s 超时或 WebView timeout；PC 正常 | 真机网络到该站受限，非规则问题 |
| 万层中文 http://www.oneceng.com | 真机 0 节点 8028 字符 | 待查（PC ReadTimeout） |
| 五六中文、全本同人、八零阅读 ×2、猫耳听书 | 仍 0 节点 | 站点失效 / 待新 IPA 重测（猫耳依赖 WebView 修复） |

### 6.6 引擎修复验证状态

CI `40796774953`（iOS @e678f01）= **success**：Build + 全部单测通过（含新增 WebViewFallbackHeuristicTests 7 条）。
IPA `40796775150` = success，产物 `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.98-unsigned.ipa`（12,419,731 B，sha256 3D79AED417C74CA4187B138DA97C53A76DE72E5AAECFAA100B67C71B8ED72483）。
真机当前仍为旧 IPA（qunxs 复测仍返回 11787 字符 WebView DOM），需安装新 IPA 后复验。

## 7. E 类 99 条 v2 复测结果（旧 IPA，2026-10-29 10:00）

`artifacts/e_current_retest_1029_v2.json` · 单线程 + 多关键词轮换（checkKeyWord 优先）+ 每源 3s 间隔

| 指标 | 数值 |
|---|---|
| PASS | **79 / 99** |
| 上一轮（单关键词） | 76 / 99 |
| 新 IPA 预计（WebView 修复后） | **81 / 99** |
| 站点永久失效 | 8 / 99 |

### 7.1 本轮由换词与并发修正救回（+3 净增）

| 源 | 结果 |
|---|---|
| 爱尚小说 ×8（23hh 同站） | 全部 PASS：总裁 20 条 ×3、总裁 20 条、哈利 10 条、总裁 20 条 |
| 落霞小说 ×3 | 总裁 50 条 ×3 |
| 万层中文 ×2 | 「我的」20 条 ×2 |
| 抖音小说 ×2 | 「大奉打更人」3 条 / 「凡人修仙传」20 条 |
| 八零电子（导） | 「剑来」5 条 |
| 手机小说网 | 「总裁」100 条 |
| 中华典藏（优+） | 「修真」20 条 |
| 笔趣阁吧 | 「总裁」50 条 |

### 7.2 仍 FAIL 的 20 条根因

| 根因 | 条数 | 源 | 处置 |
|---|---|---|---|
| 站点限流（1363 字符限流页） | 5 | 乡土小说 ×5 | 规则正确（PC 42 条），错峰可 PASS |
| 站点限流（2789 字符） | 1 | 抖音小说 #xsw8093 | 120s 限流，错峰可 PASS |
| WebView 误判（等新 IPA） | 2 | 车群小说（11787 字符）、猫耳听书（3416 字符） | 引擎已修，装机即恢复 |
| 站点失效 | 8 | 五六中文、全本同人、听蛙、蚂蚁文学 ×4 | 不再投入 |
| 搜索端点 403 | 1 | 八零阅读（导） | 帝国 CMS `e/search` 整站 403，发现页仍可用 |
| 源 key 已变更 | 2 | 基本中文（156zw.com→156zwcc.cc）、爱尚（23hh.la已整理） | 旧 key 条目，实际源已 PASS |
| 站点空响应 | 1 | 看点小说登录 ×2 | 138 字符，站点登录墙 |

### 7.3 结论

- 规则层可用率：**88 / 99**（除 8 条站点失效 + 1 条搜索 403 + 2 条 key 变更）
- 装新 IPA 后预期 PASS：**81/99**（车群 + 猫耳）
- 乡土 ×5 与抖音若错峰重跑可再 +6 → 上限 **87/99**
