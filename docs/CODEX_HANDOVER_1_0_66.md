# CODEX 交接 — v1.0.66 (Build 67)

> **分支**：`codex/reader-feedback-fixes`
> **提交**：`01ec90bb7debc6e18a3576d2910fd63fde80f986`（`fix(reader): anchor page cursor to page identity and reuse page hosts`）
> **日期**：2026-10-28
> **上一版**：v1.0.65 (Build 66) / `ffb9da4`
> **本轮输入**：两段真机录像（`c81f0199….mp4` 滑动卡顿、`5338b22f….mp4` 翻页跳回前面章节）+ 三条文字反馈

---

## 一、本轮要解决的问题

| # | 反馈 | 现象 | 判定 |
|---|---|---|---|
| 1 | 左右滑动会卡顿一下 | 每章第一次起手明显掉一帧，跨章更明显 | 起手帧同时做三件事：新建 SwiftUI 页面树、重建整窗页面模型、重建整段 `NSAttributedString` |
| 2 | 翻页一直跳回前面 | 第 5 章翻一页落到第 2 章 | 页游标用「窗口数组下标」恢复；预取插章后下标整体位移 |
| 3 | 其他翻页模式丢帧，主页像假 120Hz | 三模式帧率不稳；书架/发现滚动不跟手 | 全书封面按原图解码上屏（单张 1000px+），主线程做缩略图工作 |
| 4 | 「关于纸间」文案太泛 | 核心特色 12 条标签 | 已重写为一段自述，删除全部特色标签 |
| 5 | iOS 16 显示问题 | 待真机 | 本轮不动，见 §六 |

---

## 二、根因分析（跳页）

### 2.1 数据结构

阅读器不是「一章一页数组」，而是**五章窗口合并成一条页面数组**：

```text
pagedBlocks: [ReaderPageBlock]
  ├─ chapter 4: pageOrdinal 0,1,2
  ├─ chapter 5: pageOrdinal 0,1,2,3   ← 用户在这里
  └─ chapter 6: pageOrdinal 0,1
```

`ReaderPageBlock.id` 是**数组下标**，每次窗口新增/裁剪章节都会重排。

### 2.2 旧逻辑（缺陷）

```swift
// 旧 restoredPageIndex
if let ordinal = anchor.pageOrdinal, let exact = blocks.firstIndex(...) { return exact }
if let exact = pageIndex(forChapter:paragraph:) { return exact }   // ← first >= paragraph
return min(max(pagedPageIndex, 0), blocks.count - 1)               // ← 下标直落
```

两个致命点：

1. `pageIndex(forChapter:paragraph:)` 用 **`first >= paragraph`** 取页，遇到「段落被重新分页」会落到比锚点更靠后的页；找不到时还会 `blocks.firstIndex { chapter >= anchor.chapter }` 跨章漂移。
2. 兜底直接返回 `pagedPageIndex`。窗口前插两章后，同一个下标指向的章节整体前移——第 5 章的下标变成了第 2 章。

覆盖模式（`.cover`）另有一条独立路径：手势结束后 `Task.sleep(320ms)` 再写 `pagedPageIndex = target`。这 320 ms 里预取回包会重排数组，落笔时 `target` 已经是别的页。

### 2.3 新逻辑

新增 `ReaderPageSelection.swift`：

```swift
struct ReaderPageIdentity {          // 稳定身份：章号 + 章内页序 + 首段号
    let chapterIndex: Int
    let pageOrdinal: Int
    let firstParagraphIndex: Int
    let isPlaceholder: Bool
    var key: String { "\(isPlaceholder ? "p" : "b")-\(chapterIndex)-\(pageOrdinal)-\(firstParagraphIndex)" }
}

enum ReaderPageRestoration {
    static func index(anchor:in:fallbackIndex:) -> Int
    // 1. 精确匹配（同章 + 同 ordinal + 同首段）
    // 2. pageContaining：同章内 first <= paragraph 的最后一页
    // 3. 章节不在窗口：只向前找，绝不回退到更早章节
    // 4. 最后才用 clamp 后的 fallback
}
```

硬规则：**锚点章节存在时，绝不返回更早章节的页**。这一条直接把「第 5 章跳第 2 章」变成不可能事件。

---

## 三、代码改动

### 3.1 新增

| 文件 | 作用 |
|---|---|
| `SourceReadSwift/Features/Reader/ReaderPageSelection.swift` | `ReaderPageIdentity` + `ReaderPageRestoration`（纯函数，可单测） |
| `SourceReadSwiftTests/ReaderPageSelectionTests.swift` | 9 条回归：插章后仍在第 5 章、重分页取「最后起始段 ≤ 锚点」、锚点章缺失只向前、占位页边界、空模型、clamp |

### 3.2 `ReaderView.swift`

- `@State interactionGate = ReaderInteractionGate()`：手势状态改成引用盒。原先写在 `@State Bool` 上，起手第一帧就会让整个 ReaderView body 失效——这正是「滑动卡顿一下」。
- `handlePageInteraction(_:)`：手势开始挂起重建，结束再发。
- `scheduleWindowRebuild()` / `schedulePagedBlocksCacheRebuild()`：都加交互闸门；debounce 30 ms → `ReaderPerformancePolicy.pageLayoutDebounceNanoseconds`（120 ms）。
- `currentPageAnchor(useCachedPageAnchor:)`：优先 `pageIdentityTracker.key` 反查，其次 `pagedBlocksCache[pagedPageIndex]`，两者都要过 `blockIsInLiveWindow`；兜底固定在当前窗口章 + 段 0，**不再用 `resolvedReadingPosition(forFlatIndex:)`**。
- `pageAnchor(for:)`、`blockIsInLiveWindow(_:)` 新增。
- `pageAttributedText(for:)` 走 `ReaderPageTextCache`（16 条，按页面身份 + 朗读高亮 + 排版签名）；原名逻辑拆为 `buildPageAttributedText(for:)`。
- `readerPageRevisionKey`：排版/主题/壁纸/字体/配色，**不含 `windowSections`**，供页面级缓存判断是否真的需要重画。
- 覆盖模式：`.id()` 由数组下标改为页面身份；`finishCoverGesture` 记录 `targetAnchor`，320 ms 后用 `ReaderPageRestoration` 反解下标；新增 `reportCoverVisibleIdentity(_:)` 与 `.onAppear` 上报。

### 3.3 `PageCurlReaderView.swift`

- 新增 `pageRevision: ((Item) -> String)?`、`pageKey: (Item) -> String`。
- `hostingControllers: [String: PageHostingController]` LRU（8 条）+ `hostingOrder`：按稳定 key 复用，不再每次手势新建 SwiftUI 树。
- `prewarm(around:)`：下一帧预建 `+1 / -1 / +2`。
- `currentIndex(for:)`：用 `pageKey` 反查当前下标，修复窗口插入后 `host.pageIndex` 失效。
- `sync`：`displayedIndex` 改为 `currentIndex(for:)`；`contentRevisionChanged` 改为**可见页自身**的 revision 变化；目标控制器与当前控制器相同时**不再调用 `setViewControllers`**——跨章边界那次「无意义重设」是卡顿和半页重绘的来源。
- `willTransitionTo` / `didFinishAnimating` 向 ReaderView 上报 `onInteractionChanged(true/false)`。
- `PageHostingController` 增加 `pageKey`、`contentRevision`。

### 3.4 `ReaderPageTextView.swift`

- `updateUIView` 先 `attributedText.isEqual(to:)`，相等直接返回，避免每次布局重建 TextKit。

### 3.5 图片链路（主页 / 发现 / 搜索）

- `RemoteImageLoader`：`ImageIO` 降采样，`thumbnailCache`（240 条 / 32 MB），`cachedImage(for:maxPixelSize:)`、`image(for:headers:maxPixelSize:)`，`in-flight` key 带尺寸；解码/降采样全部在 `DispatchQueue.global(qos: .utility)`。
- `CachedRemoteImage`：新增 `maxPixelSize`。
- `BookshelfView`：`coverMaxPixelSize = max(width, height) * displayScale`。
- `DiscoverView`：聚合封面 260 / 网格 420。
- `SearchBookRow`：260。

### 3.6 关于页

`SettingsView` 删除 `Section("核心特色")`（12 条）与 4 个 `aboutTag`，替换为一段自述文案（字里行间 → 一只安静的书匣 → 支持 Legado JSON / TXT / EPUB → 欢迎反馈）。保留「合规与条款」「致谢与声明」。

---

## 四、验证

| 项 | 命令 / 运行号 | 结果 |
|---|---|---|
| 静态换行 | `git -c core.whitespace=cr-at-eol diff --check` | 0 告警（CRLF 文件保持 CRLF，LF 文件保持 LF） |
| 单测 | iOS workflow `40568266811` | 见 §四.1 |
| 编译 | iOS workflow `40568266811` job `122415260079` | 见 §四.1 |
| IPA | Unsigned IPA `40568266615` | 见 §四.2 |

### 4.1 CI 结果

（本轮完成后回填：Build 步骤结论、Test 步骤 tests / failures 计数）

### 4.2 IPA

（回填文件名、字节数、SHA256）

---

## 五、复现与回归

```bash
# 单测（macOS）
xcodebuild test -project SourceReadSwift.xcodeproj -scheme SourceReadSwift \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:SourceReadSwiftTests/ReaderPageRestorationTests \
  -only-testing:SourceReadSwiftTests/ReaderPageIdentityTests
```

真机回归脚本（人工）：

1. 打开任意 5 章以上的书，翻到第 5 章中段；
2. 向前连翻 3 页，观察是否还停在「第伍章」；
3. 在第 5 章 ↔ 第 6 章边界来回翻 10 次，观察是否出现半页重绘 / 折痕；
4. 三种模式各翻 20 页，用 Xcode Instrument（Core Animation）看是否有 `dropped frames`；
5. 书架 200 本封面上下滚动，观察首屏解码是否还阻塞主线程。

---

## 六、iOS 16 待验收

本轮没有 iOS 16 真机，**不作结论**。已知待测项（沿用 `docs/IOS16-COMPAT-AUDIT-1.0.65.md`）：

- 书架搜索框与导航栏重叠；
- 详情页 / 主页封面不显示；
- 发现页封面正常但详情页空白；
- 分页模式顶部留白与状态栏位置。

上述与 v1.0.65 的封面链路修复相关，需要 iOS 16 真机确认后再动代码。

---

## 七、下一轮待办

1. iOS 16 真机验证（最高优先级，决定是否要回到 `CoverURLResolver` / 安全区数据源）。
2. 书源登录：多数源「登录地址无效」或没有登录入口，需要按 `SourceLoginURLResolver` 的实际回包做一轮真实书源抽样。
3. 正文截断（末尾省略号）复现：需要具体书源 + 章节样本。
4. 阅读界面 UI 对齐：标题/正文样式在四模式下仍未完全统一。
5. 主页 ProMotion：封面降采样已做，下一步是滚动时的 `List` 行复用与 `AsyncBookCover` 的占位稳定性。
