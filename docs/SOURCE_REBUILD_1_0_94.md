# 空壳书源重建报告 · 1.0.94（数据修复，无 App 代码改动）

生成时间：2026-10-28
输入库：`D:\QQ游戏\shareBookSource11.json`（76 条）
输出：
- `docs/sources/rebuilt-empty-sources-1.0.94.json`（只含本轮重建的 2 条，直接导入）
- `docs/sources/shareBookSource11-rebuilt-1.0.94.json`（76 条合并版，替换原 2 条空壳）

## 1. 结论

“空壳占位条目”不是 Swift 引擎 bug，是书源条目本身只有 11 个基础字段：
`bookSourceName / bookSourceUrl / enabled / ...`，没有 `searchUrl`、`ruleSearch`、`ruleBookInfo`、`ruleToc`、`ruleContent`。
引擎再完整也无规则可执行。修法是重写这 20 条规则，**不需要改 App**。

本轮已把其中同 CMS 的 2 条完整重建并跑通四段链路：

| 书源 | 搜索 | 详情 | 目录 | 正文 |
|---|---|---|---|---|
| 天域小说 | 200 / 100 条 | 200 / 书名+作者+简介+封面 | 11 页 / 531 章 | 1093 字 + 下一页 1108 字 |
| 爱奇电子书 | 200 / 100 条 | 200 / 书名+作者+简介+封面 | 1 页 / 531 章 | 1093 字 + 下一页 1108 字 |

验证方式：Python requests + BeautifulSoup 按 Legado 规则语义逐段执行（搜索→详情→目录→正文→正文下一页），
真实 HTTP 响应，非 mock。`verdict = PASS_FULL`。

## 2. 重建后的规则（两条同构，只换域名与搜索路径）

```json
{
  "searchUrl": "http://www.tianyu8.org/search5b.html?searchkey={{key}}",
  "ruleSearch": {
    "bookList": "@css:#hotcontent .item",
    "name": "@css:dt a@text",
    "author": "@css:.btm a@text",
    "intro": "@css:dd@text",
    "coverUrl": "@css:img@data-original||@css:img@src",
    "bookUrl": "@css:dt a@href"
  },
  "ruleBookInfo": {
    "name": "@css:h1@text",
    "author": "@css:#info a[href^=\"/author/\"]@text",
    "intro": "@css:#intro@text",
    "coverUrl": "@css:#fmimg img@data-original||@css:#fmimg img@src",
    "tocUrl": "@css:a.chapterlist@href",
    "lastChapter": "@css:#info p.hidden-xs a[rel=chapter]@text"
  },
  "ruleToc": {
    "chapterList": "@css:#content_1 a",
    "chapterName": "text",
    "chapterUrl": "href",
    "nextTocUrl": "@css:#list dt a:contains(下一页)@href"
  },
  "ruleContent": {
    "content": "@css:#booktxt@text",
    "nextContentUrl": "@css:a[rel=next]@href"
  }
}
```

爱奇把 `searchUrl` 换成 `http://www.xqb8.org/soso5b627.html?searchkey={{key}}`，其余相同。

## 3. 20 条空壳逐条判定（真实探测）

| # | 书源 | 现状证据 | 判定 |
|---|---|---|---|
| 1 | 得奇小说网 | `deqixs.co` 301→`deqixss.com`；搜索/详情/目录可用；正文由 `scripts/chapter.js.php` 动态解密，HTML 里 `#chapter-content` 为空 | 搜索+目录可修，正文需 WebView/JS 逆向 |
| 2 | 书音FM | 有声站，首页 200，无搜索表单 | 需抓 JS/API，优先级低 |
| 3 | bqg128 | 首页 200；`/s?q=` 返回 4.3KB 但 0 命中 | 需找 JS 搜索接口 |
| 4 | 小说狂人 czbooks | 首页 200；搜索框不在 form 内；`/search` 404 | 需抓 JS 搜索接口 |
| 5 | 爱奇电子书 | 搜索 100 条 → 详情 200 → 目录 531 章 → 正文 2 页 | **PASS_FULL（已重建）** |
| 6 | 七猫 | `api-bc.wtzw.com` 200 空响应，纯 API | 需接口签名/鉴权（另有七猫分析文档） |
| 7 | 言情小说网 | EmpireCMS POST 搜索成功（`/e/search/index.php`）；详情无目录，`_N.html` 是章节，尾页 `_310.html` | 搜索可修，目录需 JS 生造 |
| 8 | 漫蛙 | 所有路径都返回同一 6.9KB 页面 | SPA/反爬，暂缓 |
| 9 | 365小说 | 首页 200 / 58KB，无搜索表单 | 需找入口 |
| 10 | 肉书屋 | POST `/s.php` 搜索，POST 超时 | 站点慢，需重试/换线路 |
| 11 | 阅友小说 | 首页 70KB，无表单 | 需找入口 |
| 12 | 东滩小说 | 首页 32KB，无表单 | 需找入口 |
| 13 | 台湾小说 | 首页 403（Cloudflare/UA 拦截） | 当前死源 |
| 14 | 茶马小说 | 搜索 `main?q=`；书页 `_1.html`，章节 `_2.._110.html`，无目录列表 | 正文可读，目录需 JS 生造 |
| 15 | 天域小说 | 搜索 100 条 → 详情 200 → 11 页 531 章 → 正文 2 页 | **PASS_FULL（已重建）** |
| 16 | 夜读阁 | 搜索/详情/目录 OK；正文 617 字后提示“后续内容已被隐藏，需要VIP会员” | 付费源，不能算完整 |
| 17 | 米读小说 | `api.midukanshu.com` 200 / 2B | 纯 API，需接口 |
| 18 | 御书屋 | SSL EOF | 当前死源 |
| 19 | 八叉书库 | EmpireCMS 搜索/详情/目录 OK；正文“精彩内容正在加载中…” | 正文需 WebView/JS |
| 20 | 宝华书院 | 搜索 POST 返回 553B“内容正在载入……” | 反爬，需 Cookie/JS |

## 4. 为什么不能“20 条全绿”

这 20 条不是同一类问题，至少分 6 类：

1. **同 CMS 可直接重建**：天域、爱奇（已做）。
2. **HTML 可读但无目录页**：言情、茶马（章节 URL 规则是线性的 `_N.html`，要 JS 生成目录）。
3. **正文 JS 渲染**：得奇、八叉（需要 WebView 等 JS 执行完再取 DOM）。
4. **纯 API/有声**：七猫、米读、书音FM（需要接口签名，不是 HTML 规则）。
5. **付费墙**：夜读阁（VIP 截断）。
6. **当前死亡/反爬**：台湾 403、御书屋 SSL EOF、宝华 553B、漫蛙 SPA。

因此正确目标不是“20 条全部 PASS”，而是“能重建的重建、能标记的标记、不要用假规则充数”。

## 5. 导入方法

1. App → 书源管理 → 导入本地文件；
2. 只想要修复的两条：选 `rebuilt-empty-sources-1.0.94.json`；
3. 想整库替换：选 `shareBookSource11-rebuilt-1.0.94.json`（其余 74 条原样保留）。

导入后建议先各搜一次“斗罗”，确认列表出现 100 条；再打开任意一本，确认目录 531 章、正文可翻下一页。

## 6. 后续可继续做的（按收益排序）

1. 得奇：给 `ruleContent` 加 `webView` 选项，真机验证 `#chapter-content` 是否在 JS 执行后出现；
2. 八叉：同上，验证 `.chapter-content`；
3. 言情/茶马：用 `ruleToc.chapterList` 的 `@js:` 规则，从详情页“尾页”链接生成 `_1.._N` 章节列表；
4. 七猫/米读：按 `docs` 里已有的接口分析补签名与鉴权；
5. 台湾/御书屋/宝华：标记失效，不再浪费并发。

