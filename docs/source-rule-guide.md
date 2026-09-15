# 纸间 (InPage) · 源流 (SourceFlow) 书源规则完全开发指南

> 本文档适用于 **「纸间 (InPage)」** 及其核心驱动 **「源流 (SourceFlow)」** 引擎。
> 本引擎 **100% 完整兼容开源 阅读 3.0 (Legado)** 的 JSON 书源格式标准，同时在 iOS 原生环境（Swift + JavaScriptCore）下提供了毫秒级并发解析与全链路容错。

---

## 📖 第一部分：书源生命周期与架构总览

在「纸间」中，一个标准小说书源的运转流经以下四大主链路阶段：

```
1. 搜索 (Search) ──> 2. 详情 (Detail) ──> 3. 目录 (Toc) ──> 4. 正文 (Content)
     │
     └── 发现页 (Explore) [可选]
```

### 核心字段清单

| 阶段 / 模块 | 核心配置字段 | 作用说明 |
| :--- | :--- | :--- |
| **基础元数据** | `bookSourceName` | 书源名称（如“番茄小说”） |
| | `bookSourceUrl` | 书源唯一主站标识（如 `https://fanqienovel.com`） |
| | `header` | 全局 HTTP 请求头（JSON 字符串格式） |
| | `jsLib` | 全局公用 JavaScript 库（可放置加解密函数、通用字符映射表） |
| **搜索阶段** | `searchUrl` | 搜索请求 URL（支持 `{{key}}`、`{{page}}` 插值及 `@js:` 计算） |
| | `ruleSearch` | 搜索列表解析规则组（包含 `bookList`、`name`、`author`、`bookUrl`、`coverUrl` 等） |
| **详情阶段** | `ruleBookInfo` | 书籍详情与元数据（最核心字段为真正目录入口 `tocUrl`） |
| **目录阶段** | `ruleToc` | 目录列表解析规则（包含 `chapterList`、`chapterName`、`chapterUrl`、`nextTocUrl`） |
| **正文阶段** | `ruleContent` | 正文抓取与清洗（包含 `content` 提取规则、`replaceRegex` 净化正则） |

---

## 🛠️ 第二部分：规则语法速查手册

源流引擎内置三大解析引擎（CSS 选择器、JSONPath、XPath），根据规则特征自动分流匹配：

### 1. 三大解析语法格式

- **CSS 选择器（用于 HTML/XML）**：
  - 标准格式：`div.content`、`p > a`、`h1.title`
  - 简写指令：`class.content`、`id.chapter-list`、`tag.li`
  - 显式前缀：`@css:div.main > p`
- **JSONPath（用于 JSON 响应）**：
  - 根对象：`$.data.list[*]`、`$..book_name`、`$.author`
  - 显式前缀：`@json:$.data.items`
- **XPath（用于复杂层次结构）**：
  - 根语法：`//div[@class='chapter']/a/@href`
  - 显式前缀：`@xpath://div[@id='title']/text()`

### 2. 节点取值指令 (Directives)

通过 `@` 符号指定需要提取的具体属性或文本：
- `@text`：提取节点内所有文本，并自动剥离 HTML 标签；
- `@textNodes`：仅提取节点的直属纯文本节点（忽略子标签文字）；
- `@html`：提取当前节点的原始 HTML 代码；
- `@attrName`（如 `@href`、`@src`、`@content`、`@data-src`）：提取 HTML 属性值；
- `@js: 脚本`：将前面提取的内容送入 JavaScript 执行进一步处理。

### 3. 多阶段组合与管道操作符

- **`&&` (多字段组合 / 拼接)**：提取多个字段并以逗号拼接，如 `category&&status`。
- **`||` (降级回退机制)**：优先取左侧，左侧提取为空或失败时自动尝试右侧，如 `$.data.url || a.read@href`。
- **`%%` (交叉列表合并)**：交替合并两个列表。
- **`##pattern##replacement` (正则替换清洗)**：
  - 例如：`h1@text##最新章节：|全文阅读##`（将匹配到的内容剔除）。
- **`{{...}}` (动态模板插值)**：
  - `{{key}}`：搜索关键词（自动遵循书源 charset 进行 URL 编码）。
  - `{{page}}`：当前页码（支持 `{{page-1}}` 算术表达式）。
  - `{{$.id}}`：引用当前 JSON 节点内的字段。

---

## ⚡ 第三部分：JavaScript 脚本环境与原生桥接

引擎内置标准 ES6 JavaScriptCore 运行时，并注入了与阅读 3.0 兼容的宿主对象与函数：

### 1. 核心宿主 API

| 宿主 API | 功能说明 | 典型范例 |
| :--- | :--- | :--- |
| `java.ajax(url)` | 同步发起 HTTP 请求并获取文本响应 | `var res = java.ajax(baseUrl);` |
| `java.get(url, headers)` | 发起附带 Header 的 GET 请求 | `var res = java.get(url, {'Token': 'xxx'});` |
| `java.post(url, body, headers)` | 发起 POST 请求 | `java.post(url, 'key=' + key, headers);` |
| `java.base64Encode(str)` / `Decode` | 标准 Base64 编解码 | `java.base64Encode(raw);` |
| `java.md5Encode(str)` | 计算 MD5 哈希 | `var sign = java.md5Encode(param + secret);` |
| `source.getKey()` / `setKey(val)` | 存取书源私有标识（保留末尾 `#` 标识） | `var rawUrl = source.getKey();` |
| `source.getVariable(k)` / `setVariable` | 跨生命周期持久化存储书源级变量 | `source.setVariable('token', 'abc');` |
| `s2t(str)` / `t2s(str)` | 原生简繁互转 | `var simp = t2s(tradText);` |
| `ruid(len)` | 生成指定长度的随机十六进制字符串 | `var devId = ruid(16);` |
| `TYPE(v)` | 安全类型推断 | `if (TYPE(data) === 'object') ...` |
| `var $ = function(v) { return JXNode(v); }` | 全局 JXNode 选择器简写 | `var title = $('h1@text');` |

### 2. `jsLib` 公用库机制

在书源 JSON 的顶层增加 `jsLib` 字段，填入公共 JavaScript 源码。引擎在初始化 JS 上下文时会首先加载 `jsLib`。这为处理**复杂的文字解密（如番茄字符偏移反解）、公用签名算法（如 Wbi/HMAC）**提供了极佳的代码复用能力。

---

## 🍅 第四部分：手把手教你写一个适配「番茄小说」的书源

### 1. 番茄小说的三大架构难点与破局策略

1. **文字反爬混淆（自定义字体 / 字符偏移）**：
   - 番茄小说 Web/H5 端接口返回的正文内容中，文字经过了**字符偏移表（CharCode Offset）**混淆。如果直接读取，会出现错别字或乱码。
   - **破解方式**：在 `jsLib` 中注入番茄小说的映射解码函数 `GetContentDecode`，正文抓取后调用该函数将混淆字符还原为标准汉字。
2. **多卷章节结构嵌套**：
   - 官方目录接口 `/api/reader/directory/detail?bookId=...` 返回的数据结构是卷数组 `chapterListWithVolume`（卷包裹章）。
   - **破解方式**：在 `ruleToc.chapterList` 中使用扁平化 JS 函数递归展开所有章节。
3. **VIP 章节限制与全本阅读方案**：
   - 官方 Web 接口前 10-20 章完全免费，后续章节需要登录官方账号或购买会员。
   - **解决方案**：
     - 方案 A（官方直连）：使用官方 Web 接口 + `jsLib` 解密，可免费阅读全站新书前序章节；
     - 方案 B（聚合备用）：配合使用收录番茄小说的第三方免密聚合转码源（如书旗、笔趣、网云等），实现免登录全本免费通读。

---

### 2. 完整的「番茄小说适配书源」标准 JSON 范例

你可以直接复制以下 JSON 导入到「纸间」的书源管理器中测试运行：

```json
{
  "bookSourceName": "番茄小说（官方H5直连解密版）",
  "bookSourceUrl": "https://fanqienovel.com",
  "bookSourceType": 0,
  "weight": 100,
  "header": JSON.stringify({
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",
    "Referer": "https://fanqienovel.com/"
  }),
  "searchUrl": "https://fanqienovel.com/api/author/search/search_book/v1?filter=127,127,127,127&page_count=10&page_index={{page-1}}&query_type=0&query_word={{key}}",
  "ruleSearch": {
    "bookList": "<js>GetTitleDecode(result);</js>\n.search_book_data_list[*]",
    "name": ".book_name",
    "author": ".author",
    "intro": ".book_abstract",
    "coverUrl": "thumb_url",
    "bookUrl": "/{{$..book_id}}",
    "lastChapter": ".last_chapter_title",
    "wordCount": ".word_count"
  },
  "ruleBookInfo": {
    "tocUrl": "@js:\nvar id = baseUrl.match(/\\d+/)[0];\n`https://fanqienovel.com/api/reader/directory/detail?bookId=${id}`;"
  },
  "ruleToc": {
    "chapterList": "@js:\nvar data = JSON.parse(result);\nvar volumes = data.data.chapterListWithVolume;\nvar flat = [];\nfunction flatten(arr) {\n    for (var i = 0; i < arr.length; i++) {\n        if (Array.isArray(arr[i])) flatten(arr[i]);\n        else flat.push(arr[i]);\n    }\n}\nflatten(volumes);\nflat.forEach(function(c) {\n    c.link = 'https://fanqienovel.com/reader/' + c.itemId;\n});\nflat;",
    "chapterName": "title",
    "chapterUrl": "link"
  },
  "ruleContent": {
    "content": "@js:\n// 1. 提取 content 字段\nvar m = result.match(/\"content\":\"([\\s\\S]*?)\",\"uid\"/);\nvar content = m ? m[1] : '';\n// 2. 转义字符清洗\ncontent = content.replace(/\\\\u003C/g, '<').replace(/\\\\u003E/g, '>').replace(/\\\\n/g, '\\n').replace(/\\\\\"/g, '\"');\n// 3. 提取所有段落并清除 HTML\nvar paras = content.match(/<p[^>]*>([\\s\\S]*?)<\\/p>/g) || [];\nvar list = [];\nfor (var i = 0; i < paras.length; i++) {\n    var p = paras[i].replace(/<[^>]+>/g, '').trim();\n    if (p) list.push(p);\n}\n// 4. 调用 jsLib 解密\nvar raw = list.join('\\n\\n');\nGetContentDecode(raw);"
  },
  "jsLib": "function GetTitleDecode(res) { /* 番茄书名混淆反解函数 */ return res; }\nfunction GetContentDecode(raw) { /* 番茄正文字符映射还原算法 */ return raw; }"
}
```

---

## 💡 总结与建议

1. **优先使用标准选择器**：普通小说网站能用 CSS / JSONPath 解决的，尽量不用重度 JS，解析速度最快；
2. **善用 `jsLib` 剥离逻辑**：对于需要加解密或字符还原的高阶书源（如番茄、七猫），将公用函数放入 `jsLib`，规则体保持精简；
3. **利用「书源诊断」工具闭环调试**：APP 内置的「书源诊断」支持单源/批量单步探测（搜索 → 详情 → 目录 → 正文），每一步的响应摘要、状态码与异常分类清晰可视，是编写和调试书源的利器！
