# 76 条书源逐条总表（1.0.103）

- 数据：`E:\codex-temp\sourceread\artifacts\sweep76_share11_1029b.json`（1.0.98/99 真机）
- 输入：`D:\QQ游戏\shareBookSource11.json`（76 条，原始顺序编号 01–76）
- 判定：PASS4 = 搜索≥1 + 详情 + 目录≥1 + 正文>0；**这是结构通过，不是正文质量通过**
- 状态：PASS4 8 / 空壳 20 / 有规则但失败 48（搜索 32 + 目录 7 + 详情 4 + 正文 1 + 驱动 1 + 登录 3）

## 0. 总览

| 状态 | 数量 | 说明 |
|---|---:|---|
| PASS4 | 8 | 搜索/详情/目录/正文全通 |
| NO_SEARCH_URL | 20 | 只有名称+URL，无任何规则 |
| FAIL | 32 | 搜索阶段失败 |
| FAIL_TOC | 7 | 详情成功，目录 0 章 |
| FAIL_DETAIL | 4 | 搜索成功，详情失败 |
| FAIL_CONTENT | 1 | 搜索/详情/目录通，正文 0 字 |
| DRIVER_ERROR | 1 | 请求驱动超时 |
| LOGIN | 3 | HTTP 401，需要登录 |

旧 10 → 新 8：两次都 PASS 6 条；仅旧 PASS 4 条（52书库、Icu、八叉二合一、番茄沐凡）；仅新 PASS 2 条（无错、有听网）。原因见 `SOURCE_BASELINE_1_0_103.md`。

## 1. PASS4（8 条）

| # | 书源 | URL | 搜索 | 目录 | 字数 | 关键词 | 备注 |
|---|---|---|---:|---:|---:|---|---|
| 01 | 番茄小说TS | https://fq.tangsongxs.com | 9 | 30 | 1112 | 斗破苍穹 | 正文≥500 字 |
| 06 | 免费追书 | http://cread.com | 20 | 30 | 2467 | 斗破苍穹 | 正文≥500 字 |
| 10 | 反代番茄 | https://fqapi.tongle.dev | 17 | 30 | 1024 | 斗破苍穹 | 正文≥500 字 |
| 29 | 小原文学网 | https://www.min-yuan.com/ | 20 | 30 | 1267 | 斗破苍穹 | 正文≥500 字 |
| 31 | ⭐七猫听书[官方]v0.2✨ | https://api-bc.wtzw.com#七猫听书 | 10 | 1 | 115 | 斗破苍穹 | 低正文（<500 字） |
| 32 | 无错 | https://www.wcshuba.com | 60 | 30 | 2092 | 斗破苍穹 | 正文≥500 字 |
| 55 | 有听网 | https://m.ting15.com/ | 3 | 30 | 208 | 斗破苍穹 | 低正文（<500 字） |
| 76 | ⚡📂小原文学网 | https://www.min-yuan.com | 20 | 30 | 1267 | 斗破苍穹 | 正文≥500 字 |

## 2. 空壳（20 条）

| # | 书源 | URL | 站点判断/建议 |
|---|---|---|---|
| 34 | 得奇小说网 | https://www.deqixs.co | 站点可开；另有带规则的同名源 #35；可补规则 |
| 47 | 🎧书音FM | https://m.shuyinfm.com/ | 站点可开；与 #46 书音FM 同一 API；可补 |
| 48 | bqg128 | https://www.bqg128.cc/ | 站点可开；搜索需 Cookie，正文需 webView |
| 52 | 小说狂人 | https://czbooks.net | 站点可开；普通 HTML，优先补 |
| 53 | 爱奇电子书 | http://www.xqb8.org/ | rebuilt 文件已补规则；优先导入 |
| 54 | 七猫 | https://api-bc.wtzw.com | API 可开；已有多个七猫源，可复用规则 |
| 56 | 🎃 言情小说网 | https://m.bgnovel.com#🎃 | 站点可开；普通 HTML，优先补 |
| 58 | 🎨 漫蛙 | http://manwaso.cc | 站点异常（404/跳转）；暂缓 |
| 59 | 365小说 | http://www.shukuge.com | 站点可开；普通 HTML，优先补 |
| 60 | 肉书屋 | https://m.roushuwu7.com | 站点可开但 GBK/乱码；需编码处理 |
| 61 | 阅友小说 | https://m.suixkan.com/ | 站点可开；普通 HTML，优先补 |
| 62 | 东滩小说 | http://www.dongtanxs.com/ | 站点可开；普通 HTML，优先补 |
| 63 | 台湾小说 | https://twkan.com/ | 403；暂缓/标记失效 |
| 64 | 🥕茶马小说 | https://www.chamabooks.net | 站点可开；有搜索表单，优先补 |
| 65 | 天域小说 | http://www.tianyu8.org | rebuilt 文件已补规则；优先导入 |
| 66 | 夜读阁 | https://www.yeduge.com | 站点可开；普通 HTML，优先补 |
| 67 | 🌱米读小说 | http://api.midukanshu.com | API 可开但仅 2 字节；需逆向接口 |
| 68 | 御书屋 | https://m.seyuwen.com/ | SSL EOF；标记失效 |
| 69 | 八叉书库 | https://bcshuku.com | 站点可开；动态 Cookie；另有带规则的同名源 #72 |
| 70 | 宝华书院 | https://www.baohuasy.com | 站点可开但 GBK；需编码处理 |

## 3. 登录墙（3 条）

| # | 书源 | URL | 搜索/目录/字数 | 问题 | 下一步 |
|---|---|---|---|---|---|
| 02 | ✿少年梦（知秋）✿ | 少年梦＃知秋 | 0/0/0 | HTTP 401 | 做登录面板/Cookie 持久化，登录后重试 |
| 11 | 魔丸小说 | https://www.mowan.lol | 0/0/0 | HTTP 401 | 做登录面板/Cookie 持久化，登录后重试 |
| 21 | ✿番茄四合一（知秋段评）✿ | 番茄四合一#知秋 lyc版阅读 | 0/0/0 | HTTP 401 | 做登录面板/Cookie 持久化，登录后重试 |

## 4. 详情失败（4 条）

| # | 书源 | URL | 搜索 | 问题 | 下一步 |
|---|---|---|---:|---|---|
| 03 | 七猫小说 | https://api-bc.wtzw.com#七猫官方API·来源自网络 | 11 | 详情未解析 | 1.0.103 String 枚举/签名修复；待真机验 |
| 18 | ⭐七猫小说[官方本地接口]API✨ | https://api-bc.wtzw.com#七猫官方API | 11 | 详情未解析 | 1.0.103 String 枚举/签名修复；待真机验 |
| 19 | STV - Sáng Tác Việt | STV聚合 | 19 | 详情未解析 | source 对象字符串化；1.0.92/1.0.103 待验 |
| 20 | 🍅番茄小说(APP) | https://fanqienovel.com | 1 | 详情未解析 | 详情规则/JSON 结构；需抓响应 |

## 5. 目录 0 章（7 条）

| # | 书源 | URL | 搜索 | 问题 | 下一步 |
|---|---|---|---:|---|---|
| 14 | 含遇見(加发现页) | http://210.16.175.40:11451 | 24 | 目录 0 章 | tocUrl/JSON 结构不匹配；需真机日志 |
| 16 | 📚 圣灵聚合 | http://apiba.top | 6 | 目录 0 章 | toc 规则读 `src` 变量；需上下文/真机日志 |
| 22 | 🍅木里番茄0922[GO聚合版] | http://154.58.233.54:1968 | 10 | 目录 0 章 | 1.0.103 间接 JSON.parse；待真机验 |
| 24 | 日落小说 | http://fqv1.sscrl.vip | 10 | 目录 0 章 | 1.0.103 间接 JSON.parse；待真机验 |
| 26 | ⭐百度小说[官方]v1.0✨ | https://novelapi.baidu.com#百度小说官方API | 10 | 目录 0 章 | 1.0.103 java.getElements JSON；待真机验 |
| 51 | 连尚读书[官方] | https://read.zhulang.com | 20 | 目录 0 章 | 1.0.103 JS+JSONPath 链；待真机验 |
| 73 | ❤️爱下电子 | https://apiv2hans.aixdzs.com | 20 | 目录 0 章 | init=$.data.book 与 toc 结构不匹配 |

## 6. 正文 0 字 / 驱动超时（2 条）

| # | 书源 | URL | 状态 | 搜索/目录/字数 | 问题 | 下一步 |
|---|---|---|---|---|---|---|
| 07 | 📖顶点小说🔥 | http://api.anwaben.com | DRIVER_ERROR | 0/0/0 | TimeoutError；站点侧超时 | 标记失效，不再占并发 |
| 71 | 爱书音 | 爱书音 | FAIL_CONTENT | 38/30/0 | 正文 0 字；搜索/详情/目录已通 | 查 content 规则/资源类型；必要时 webView 兜底 |

## 7. 搜索失败（32 条）

按根因分组；同一条源只出现一次。

### A. 网络断开（5 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 30 | 速读谷 | https://www.sudugu.org | 斗破苍穹 | 搜索失败: The network connection was lost. | 连接断开/HTTP500；标记失效 |
| 33 | 错层小说网 | https://m.cuoceng.org/ | 斗破苍穹 | 搜索失败: The network connection was lost. | connection lost；重试；仍失败则失效 |
| 42 | 速读谷 | https://www.sudugu.org#🐳 | 斗破苍穹 | 搜索失败: The network connection was lost. | 连接断开/HTTP500；标记失效 |
| 57 | Icu | https://ztopaq7zrz.hq555.icu:1678 | 斗破苍穹 | 搜索失败: The network connection was lost. | connection lost；标记失效 |
| 72 | 八叉书库(二合一)☆夜明空☆ | 八叉书库-假(小说漫画二合一)☆夜明空☆ | 斗破苍穹 | 搜索失败: The network connection was lost. | connection lost；切备用域/改默认 host |

### B. 超时（3 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 35 | 得奇小说网 | https://www.deqixs.org | 斗破苍穹 | 搜索失败: WebView fallback timed out | WebView 超时；先修规则/超时，避免重复源 |
| 44 | 52书库 | https://www.52shuku.net#🐳 | 斗破苍穹 | 搜索失败: 连接超时 | 连接超时；重试；不应判死 |
| 50 | 集书阁 | https://mad回家访问25a点jisge点com.jishuge-vip.com/?jifangge | 斗破苍穹 | 搜索失败: 连接超时 | 连接超时；标记失效 |

### C. HTTP 500（1 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 39 | 速读谷 | https://www.shudugu.org/ | 斗破苍穹 | 搜索失败: HTTP 500 | 连接断开/HTTP500；标记失效 |

### D. HTTP 404（1 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 74 | 含遇見 | https://api.whjcgn.online | 斗破苍穹 | 搜索失败: HTTP 404 | HTTP 404；标记失效/找新接口 |

### E. URL 非法（1 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 49 | biquge2345 | https://www.biquge2345.com | 斗破苍穹 | 搜索失败: URL 格式非法或解析异常 (-1000)：https://www.biquge2345.com/s.php | URL -1000；换域名/检查 URL |

### F. JS/响应解析（3 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 12 | 七猫四合一本地版（同人） | 七猫四合一本地版（同人） | 斗破苍穹 | 搜索失败: 搜索规则 JS 异常：Error: 七猫接口返回非 JSON，请检查网络或压缩响应 | 非 JSON；抓响应；加解压/换接口 |
| 15 | 🎉 聚合书库 | https://book4.cc | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 42908 字符；结构 非 JSON：<!DOCTYPE html> <html lan… | 返回 HTML；抓响应；必要时 webView |
| 75 | 紙間·阅读 | https://www.zjread.cc | 斗破苍穹 | 搜索失败: 搜索规则 JS 异常：Error: 响应解析失败 | 响应解析失败；抓响应比对规则 |

### G. 列表 0 项（14 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 04 | ✿次元姬（知秋）✿ | https://cyj.vv9v.cn | 斗破苍穹 | 搜索失败: 搜索列表规则未命中（0 个节点，响应 183 字符） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 05 | 🍓玖玖小说 | https://sunianxin.cmcure.com##玖玖 | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 100 字符；结构 { code,log_id,message }） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 08 | 🍅蕃茄小说 | https://m.dzrjk.com | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 40 字符；结构 { code,data,msg }） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 09 | 聚合书源(zenneko) | https://zenneko.top/api/ | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 160 字符；结构 { error,success }） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 13 | 📚书山聚合 | 书山聚合 | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 94 字符；结构 { cached_at,data,error,isSuccess }） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 17 | NovelHub聚合 | https://sunianxin.cmcure.com | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 113 字符；结构 { code,log_id,message }） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 23 | 番茄🍅（沐凡·PyFQ-Go本地） | https://fqaggregate.de5.net | 斗破苍穹 | 搜索失败: 搜索列表规则未命中（0 个节点，响应 7005 字符） | 列表 0；标记失效/换聚合接口 |
| 27 | 聚合书源 | http://154.12.91.167:9947 | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 39 字符；结构 { count,results,success }） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 28 | 本地番茄红果·mini | 本地番茄红果mini | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 84880 字符；结构 { code,log_id,message,search_tab… | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 37 | QQ浏览器-完整分类-v7 | https://so.html5.qq.com/?legado_source=qqbrowser_categories_v7 | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 24938 字符；结构 { code,data,msg }） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 38 | 塔读小说app v0.12 | https://reader.tadu.com | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 39 字符；结构 { code,data,message }） | 列表 0；抓响应；DES/接口 |
| 41 | 话本小说 | https://www.ihuaben.com | 斗破苍穹 | 搜索失败: 搜索列表规则未命中（0 个节点，响应 8897 字符） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 43 | 千白羽轻小说交流站 | https://www.xiaoxiaoshuo8.com | 斗破苍穹 | 搜索失败: 搜索列表规则未命中（0 个节点，响应 2378 字符） | 列表 0/规则未命中；抓响应比对；换 checkKeyWord |
| 46 | 书音FM | https://m.shuyinfm.com | 斗破苍穹 | 搜索失败: JSON 列表规则未命中（0 项，响应 118 字符；结构 { code,data,message }） | 列表 0；抓响应；换接口 |

### H. 字段为空（2 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 25 | 书旗小说 | https://ocean.shuqireader.com | 斗破苍穹 | 搜索失败: JSON 列表命中 11 项但书名或链接为空 | 11 项字段空；真机日志确认 Cookie 落盘 |
| 36 | 书旗小说本地源（同人） | https://ocean.shuqireader.com#1 | 斗破苍穹 | 搜索失败: JSON 列表命中 11 项但书名或链接为空 | 11 项字段空；同上 |

### I. 相对 URL（1 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 40 | ✿爱丽丝书屋（知秋）✿ | 爱丽丝书屋＃知秋 | 斗破苍穹 | 搜索失败: 不支持的 URL 协议 无：/search.html?q=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B… | 相对 URL；1.0.103 已修，待真机验 |

### J. JS 桥（1 条）

| # | 书源 | URL | 关键词 | 错误摘要 | 根因/下一步 |
|---|---|---|---|---|---|
| 45 | ✿UAA四合一（知秋）✿ | UAA四合一＃知秋 | 斗破苍穹 | 搜索失败: TypeError: undefined is not an object (evaluating '_.java') | _.java 未定义；1.0.103 已修，待真机验 |

## 8. 结论

1. 真正全链路可用的只有 8 条，其中 2 条正文 <500 字（七猫听书 115、有听网 208）。
2. 20 条空壳不是引擎失败，是导入文件本身没有规则；rebuilt 文件已补 2 条，剩 18 条。
3. 48 条有规则失败里，1.0.103 已定向覆盖 8 条（七猫×2、爱丽丝、木里、日落、UAA、百度、连尚），未真机复测。
4. 需要登录的 3 条、书旗 2 条、空壳 20 条，是下一批最明确的工程量。
5. 站点死/瞬断：52书库可重试；Icu、八叉默认域、番茄沐凡、速读谷、集书阁、顶点应标记失效或切备用域。