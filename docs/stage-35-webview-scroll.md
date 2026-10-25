# Stage 35 — 滚动模式改用 WebView 渲染（1.0.48）

## 为什么换渲染层

1.0.44–1.0.47 都在 TextKit 表面（`NativeReaderTextView`）上打补丁，症状没消失，因为根因是渲染模型：

| 症状 | 旧实现的成因 |
|---|---|
| 点目录跳章 / 纯上下滑动突然整屏空白 | 窗口变动走 `rebuild()`：先清空 `textStorage`，再 `ensureLayout` 重排。重排那一帧就是白屏 |
| 连续滑动掉帧 | 整窗 `NSAttributedString` 重建落在拖拽帧里；`ReaderRebuildDeferralPolicy` 只能推迟到惯性结束，松手那一下仍然卡 |
| 章标题跟正文一样大小/颜色 | 滚动面拿到的是一维 `[String]`，章节标题只是其中一段文本，没有独立身份 |

## 新结构

- `WebScrollReaderView`（`SourceReadSwift/Features/Reader/`）：`WKWebView` 承载正文，接口与 `NativeReaderTextView` 对齐（同一组字号/行距/内边距/滚动目标/回调），`ReaderView` 只替换了构造调用。
- `WebReaderDocument`：纯逻辑 + 文档壳（CSS/JS），可单测。
  - `WebReaderSection`：章节结构（章节号、标题、段落、是否就绪）。
  - `WebReaderFlatIndexPolicy`：与 `ReaderChapterWindowPolicy.layout` 完全一致的扁平索引规则（第一章从 0 起，之后每章先占一位给分隔标题）。
  - `WebReaderContentPayloadBuilder`：生成 `setContent` 的 JSON（标题单独成元素、`[img]` 段落转图片节点、旧破折号装饰剥离）。
  - `WebReaderStylePayload` / `WebReaderColor` / `ReaderFontFamily.webCSSFamily`：主题与排版映射。
  - `WebReaderImageScheme`：`readerimg://` 方案 + `ReaderImageSchemeHandler`，插图请求仍带书源的 `Referer` / `User-Agent`。

## 三个交付点

1. **不再空白**：内容更新是文档内 DOM 补丁（`setContent` → 复用未变章节节点，`replaceChildren` / 尾部追加），从不重载文档；换章只在首尾增删节点。
2. **位置锚定**：锚点用 `data-key` + `data-local`（章节身份 + 段落局部号），不是扁平编号。上方插入一章时，文档量出插入高度后把滚动位置补回去；同时 `rebaseSection` 重算被复用节点的 `data-flat`，可见段落回报与跳转索引不会错位。
3. **标题样式**：`h1/h2.chapter-title` 独立 CSS —— 1.3 倍字号（下限 +6pt）、700 字重、左侧 3px 主题色竖线、独立上下间距。正文 18px 时标题 26px（headless 实测）。
4. **点击区**：文档内 `pointerdown/pointerup` 判定——位移 > 8px、按住 > 260ms、手势期间滚动过、存在选区、上一个滚动事件距今 < 170ms，任一命中都不算点击；命中后把 CSS 像素坐标回传 `handleReaderTap(at:)`，继续沿用 3×3 点击区配置。滚动模式下 SwiftUI 的 `DragGesture` 让路，避免一次点击翻两页。

## 验证

- `SourceReadSwiftTests/WebReaderDocumentTests.swift`：扁平索引与窗口布局逐章一致、payload 结构、图片切分、标题字号、行高换算、颜色、JS 字面量转义、文档壳关键规则。
- headless Chromium 走真实 DOM（3 章 75 段，viewport 390×844）：
  - 标题 26px/700/3px 竖线，正文 18px；
  - `scrollToFlat(53)` 落到 2315px，`visible` 回报 53；
  - 翻页 3294 → 3953（0.88 视口）；
  - 普通点击上报、拖 70px 不上报、刚滚动 170ms 内不上报、超出窗口上报；
  - 顶部再点上一页触发 `page-boundary`；
  - 上方插入 20 段章节后，顶端仍是同一段（`c1` / `local 13`），扁平号 54 → 75，`data-start` 重算为 21；
  - 全程 `window.onerror` 为空。
- 版本三处同步：`project.yml` 1.0.48/49、`AppVersion.minor=48/build=49`、`SearchURLResolverTests` 断言。

## 已知取舍

- 滚动模式下页脚（页码/电量）本来就不显示，本次不涉及。
- 平滑滚动优先用平台 `scrollTo({behavior:'smooth'})`；若平台忽略（Reduce Motion / 无合成器），90–160ms 内检测到位移为 0 就直接落位，避免点击无反应。
- 插图经 `readerimg://` 方案加载；若某张图取不到，只留占位底色，不影响正文。
