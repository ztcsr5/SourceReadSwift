# 纸间阅读器 · 阅读模块完整记录（1.0.30 → 1.0.52）

> 来源：旧会话 `session-830a2381-38fa-41b1-a1f2-7d9efa5fd76c`（1.0.30–1.0.47）+ 本会话（1.0.48–1.0.52）。
> 记录原则：只写实际发生的事；哪些是观测、哪些是推断、哪些没验证，逐条标明。
> 仓库：`D:\Gemini反重力\SourceReadSwift2`　分支：`codex/reader-feedback-fixes`

---

## 0. 一句话总结

阅读模式在 1.0.30–1.0.47 一直在 TextKit 表面（`NativeReaderTextView`）上打补丁，而三个核心症状（跳章空白、连续滑动卡顿、章标题与正文同款）来自**渲染模型本身**；1.0.48 起滚动模式改用 WKWebView + 文档内 DOM 补丁，1.0.49–1.0.52 再补连续阅读、EPUB 身份、搜索/发现性能、页脚排版、菜单位移与文档自愈。**目前仍有两项没有真机证据：快速滑动卡死的根因、120Hz 的实际帧率。**

---

## 1. 旧会话（session-830a2381）留下的上下文

会话标题「阅读APP」，目标（goal `goal-7ba415d3`，30 轮、22 轮已用、状态 complete）：

> 纸间 1.0.35+ 交付：① #4 进书空白——首章预加载/骨架屏 + 吃磁盘缓存；② #5 点击区域过敏感——位移+时长阈值，与滚动共存；③ #6 本地书在阅读器内点书籍详情闪退；④ 依据「轻阅书源诊断数据_1792882175.json」定位书源失败阶段并按失败类型改解析层；⑤ 每次改动版本 +1（project.yml / AppVersion / 测试断言三处同步），推送后 iOS + Unsigned IPA 双 CI 全绿，新 IPA 落到桌面。

会话里已经确定的关键事实（对本轮仍有约束）：

| 事实 | 含义 |
|---|---|
| 项目 294 个 Swift 文件 / 76,251 行 | 只看阅读链路，不可能整包重读 |
| 出网受限：`git push` 连不上 github.com:443 | 27 个 `push_round*.ps1` 走 GitHub REST API 提交 |
| CI 只有两条 workflow | `iOS`（Build + Test，零产物）、`Unsigned IPA`（只出 `SourceReadSwift-<版本>-unsigned.ipa`） |
| IPA 落桌面命名 | `SourceReadSwift-<版本>-unsigned.ipa` |
| 版本三处同步 + `project.yml` 必须 LF | 否则 `::error::Version drift` 直接红 |
| 1.0.44–1.0.47 的修法 | 占位层、标题去破折号、点击阈值、掉帧阈值——都还在 TextKit 表面上 |

### 1.1 旧会话逐版摘要（来自会话 turnOutline）

| 版本 | 做了什么 | 结果 |
|---|---|---|
| 1.0.30 | 首轮 16 条需求里的 14 条 | 9 次 CI |
| 1.0.32 | 「每次改动版本 +1」规则落地 | 新 IPA 落桌面 |
| 1.0.34 | 状态栏/时间/章节/电量位置上移、外观主题等 8 条里改 5 条 | — |
| 1.0.35 | #4 进书空白（首章预加载 + 骨架屏）、#5 点击过敏（位移/时长阈值）、#6 闪退 | — |
| 1.0.37 | 修 31 条「URL 格式非法」 | — |
| 1.0.40 | #4 真预加载 | — |
| 1.0.41 | 14s 超时对齐 20s | — |
| 1.0.42 | 搜索接口「空结果不重试」 | — |
| 1.0.43 | 目录空结果交叉兜底 | — |
| 1.0.44 | 占位层不再盖住正文（滑动跨章空白） | 后续复查：仍会白 |
| 1.0.45 | 章标题去破折号、点击阈值收紧 | 标题与正文同款 → 更糟 |
| 1.0.47 | 掉帧判定阈值 1.5x → 2x | 用户实测仍掉帧 |

旧会话最后一轮（turn 40）的结论是：**「问题出在滚动阅读的渲染模型，不在补丁层」**，并明确「当前会话工作余量见底，做不到一次全修」。这句话是本轮 1.0.48 换渲染层的直接依据。

---

## 2. 版本时间线（本会话）

| 版本 | commit | 主题 | 交付物 |
|---|---|---|---|
| 1.0.48（49） | `b923eab` | 滚动模式改 WKWebView 渲染 | IPA `2000A1E1…` |
| 1.0.49（50） | `c6b354e` | 连续阅读预取、首开回顶、EPUB 三连修、搜索/发现性能 | IPA `421C3A22…` |
| 1.0.50（51） | `690e649`（REST API 推送） | 页脚贴底、正文排满、主题即时生效、点击防重、120Hz 采样 | IPA `95A9CFB7…` |
| 1.0.51（52） | `11834068`（REST API 推送） | 冻结缓解、分页排版一致、目录背景 | IPA `B072B86F…` |
| 1.0.52（53） | `7e4ac71`（REST API 推送） | 菜单不再挤正文、WebView 脚本自愈、NaN 闸门、显示兜底 | IPA `2D377688…` |

所有版本的 IPA 都落在 `C:\Users\Edc21\Desktop\`，文件名 `SourceReadSwift-<版本>-unsigned.ipa`。

---

## 3. 1.0.48：滚动模式换渲染层

### 3.1 为什么换

| 症状 | 旧实现（TextKit）的成因 |
|---|---|
| 点目录跳章 / 纯上下滑突然整屏空白 | 窗口变动走 `rebuild()`：先清空 `textStorage`，再 `ensureLayout` 重排，重排那一帧就是白屏 |
| 连续滑动掉帧 | 整窗 `NSAttributedString` 重建落在拖拽帧里；`ReaderRebuildDeferralPolicy` 只能推迟到惯性结束 |
| 章标题与正文一样大、一样颜色 | 滚动面拿到的是一维 `[String]`，章节标题只是数组里的一段文本，没有身份 |

### 3.2 新结构

| 文件 | 职责 |
|---|---|
| `Features/Reader/WebScrollReaderView.swift` | `UIViewRepresentable` 包 `WKWebView`；接口与 `NativeReaderTextView` 对齐（字号/行距/内边距/滚动目标/边界回调/点击上游） |
| `Features/Reader/WebReaderDocument.swift` | 纯逻辑 + 文档壳（CSS/JS）：`WebReaderSection`、`WebReaderFlatIndexPolicy`、payload 构建、`readerimg://` 方案、JS 字面量转义 |
| `Features/Reader/ReaderView.swift` | 滚动分支切到 `WebScrollReaderView`；滚动模式下 SwiftUI 点击手势让路 |
| `SourceReadSwiftTests/WebReaderDocumentTests.swift` | 索引/载荷/字号/颜色/转义/文档壳单测 |

### 3.3 三个交付点

1. **不再空白**：内容更新是文档内 DOM 补丁（复用未变章节节点、尾部追加 / `replaceChildren`），从不重载文档。
2. **位置锚定**：锚点用 `data-key`（章节）+ `data-local`（段落局部号），不是扁平编号；上方插入章节后 `rebaseSection` 重算被复用节点的 `data-flat`。
3. **标题与点击区**：`h1/h2.chapter-title` 独立 CSS（1.3 倍字号、700 字重、左侧 3px 主题色竖线）；点击在 JS 里过五道闸（位移 >8px、按住 >260ms、手势内滚动、有选区、上个滚动事件 <170ms）。

### 3.4 验证

- CI：iOS（Build + Test）与 Unsigned IPA 双绿；新单测在 CI 内跑过。
- headless Chromium 真实 DOM（3 章 75 段，390×844）：跳段落点 2315px、`visible` 回报 53、翻页 3294→3953、点击上报/拖拽过滤/滚动窗口过滤、顶部触发 `page-boundary`、**上方插入 20 段章节后顶端仍是同一段（`c1`/`local 13`，扁平号 54→75，`data-start` 重算为 21）**、`window.onerror` 为空。

---

## 4. 1.0.49：连续阅读 + 首开回顶 + EPUB + 搜索发现

### 4.1 阅读（用户 1.0.47 反馈）

| 投诉 | 处理 | 依据/局限 |
|---|---|---|
| 章节加载不是无限流、一章看完卡一下（本地书也是） | 预取半径：本地 4 章 / 书源 2 章；追加触发从「离底 650px」提到「1.6 屏」；去掉尾部「正在加载本章…」 | 书源本身慢时仍受网络限制 |
| 打开不在顶部、标题看不见 | `resetToken = bookID`：换书且无显式跳转目标时文档滚回 0 | WKWebView 会被复用，上一本滚动位置会带进来 |
| 滑动几下却跳了好几次 / 点击太快 | 阈值收紧（10px / 320ms / 260ms 静默窗）+ 分页模式 0.28s 点击冷却 | 真机行为待确认 |

### 4.2 EPUB（1.0.43 遗留）

三层各自断掉，不是「解析回落」：

1. **徽标变 TXT**：`BookshelfBook(localTextBook:)` 对 TXT/EPUB 统一写 `sourceURL=local://text`，书架徽标用 `id/title 含 .epub` 判断 → 永不成立。新增 `isLocalEPUB`（导航条目或章节 `sourcePath`）。
2. **目录不显示**：`SearchBook.id` 是派生值 `sourceURL|bookURL`，不等于存储 id `local|<UUID>`，详情页 `book(id:)` 恒 nil。`BookshelfStore` 增加 `resolvedIndex/localBook(matching:)` 按 `bookURL` 回退；本地章节直接进 `BookshelfReaderGatewayView`（原来走 `ChapterLoadingView` 必报「找不到书源」）。
3. **封面不显示**：封面早已抽取落盘并写进 `coverURL`（`file://`），但 `RemoteImageLoader` 只认 `HTTPURLResponse` → 永远占位图。新增 `isFileURL` 分支。
4. 另修真实漏洞：AirDrop/分享进入的无扩展名副本会被当 TXT 切成一章「全文」→ `looksLikeEPUB`（ZIP 魔数 + `META-INF/container.xml`）。

### 4.3 搜索 / 分类发现

| 投诉 | 真因 | 处理 |
|---|---|---|
| 搜索慢，书源少更慢 | 搜索末尾 `await zlibSearchTask.value`，Z-Library 资源超时 60s；批屏障「每批等最慢」 | 源阶段结束即出结果；zlib 8s 超时后取消、晚到增量合并；`withTaskGroup` 恒定 12 并发 + 20s 总预算 |
| 搜索结果/分类卡 | 每帧 3 次全量分组排序；每行 3 次书架线性扫描；`normalized/cleanTitle` 每次编译 7 条正则，旧代码还在 sort 比较器里重算 | `results.didSet` 时算一次派生结果；`BookshelfMembership` 每帧一次 `Set` 快照；正则静态缓存 + `BookProfile` 每本只归一化一次；排序移后台、发布 200ms 节流 |
| 分类点了没反应 | `ExploreViewModel` 三个静默 `return`；取消后 `isLoadingMore` 不复位 → 转圈不停、分页不再触发 | `loadGeneration` 先 cancel+bump 再守卫；失败一律可见文案 + 重试条 |
| 分类列表卡 | 外层 `ScrollView > VStack`，整页 eager 构建 | `LazyVStack` |

---

## 5. 1.0.50：排版与 120Hz

| 需求 | 处理 |
|---|---|
| 非滑动模式状态条贴底、正文排满（学益达 P2/P3） | 页脚 `padding(.bottom, max(safeInset*0.25,2))` + `.ignoresSafeArea(edges:.bottom)`；分页底部预留从 `pagePadding + footerHeight`（≈118pt）改为 `pagePadding*0.5 + 26` |
| 换主题要翻页才生效（P4 层级） | page-curl 每页是创建时快照，只有 `contentRevision` 变才重建；`readerPageCacheKey` 追加 `backgroundRawValue` + 明暗外观 |
| 底部不要那条带、顶部收窄 | `defaultTopInset` 56 → 44（`minimumTopInset`：padding 20→44、48→56、60→68），测试断言同步 |
| 120Hz | `ReaderFrameRateSampler` 的 `CADisplayLink` 显式设 `preferredFrameRateRange`（min 80 / max+preferred = 屏幕上限）；Info.plist 的 `CADisableMinimumFrameDurationOnPhone` 本就在 |
| 点击跳页（视频 36 帧分析） | `handleReaderTap` 加 0.28s 冷却，防「同一帧两个来源各判一次点击」 |

验证：CI 双绿；IPA 1.0.50 `95A9CFB7…`。**未验证**：真机帧率、手势跳页是否消失。

---

## 6. 1.0.51：冻结缓解与排版一致

| 用户反馈 | 处理 | 性质 |
|---|---|---|
| 轻轻滑一下卡死（快滑触发），重开 App 仍空白 | 窗口半径 4→2；每章 `contain: layout style paint`；`visible` 回传 120ms 节流 | 抑制最可能的两个爆炸点，**根因未证实** |
| 弹菜单正文下降一格 | 分页模式 `pageTopInset` 改常量 | 只修了分页模式，滑动模式漏了（见 1.0.52） |
| 目录下滑露白 | TOC List 加主题背景 `.background(readerThemeBackground.ignoresSafeArea())` | — |
| P3 底部拉条超出选项框 | **未修**（需要指出是哪个面板） | 待补信息 |
| 非滑动模式正文还是空 | 排版 37pt / 渲染 64pt 不一致 → 统一 `pagedBottomPadding` | — |

---

## 7. 1.0.52：菜单位移、脚本自愈、NaN 闸门

1. **菜单位移真因**：视频是滑动模式，而滑动模式传给 WebView 的 `topInset` 仍随 `showOverlay` 变化（24 ↔ 56），菜单一开 CSS 顶内边距变大 → 整页下移。改为常量 `minimumTopInset`。
2. **空白卡死三道硬保护**：
   - 文档 `window.onerror` → 原生销毁重建文档（最多 2 次），保留内容与目标段落；
   - 所有 `scrollTo` 经 `safeScrollTo`，`isFinite` 不成立丢弃；`restoreAnchor` 的 target 同校验（NaN 会让 WebKit 滚动手势永久失效）；
   - `.onAppear` 里**无条件** 0.8s 显示兜底（原来只在目标 > 0 时挂 0.5s），避免回调丢失导致表面永远 `opacity 0`。
3. 视频逐帧复核（34.6s / 69 帧，抽 25 帧）：确认菜单位移；另见「页码不变但正文整块换页」一帧，归因于无有效锚点时 `restoreAnchor` 算错位置，1.0.52 的闸门一并覆盖。

交付：IPA 1.0.52 `2D377688…`，CI 双绿（artifact 12611218845）。

---

## 8. 根因总表

| # | 症状 | 根因（观测/推断） | 修法 | 版本 |
|---|---|---|---|---|
| 1 | 跳章/滑动空白 | TextKit 清空后重排（观测） | WebView DOM 补丁 | 1.0.48 |
| 2 | 标题与正文同款 | 扁平 `[String]` 无标题身份（观测） | 结构化 sections + 独立 CSS | 1.0.48 |
| 3 | 点击过敏/跳页 | 位移/时长阈值 + 双来源判定（观测+推断） | JS 五道闸 + 0.28s 冷却 | 1.0.48/1.0.50 |
| 4 | 一章一加载 | 预取半径小 + 触发点贴底（观测） | 半径 2、触发 1.6 屏 | 1.0.49/1.0.51 |
| 5 | 首开不在顶部 | WKWebView 复用带旧滚动位置（推断，已由 resetToken 覆盖） | resetToken 回顶 | 1.0.49 |
| 6 | EPUB 变 TXT / 无封面 / 无目录 | 身份写死 local://text、派生 id 不匹配、HTTP-only 图片加载器（观测） | isLocalEPUB、bookURL 回退、file URL 分支 | 1.0.49 |
| 7 | 搜索慢（源少更慢） | zlib 60s 阻塞 + 批屏障（观测） | 关键路径剔除 + 滑动窗口并发 | 1.0.49 |
| 8 | 分类无反馈 | 静默 return + 取消不复位标志（观测） | loadGeneration + errorMessage | 1.0.49 |
| 9 | 换主题要翻页 | 页面快照 + 缓存键缺主题（观测） | cache key 加主题/外观 | 1.0.50 |
| 10 | 正文不满页 | 排版与渲染底距不一致（观测） | 统一 `pagedBottomPadding` | 1.0.50/1.0.51 |
| 11 | 菜单挤正文 | 顶边距随菜单变化（观测，视频证实） | 常量顶边距 | 1.0.52 |
| 12 | 卡死/空白（未定） | NaN 滚动位置 / 脚本错误 / DOM 过大（推断） | 自愈 + NaN 闸门 + 半径收缩 | 1.0.51/1.0.52 |

---

## 9. 代码地图（阅读链路）

```text
Features/Reader/
  ReaderView.swift              24 万字节的宿主视图：chrome、TOC、设置、分页三兄弟、窗口策略调用
  WebScrollReaderView.swift     滚动面（WKWebView 封装 + 消息桥 + 插图 scheme handler）
  WebReaderDocument.swift       文档壳 CSS/JS + 纯逻辑（索引/载荷/颜色/转义）
  NativeReaderTextView.swift    TextKit 旧滚动面（1.0.48 起不再被 ReaderView 使用，保留作回滚）
  ReaderChapterWindow.swift     窗口策略：切片、扁平索引、跨章位置解析、重试退避
  ReaderPageLayoutEngine.swift  分页度量（顶部/底部内边距、缩进、行高）
  PageCurlReaderView.swift      UIPageViewController 仿真翻页容器
  ReaderPagedNavigationPolicy.swift / ReaderPageStepPolicy / ReaderScrollAnchorPolicy …
Core/Storage/ChapterContentCacheStore.swift   章节磁盘缓存
Features/Bookshelf/BookshelfReaderGatewayView.swift  本地书 / 书源书统一入口
Core/Import/LocalEPUBBookParser.swift         EPUB 解析 + cover/OPF/NCX
Shared/DesignSystem/RemoteImageLoader.swift   远程 + 本地封面/插图
```

---

## 10. 构建与交付 SOP（本机实测）

1. **版本三处同步**：`project.yml`（MARKETING_VERSION / CURRENT_PROJECT_VERSION）、`Shared/AppVersion.swift`（minor/build）、`SourceReadSwiftTests/SearchURLResolverTests.swift`（断言）。
2. **`project.yml` 必须 LF**：`python -c "print(open('project.yml','rb').read().count(b'\r\n'))"` → 0。
3. **推送**：
   - 正常：`git push --force-with-lease origin HEAD:refs/heads/codex/reader-feedback-fixes`（github.com:443 常被 RST）；
   - 备用：GitHub REST API 造 blob→tree→commit→PATCH ref（本会话 1.0.50/51/52 都是这条路），见 `_push_api.ps1`。
4. **CI**：push 到 `codex/**` 同时触发 `iOS` 与 `Unsigned IPA`；iOS 必须 Build **和 Test** 都绿。
5. **取 IPA**：`GET /actions/runs/{id}/artifacts` → 下载 zip → 解压 → 桌面命名为 `SourceReadSwift-<版本>-unsigned.ipa`。
6. **验收**：解包读 `Info.plist`（版本/构建号）+ 主二进制搜特征串（`web-scroll-reader`、`chapter-title`、`resetScroll`、`looksLikeEPUB`、`isLocalEPUB`）。

---

## 11. 已知未解 & 下一步

| 项 | 状态 | 下一步 |
|---|---|---|
| 快速滑动卡死 | 已加自愈与闸门，根因未证实 | 真机诊断页数据；A/B 关闭 `readerimg://` 插图方案；必要时采集 WebKit 崩溃/看门狗日志 |
| 120Hz 实际帧率 | 只设了 `CADisplayLink` 的 range | 真机读设置→诊断的平均帧率；若 WKWebView 被钉 60，考虑滚动面换回原生或限制 DOM 尺寸 |
| P3 底部拉条越界 | 未修 | 需要用户指出面板（阅读设置/目录/书源编辑） |
| 三套渲染并存 | 结构债 | 建议下一轮只做「滚动面收成一套（WebView）、下线 TextKit 面」，再逐段重写 `ReaderView` 滚动分支 |

---

## 12. 附：可复现验证命令

```bash
# 单元测试（本地无 macOS，靠 CI）
cd D:/Gemini反重力/SourceReadSwift2 && git push ... # 触发 .github/workflows/ios.yml

# 文档壳 DOM 行为（本机 Chrome）
python _web_scroll_test_gen.py
chrome --headless=new --disable-gpu --window-size=390,844 \
       --virtual-time-budget=12000 --dump-dom file:///.../_web_scroll_test.html > dump.html
python _web_scroll_test_read.py

# 扁平索引与窗口布局一致性
python _flat_policy_check.py

# 包内验收
python _verify_ipa2.py "C:/Users/Edc21/Desktop/SourceReadSwift-1.0.52-unsigned.ipa"
```

---

_文档生成时间：2026-10-26 03:5x（Asia/Shanghai）。事实来源：旧会话 turnOutline、本会话每版 CI run/artifact、真机截图与两段录屏的分帧分析。标注「推断」的条目尚未有真机证据。_
