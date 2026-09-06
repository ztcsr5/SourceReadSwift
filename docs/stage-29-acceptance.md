# Stage 29：Legado 混合响应矩阵与诊断视觉验收

本阶段对应四张诊断/规则编辑参考图。图片仅用于界面结构和信息密度参考，不把其中真实网站、URL、Cookie、token 或账号写入 fixture、日志或自动化测试。

## 四阶段链路

界面必须始终按以下顺序显示并保持可跳转：

```text
搜索 → 详情 → 目录 → 正文
```

规则编辑器使用四段式分段控件：

```text
搜索 | 详情 | 目录 | 正文
```

每个阶段都要能看到：当前规则字段、阶段说明、本地样本预览、一键执行、复制结果和失败修复入口。

## 诊断信息层级

### 响应摘要

动态诊断和导出报告保留以下字段（敏感值只显示 `<redacted>`）：

- HTTP status、method、bytes、contentType
- Set-Cookie/Cookie 的存在性（值必须脱敏）
- attemptedURL、canonicalURL
- pagesLoaded、retainedItemCount
- finalURL、解码状态、Content-Encoding

### 阶段事件

日志列表应使用稳定的机器阶段名，并附带中文标题：

```text
[search.load.response]
[search.parse]
[detail.load]
[toc.pagination.stop]
```

`toc.pagination.stop` 至少说明 `reason`、`pagesLoaded` 和 `retainedItemCount`，以便区分无下一页、空页、重复 URL、重定向循环和达到页数上限。

### 失败分类

视觉诊断必须区分以下情况，不允许统一显示“书源失败”：

- 规则缺失
- JSON/HTML 搜索结果为空
- HTTP 404/403/429
- 请求超时或网络失败
- 解析失败
- JavaScript 异常
- 需要登录/人工验证/被拦截

失败卡片要给出对应阶段和可执行修复建议（例如检查 `ruleSearch.bookList/name/author/bookUrl`、请求方法、Header/Cookie、charset 或 WebView fallback）。

## 本地脱敏回归

Stage 29 fixture 使用 `fixture.example`，覆盖：

1. Search 返回 HTML 外壳中的 JSON；
2. Detail 返回 JSON；
3. TOC 第 1 页 JSON、第 2 页 HTML；
4. Content 第 1 页 JSON、第 2 页 HTML；
5. bodyJs 在阶段之间传递 token/phase；
6. Cookie 从响应进入后续请求；
7. TOC 重复章节去重并重建连续 index；
8. 重定向回已加载页面时输出 `duplicate-final-url`；
9. 导出报告保留字段名但不泄露动态 token/Cookie。

## 验收门

```powershell
git diff --check
node ci-log/extract-prelude.js
node --check ci-log/js-prelude-check.js
```

Windows 不运行 Swift/XCTest。提交后必须由 GitHub Actions 完成 iOS build/XCTest 与 unsigned IPA；真实 iOS 视觉和 120 Hz 仍需真机验收。
