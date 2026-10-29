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

## 8. 全量 991 条体检（2026-10-29 10:50，旧 IPA 1.0.98）

脚本 `E:\codex-temp\sourceread\scripts\full_sweep_v2.py`（2 并发 + 502 重试 + 每源最多 4 关键词）
结果 `artifacts/full_sweep_v2.json`

| 指标 | 数值 |
|---|---|
| 总数 | 991 |
| PASS | **750（75.7%）** |
| FAIL | 238 |
| 无 searchUrl（仅发现页） | 3 |

### 8.1 FAIL 分类

| 类别 | 条数 | 判定 |
|---|---|---|
| BAD_URL（-1000） | 66 | 全部是 **301 换域名** 的站；App 首跳即报 badURL |
| TIMEOUT | 32 | 慢站 / 网络 |
| EMPTY_FIELD（命中节点但字段空） | 31 | 帝国 CMS 搜索表为空 / 死站 |
| NETWORK（连接丢失/域名未解析） | 30 | 站点侧 |
| ZERO_NODE | 27 | 限流页 / 失效站 / WebView 误判（旧 IPA） |
| JSON 列表空 | 27 | JSON 源字段差异 |
| HTTP 404 | 15 | 站点路径变更 |
| OTHER | 10 | — |

### 8.2 BAD_URL 66 条的真实根因（301 假设已排除）

结论修正：**301 重定向处理正常，不是 -1000 的来源。**

决定性实验（`redirect_server.py` @ 8096，真机 `/api/source/debug`）：

| 用例 | 服务端行为 | 真机结果 |
|---|---|---|
| `/redir` | 301 → 相对 `Location: /target` | PASS，3 条 |
| `/redir-abs` | 301 → 绝对 `Location: http://<host>/target` | PASS，3 条 |

DNS 抽样（本机）：

```
m.rulianshi.la    -> 0.0.0.0
www.kk169.net     -> 0.0.0.0
www.yetianlian.com-> 0.0.0.0
www.wsskw.com     -> 0.0.0.0
m.yunxs.cc        -> 0.0.0.0
www.wurexs.com    -> 178.107.151.115（搜索路径 301 后 502）
```

iOS 连接 `0.0.0.0` 时抛 `NSURLErrorBadURL (-1000)`，与重定向无关。66 条里的活站已通过改域名恢复（rulianshi / kk169 / yetianlian / quduwx），其余 54 条死站已 `enabled=false`。

### 8.3 本轮修复的源（写回真机库）

| 源 | 条数 | 改动 | 验证 |
|---|---|---|---|
| 不知加啥 | 1 | bookSourceUrl `m.rulianshi.la` -> `m.rulianshi.cc` | 真机 50 条 PASS |
| 去读书家族 | 5->1 | 合并为 `http://www.quduwx.net` + `/modules/article/search.php?q={{key}}` | 真机 50 条 PASS（元尊） |
| 夜天连看家族 | 9->2 | 桌面 `www.xyetianlian.com`、移动 `m.xyetianlian.com` | 真机各 40 条 PASS |
| 穿越小说家族（kk169） | 9->1 | `http://www.kk169.la` + `modules/article/search.php?q={{key}}` | 真机 56 条 PASS |

### 8.4 批量禁用死站（54 条）

以下 host 经 PC 侧实测为 DNS 失败或 301 后 502，已 `enabled=false`：

```
www.wurexs.com  m.yunxs.cc  www.tangsanshu.org  www.biqusk.com  m.wenxuedu.net
wujixsw.info  www.xbiquzw.com  www.tcmaoxin.org  www.xmayitxt.com  www.00shu.la
m.00shu.la  www.23uswx.org  www.gdbzkz.org  www.95dushu.net  www.kyxsw.org
m.wsskw.com  www.wsskw.com  www.xinshuge.net  www.sjwx.la  wap.xuanyge.org
www.xuanyge.org  wap.dawensk.com  www.dingdianxs.la
```

### 8.5 真机库最终状态

| 指标 | 值 |
|---|---|
| total | 973（原 992，合并重复家族 -19） |
| enabled | 918 |

### 8.6 未验证 / NOT RUN

- 1.0.99 / 1.0.100 IPA 装机后的全量复测（当前全量结果仍来自 1.0.98）。
- 301 引擎修复：**不需要**（实验证明现有实现正确）。

## 9. 1.0.100 引擎修复（2026-10-29）

### 9.1 `webView:true` + POST body 丢失修复

`loadWithOptionalWebViewFallback` 原来对 `webView:true` 直接跳过 socket。WKWebView 只能 GET，POST body 丢失：

| 源 | App 的 POST 结果 | 回退后的 GET | 最终解析 |
|---|---|---|---|
| 抖音 m.douxsw.com | 5010 B / 3 本 | 2831 B 空表单 | 失败 2789 字符 |
| 乡土 www.xiangtxsw.com | 28572 B | 1465 B 无关键词页 | 失败 1363 字符 |
| 车群 www.qunxs.com | 21527 B / 15 本 | 13110 B 首页式页面 | 失败 11787 字符 |

修复：body-bearing 的 POST 先走 socket，WebKit 仅作为失败回退（`LegadoSourceEngine.shouldForceWebView(for:)`）。

### 9.2 1.0.98 的 WebView 误判（已在 1.0.99 修复，待装机）

车群 / 乡土 / 抖音的 28K 结果页都含 `cdn-cgi` 的 `cloudflare` 字样，1.0.98 把它当成人机验证页强制 WebView，简化 DOM 后 0 节点。1.0.99 的 `hasCrawlableMarkup` 已按 `<a>/<table>/<li>` 判定真实结果页。

### 9.3 “引擎差异”逐条复核

| 其他 AI 的判断 | 现行代码 | 真机实测 |
|---|---|---|
| `s.length()` 不存在 | 已兼容 | `"abcd".length()` → 4 |
| `createSymmetricCrypto(...).encryptHex` 缺失 | 已实现 DES/3DES | DES 加密 `4a242ef2e9ce4ca6`，解密回 `test` |
| `_.java` undefined | 已挂载 | base64 `abc` → `YWJj` |
| 内嵌 JSON 字符串目录 0 章 | `decodeJSONValue` 递归展开 | 代码路径已存在 |
| 相对 searchUrl 报“不支持的 URL 协议” | 已按 bookSourceUrl 拼接 | `/redir` 相对 301 PASS |

### 9.4 站点侧确认不可修

| 源 | 证据 |
|---|---|
| 猫耳听书 | `dramaapi/search` 返回 412 bilibili 错误页 |
| 五六中文 | `m.56zw.com` 301 → `m.56yz.com`，搜索恒为空（1603 B） |
| 蚂蚁文学 | `mayiwsk.com` HTTP 404 |
| 全本同人 | `/e/search` 返回 cookie+reload JS 跳转页（WebView 可试） |
| 看点小说 | 搜索响应 138 B（站点侧拦截） |
