# 76 源基线对账（10 → 8）与失败分类

- 日期：2026-10-29
- 旧基线：`E:\codex-temp\sourceread\reports\lan-check-20261028-192236.json`（1.0.90，关键词「斗破苍穹」，单线程，timeout 180s）
- 新基线：`E:\codex-temp\sourceread\artifacts\sweep76_share11_1029b.json`（1.0.98/99，5 关键词轮换，并发 3，timeout 150s，网络错误不重试）
- 输入：`D:\QQ游戏\shareBookSource11.json`（76 条）

## 1. 10 → 8 不是引擎退化

两次 PASS4 的逐条对账：

| 集合 | 数量 | 书源 |
|---|---:|---|
| 两次都 PASS | 6 | 免费追书、番茄小说TS、反代番茄、小原文学网、⚡📂小原文学网、⭐七猫听书 |
| 仅旧报告 PASS | 4 | 52书库、Icu、八叉书库(二合一)、番茄🍅（沐凡·PyFQ-Go本地） |
| 仅新报告 PASS | 2 | 无错、有听网 |
| 历史并集 | 12 | 6 + 4 + 2 |

净变化 = 增 2 - 掉 4 = **8**。

### 1.1 掉下去的 4 条

| 书源 | 旧结果 | 新结果 | PC 直连复核（2026-10-29） | 判定 |
|---|---|---|---|---|
| 52书库 | 7/30/7026 | 搜索连接超时 20.6s | 搜索 URL 200 / 9069B / 0.6s | 手机侧瞬时超时，重试应恢复 |
| Icu | 38/5/1748 | `network connection was lost` 518ms | `hq555.icu:1678` TLS reset | 域名/线路已断 |
| 八叉书库(二合一) | 20/30/40 | `network connection was lost` 2.4s | 实际小说站 `8xsk.top` TLS reset；备用 `tpmh8.cc` 200 | 默认主机失效，需切备用域 |
| 番茄🍅（沐凡） | 10/30/243041 | 0 节点，7005 字符，84.7s | `fqaggregate.de5.net` TLS reset | 外部聚合接口已断 |

### 1.2 新上来的 2 条

| 书源 | 旧结果 | 新结果 |
|---|---|---|
| 无错 | 0 节点，7138 字符 | 60/30/2092 |
| 有听网 | HTTP 404 | 3/30/208 |

### 1.3 口径差异

1. 旧报告单关键词「斗破苍穹」，新报告 5 词轮换；旧报告默认并发 1，新报告并发 3。
2. 新脚本遇到 `network connection was lost` / 超时直接判 FAIL，不重试；旧脚本 timeout 180s。
3. PASS4 只要求「搜索≥1 + 详情 + 目录≥1 + 正文>0」，不要求正文可读长度：
   - 旧 10 条里八叉仅 40 字、七猫听书 115 字；
   - 新 8 条里七猫听书 115 字、有听网 208 字。
   - 按正文 ≥500 字统计：旧 8 条、新 6 条。

结论：10 是单次宽松口径的结果，8 是更严格口径的结果；两次并集 12，稳定通过 6。**不能把 8 当成引擎退回到 1.0.90 之前。**

## 2. 空壳 20 条：是同一批，但测试输入需要统一

- 与旧报告逐条比对：20 条的名称 + `bookSourceUrl` 完全一致，20/20，无新增无减少。
- 原始 `shareBookSource11.json` 中这 20 条只有 7 个字段：`bookSourceName / bookSourceUrl / bookSourceType / enabled / enabledExplore / customOrder / weight`，没有 `searchUrl / exploreUrl / rule*`。
- `docs/sources/shareBookSource11-rebuilt-1.0.94.json` 已经是 **18 条空壳**：天域小说、爱奇电子书已补规则；但当前 sweep 测的是原始文件，所以仍显示 20。
- 因此：**如果真机导入的是 rebuilt 文件，App 里应是 18 条空壳；如果导入的是原始文件，才是 20 条。测试和真机库必须统一。**

### 2.1 空壳站点状态（上一轮探站记录）

- 可打开 15：得奇、书音FM、bqg128、小说狂人、爱奇、言情、365、阅友、东滩、茶马、天域、夜读阁、米读 API、八叉、宝华。
- 异常/不可达 5：漫蛙（跳转/404）、肉书屋（乱码/超时）、台湾小说（403）、御书屋（SSL EOF）等。
- 15 条也不是都能低成本补：bqg128 需要先种 Cookie 再搜索，正文还要 `getsite` Cookie + `webView`；得奇、书音FM、米读是 API 型；八叉有动态 Cookie。

## 3. 其他不可行：32 条 FAIL 的根因

| 根因 | 数量 | 书源 | 性质 |
|---|---:|---|---|
| 网络断开 | 5 | 速读谷×2、错层、Icu、八叉 | 站点/线路；重试或标记失效 |
| 连接超时 | 3 | 52书库、集书阁、得奇 | 站点/线路；重试或标记失效 |
| HTTP 500 | 1 | 速读谷 | 站点宕机 |
| HTTP 404 | 1 | 含遇見 | 接口下线/域名变更 |
| URL 非法 -1000 | 1 | biquge2345 | 域名/解析异常 |
| JSON/列表 0 项 | 14 | 玖玖、次元姬、蕃茄、zenneko、书山、NovelHub、聚合书源、本地番茄红果、番茄沐凡、QQ浏览器、塔读、话本、千白羽、书音FM | 站点接口/规则变更；部分为关键词假阴性 |
| JS/响应解析异常 | 3 | 七猫四合一、聚合书库、紙間 | 返回非 JSON / 解析链不匹配 |
| 列表命中但字段空 | 2 | 书旗×2 | `GetUrl()`/Cookie token 分支 |
| 相对 URL | 1 | 爱丽丝书屋 | `bookSourceUrl` 非绝对 URL；1.0.103 已定向修 |
| `_.java` 未定义 | 1 | UAA 四合一 | 1.0.103 已定向修 |

### 3.1 另外 16 条非 PASS

| 状态 | 数量 | 书源 | 主要问题 |
|---|---:|---|---|
| FAIL_TOC | 7 | 圣灵、含遇见(加发现页)、木里、日落、百度、连尚、爱下 | JSON 嵌套/JS 文本/变量上下文；1.0.103 覆盖木里、日落、百度、连尚 |
| FAIL_DETAIL | 4 | 七猫×2、番茄 APP、STV | 详情规则/签名/对象字符串化；1.0.103 覆盖七猫、STV |
| FAIL_CONTENT | 1 | 爱书音 | 搜索/详情/目录已通，正文 0 字 |
| DRIVER_ERROR | 1 | 顶点 | 站点超时 |
| LOGIN | 3 | 少年梦、魔丸、番茄四合一 | HTTP 401；需要书源登录面板/Cookie，不是解析器问题 |

## 4. 1.0.103 已定向覆盖的源

| 源 | 旧失败 | 1.0.103 修复 |
|---|---|---|
| 七猫小说 / 七猫官方 | FAIL_DETAIL | String 助手改为不可枚举，避免污染签名参数 |
| 爱丽丝书屋 | 相对 URL | `networkBaseURL` 从 jsLib/规则恢复 origin |
| 木里番茄 / 日落 | FAIL_TOC | 识别 `var raw = String(result); JSON.parse(raw)` 间接 JSON 文本 |
| UAA 四合一 | `_.java` | 参数遮蔽时仍把 `_.java` 绑定到桥 |
| 百度小说 | FAIL_TOC | `java.getElements('$..items.*')` 返回 JSON 节点 |
| 连尚读书 | FAIL_TOC | `<js>…</js>$[*]` 链式规则先解析 JS 文本为 JSON |
| 36 条 `@js:` exploreUrl | 发现页空白 | 新增 JS 分类求值 + `step=explore` |

合计 8 条定向源。装 1.0.103 后先跑 `verify_named.py`，再跑 `sweep76_v4.py`；预期从 8 提到 14–16，但必须以真机结果为准（未跑 = NOT RUN）。

## 5. 复测脚本改进

新增 `E:\codex-temp\sourceread\scripts\sweep76_v4.py`：

- 对局域网地址强制绕过 `HTTP_PROXY`；
- 对 `network connection was lost` / timeout / 5xx 自动重试 2 次；
- 优先使用 `ruleSearch.checkKeyWord`，再轮换 5 个关键词；
- 区分 `TRANSIENT` 与 `FAIL`，并单独统计「正文 <500 字」的低质量 PASS；
- 输出 JSON + Markdown 对账表。

当前 LAN `192.168.31.205:8080`：TCP 可连，但 HTTP 请求 10–20s 返回 0 字节，App 侧疑似挂起/后台冻结；待服务恢复后执行：

```powershell
$env:PYTHONIOENCODING='utf-8'
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\verify_named.py'
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\sweep76_v4.py' --concurrency 1 --timeout 180 --retries 2
```
