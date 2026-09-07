# 已测试.json 书源能力表

- 数据源：`D:\QQ游戏\已测试.json`
- 样本数：13
- 结论：这 13 个源都已覆盖 Search → Detail → TOC → Content 主链；真正拉开差距的是 JS、POST、Cookie、登录/验证、加密、字体反爬和图文混排。

## 能力概览

| 能力 | 覆盖 |
|---|---:|
| Search | 13/13 |
| Detail | 13/13 |
| TOC | 13/13 |
| Content | 13/13 |
| Explore | 10/13 |
| CookieJar | 10/13 |
| JS-heavy | 8/13 |
| POST-search | 7/13 |
| GBK | 4/13 |
| Login/CF-check | 3/13 |
| Crypto/AES/Base64 | 3/13 |
| Font-obf/Image-text | 3/13 |
| Paging | 13/13 |

## 分层结论

- **A 级**：纯网页/轻量规则，主链稳定，额外复杂度少。
- **B 级**：JS-heavy 或 POST 搜索，已经依赖运行时桥接。
- **C 级**：登录/验证、AES/Base64、字体反爬、图文混排，属于最值得继续巩固的高复杂源。

## 源明细

| # | 书源 | 等级 | 额外能力 |
|---:|---|:---:|---|
| 1 | 第一版主网🔞 | B | Explore、JS-heavy、Paging、GBK |
| 2 | 🔞🔲第一版主999 | C | Explore、POST-search、CookieJar、JS-heavy、Login/CF-check、Crypto/AES/Base64、Font-obf/Image-text、Paging、GBK |
| 3 | 📪第一版主820 | C | Explore、POST-search、CookieJar、JS-heavy、Login/CF-check、Crypto/AES/Base64、Font-obf/Image-text、Paging、GBK |
| 4 | 要撸小说 | C | Explore、POST-search、JS-heavy、Crypto/AES/Base64、Paging |
| 5 | 久久小说网 | B | Explore、POST-search、CookieJar、Paging |
| 6 | 希望中文 | C | POST-search、CookieJar、JS-heavy、Login/CF-check、Paging、GBK |
| 7 | 风读小说 | C | Explore、JS-heavy、Font-obf/Image-text、Paging |
| 8 | 六月中文网 | A | CookieJar、Paging |
| 9 | 爱下电子书 | B | Explore、CookieJar、JS-heavy、Paging |
| 10 | 速读谷 | A | Explore、CookieJar、Paging |
| 11 | 番茄小说 | B | Explore、POST-search、CookieJar、JS-heavy、Paging |
| 12 | 小原文学网 | B | Explore、POST-search、CookieJar、Paging |
| 13 | 新版笔趣阁 | A | CookieJar、Paging |

## 对后续工作的含义

- **可直接复用**：主链四段对这 13 个源都不是问题。
- **继续巩固**：JS-heavy、POST-search、CookieJar、登录/验证、加密、字体反爬。
- **阶段建议**：下一步应把这份表接到 XCTest/fixture，形成「源样本 → 预期覆盖 → 失败分类 → 修复入口」闭环。
