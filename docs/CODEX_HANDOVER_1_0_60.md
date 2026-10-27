# SourceReadSwift v1.0.60 交接文档 — 阅读界面重构

**版本：** 1.0.60 (Build 61)
**分支：** `codex/reader-feedback-fixes`
**基线 Commit：** `66e83ea4d06e7d0d7ecf7f114d10d5a0f6b4e110`
**日期：** 2026-10-27
**上游交接：** `docs/CODEX_HANDOVER_1_0_59.md`（v1.0.59 全量复盘）
**书源评估：** `docs/书源解析能力评估-1.0.60.md`

> 本轮只改阅读界面与三种阅读模式，不动书源主链。目标是把「顶部空白太多、翻页模式有 BUG、状态栏位置不佳」收敛到开元阅读 3.0.1 / 栖阅 2026.6.08 截图像素量测的同一套几何。

---

## 一、本轮范围与非目标

**做：**

1. 阅读页几何单一来源，消灭三处安全区重复扣减；
2. 每页内置页眉/页脚，分页模式不再用全局浮层覆盖；
3. 仿真 / 覆盖 / 滑动三种模式的点击与容器 inset 修复；
4. 跨章续读提前缓冲（读到本章倒数第 3 页即预取下一章）；
5. 新增两项排版设置 + 一键对齐竞品排版预设；
6. 默认排版参数对齐竞品量测值；
7. 8 个几何单测 + 版本断言同步。

**不做（留给下一阶段）：**

- WebView 书源 `webJs` 注入、`sourceRegex` 子资源嗅探、`overrideUrlRegex`（见评估文档 §7 S1）；
- Java 兼容类补齐（S2）；
- XPath 不可翻译诊断（S3）；
- 阅读界面之外的功能模块。

---

## 二、竞品排版基准（390×844pt @3x 截图像素量测）

素材：

- `C:\Users\Edc21\Desktop\开元阅读-3.0.1-逆向解包`（Flutter，`com.niki.xxread`）
- `C:\Users\Edc21\Desktop\栖阅2026.6.08-逆向解包`（SwiftUI，`com.arekert.qireader`）
- 量测记录：两家 `02_文档合集\阅读界面布局定位_开元_栖阅.md`、`reader_layout_spec.json`

| 元素 | 竞品基准 | v1.0.60 实现 | 落点 |
|---|---|---|---|
| 页眉章节名 | 12pt，墨迹 y 50–61 | 12pt，`safeTop + 2` 起，15pt 行高 | `ReaderPageChrome` |
| 正文首行顶 | 84.3（safeTop 50 + 34.3） | `safeTop + 2 + 15 + 17 = safeTop + 34` | `ReaderPageGeometry.bodyTop` |
| 左右边距 | 20.7 / 21.0 | 默认 `pagePadding = 21` | `ReaderTypographyDefaults` |
| 首行缩进 | 40.3（约 2 字） | 默认 `paragraphIndent = 40` | 同上 |
| 字号 / 行距 | 20.7pt / 42.7pt | 20pt / `lineSpacing = 12` | 同上 |
| 段距 | 0 | 默认 0 | 同上 |
| 正文底 | 819.0 | `footerTop - 4`（`footerTop = H - max(safeBottom/2, 12) - 14`） | `ReaderPageGeometry` |
| 页码 | 右下 `3/35`，11pt，离底 12.3 | 11pt，右下，`footerBottomInset = 12` | `ReaderPageChrome` |

---

## 三、几何架构：单一来源

### 3.1 旧问题

旧实现有三处各自扣安全区：

1. `pageSurface` 的 `.padding(.top, safeTop + 4)`；
2. 分页引擎 `viewport.height - topPadding - bottomPadding`；
3. `UIHostingController` 默认 safe area 内缩。

三处各扣一次的结果就是「顶部大片空白 + 页尾截断」，且不同机型/不同模式偏移量不一致。

### 3.2 新结构

新增 `SourceReadSwift/Features/Reader/ReaderPageGeometry.swift`（203 行）：

```text
bodyTop        = safeTop + 2 + 15 + 17        // header 模式；inline = safeTop + 8；hidden = safeTop + 12
footerTop      = height - max(safeBottom*0.5, 12) - 14
bodyBottom     = footerTop - 4
contentHeight  = max(bodyBottom - bodyTop, 120)
contentWidth   = max(width - margin*2, 80)
```

- `ReaderPageGeometry` 是唯一几何来源：分页引擎、SwiftUI 页面、页眉、页脚、页码全部只读它；
- `ReaderPageContainerMetrics` 把 `UIHostingController` 的真实 bounds、全局原点、根视口高度、根安全区回传；
- `resolvedSafeTop`：容器全局原点 `globalMinY > 1` 时归零，防止已内缩容器再扣一次；
- 0.5pt 吸附：`adoptPageContainerMetrics` 只在尺寸变化超过 0.5pt 时更新，避免布局抖动触发无限重排。

### 3.3 容器回调链

`PageCurlReaderView` 新增 `onPageContainerLayout: ((CGSize, CGFloat) -> Void)?`：

- `PageHostingController.viewDidLoad`：`edgesForExtendedLayout = .all`、`extendedLayoutIncludesOpaqueBars = true`、`viewRespectsSystemMinimumLayoutMargins = false`、`insetsLayoutMarginsFromSafeArea = false`、`additionalSafeAreaInsets = .zero`、`layoutMargins = .zero`；
- `viewDidLayoutSubviews`：0.5pt 去抖 → `DispatchQueue.main.async` 回传 `(size, globalMinY)`；
- `ReaderView` 侧 `pageContainerLayoutHandler` 接收后驱动 `pagedLayoutViewportSize` 与 `pagedPageGeometry`。

---

## 四、分页模式修复

| 问题 | 根因 | 修复 |
|---|---|---|
| 仿真翻页点一下连翻两页 | `UIPageViewController` 自带 tap 与 SwiftUI 九宫格 tap 各翻一次 | `suppressInternalTapGestures` 只关闭 pageCurl 的 `UITapGestureRecognizer`，保留拖动卷页 |
| 滑动模式内容下移/裁切 | 内部 `UIScrollView.contentInsetAdjustmentBehavior` 自动加安全区 | `normalizeInternalScrollViews` 递归设 `.never`、inset 归零 |
| 分页高度与容器不一致 | `UIHostingController` 二次安全区内缩 | 容器配置归零 + metrics 回传（§3.3） |
| 章节标题占正文高度 | 页眉模式仍给大标题预留 40–50pt | `appendPages` 在 header/hidden 模式 `currentIncludesTitle = false`、`currentHeight = 0` |
| 顶部空白过多 | 三处安全区重复扣减 | §3 单一几何来源 |
| 页码格式不直观 | 只显示页码 | `"\(ordinal+1)/\(total)"`（当前页/本章总页） |

每页内置 chrome：

- `pagedPageHeader`：12pt 章节名，`headerRect` 定位；
- `pagedPageFooter`：11pt 页码右下 + 可选时间/电量，跟随 `statusPosition`（仅页脚 / 仅页眉 / 页眉+页脚）；
- 全局 `readerHeader` / `readerFooter` 只在 scroll 模式渲染，分页模式不再叠加浮层。

---

## 五、滚动模式修复

- 全局页眉改为 `frame(height: scrollHeaderBandHeight /* 22 */)` 之后再加 `.padding(.top, readerTopSafeInset + headerTopGap)`，修正顺序后文字不再被压扁；
- `scrollContentTopInset = safeTop + 2 + 22 + 6`，正文与 22pt 页眉带不重叠；
- `readerFooter` 底部 padding = `max(readerFooterSafeInset * 0.35, ReaderPageChrome.footerBottomInset)`（= 12），页码不再顶到屏幕中间；
- 根视图 `.ignoresSafeArea()` + `pageBackground.ignoresSafeArea()`，背景铺满物理屏。

---

## 六、跨章续读

- 新增 `ensurePagedContinuationBuffer(pageIndex:)`：本章倒数第 3 页触发 `loadWindowChapter(next)`；接近已加载尾部时 `prefetchWindow`；
- 挂在 `onChange(pagedPageIndex)` 与 `updatePagedVisibleParagraph`：翻页、拖动、程序跳页都会触发；
- 跨章沿用 v1.0.28–v1.0.30 的双向窗口、真实占位页、失败重试与 LRU 缓存；
- 目标行为：向前/向后连续滑动可自动续章，而不是滑完本章停在末页。

---

## 七、设置项与默认值

新增 `@AppStorage`：

| Key | 取值 | 默认 |
|---|---|---|
| `reader.chapterHeadingStyle` | 页眉小标题 / 正文大标题 / 隐藏标题 | 页眉小标题 |
| `reader.contentExtendsIntoChrome` | 内容延伸至页眉页脚区域 | 关 |

新增「一键对齐成熟阅读器排版」按钮（`applyCompetitiveReaderPreset()`）：
字号 20 / 行距 12 / 边距 21 / 缩进 40 / 段距 0 / 页眉模式 / 页脚状态栏。

默认值变更（`ReaderTypographyDefaults`）：

| 参数 | 旧 | 新 |
|---|---|---|
| 字号 | 19 | 20 |
| 行距 | 8 | 12 |
| 段距 | 6 | 0 |
| 缩进 | 38 | 40 |
| 标题间距 | 20 | 8 |
| 页边距 | 20 | 21 |

---

## 八、构建与验证

- 版本三处同步：`project.yml`（`MARKETING_VERSION 1.0.60` / `CURRENT_PROJECT_VERSION 61`）、`SourceReadSwift/App/Info.plist`、`SourceReadSwift/Shared/AppVersion.swift`（minor 60 / build 61）。
- 单测：
  - 新增 `SourceReadSwiftTests/ReaderPageGeometryTests.swift` 8 个用例（竞品基准 84/813/809/725、灵动岛 93/821/817/724、inline 58、hidden 62、延伸 58→834/776、窄屏钳制、内缩容器 34/762/758/724、全屏 59、非法回退）；
  - `ReaderSettingsModelsTests` 默认值与三档标题文案断言同步；
  - `SearchURLResolverTests.testAppVersionSemantics` 版本断言 60/61。
- CI：GitHub Actions run `40486194273`（commit `66e83ea4`）：Build 成功；Test `1057` 个用例、`0` 失败、`** TEST SUCCEEDED **`（2026-10-27T10:19:55Z）。
- IPA：GitHub Actions run `40486194260` 成功；产物 `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.60-unsigned.ipa`，`12,024,153` 字节，SHA256 `F4960385D9A3386DAD1151CBC8FB895BFBE5861CCCA232352C3791883B073289`；包内 `CFBundleShortVersionString=1.0.60`、`CFBundleVersion=61`、`MinimumOSVersion=16.0`、`CFBundleIdentifier=com.edc21.SourceReadSwift`。

历史参考：`ec899cc` 的 iOS workflow 已 build 成功，测试 1057 个用例、3 个失败，全部是 `SearchURLResolverTests` 版本断言仍写 59/60；`66e83ea` 已修正该断言并重跑。

---

## 九、真机验收清单（未通过前不得写成已通过）

| # | 场景 | 期望 |
|---|---|---|
| 1 | iPhone 14 Pro Max / 15 Pro（灵动岛 393×852） | 页眉不压刘海；页码在 home indicator 上方 |
| 2 | iPhone SE（safeTop 20） | 正文顶 = 54 |
| 3 | 仿真翻页 | 点按只翻一页；拖动可卷页 |
| 4 | 覆盖翻页 | 跟手，无跳页 |
| 5 | 滑动（横向分页） | 内容不下移、不裁切 |
| 6 | 四种模式 | 上/下章可连续滑动续读，不在章末停住 |
| 7 | 滚动模式 | 页眉 22pt 与正文 30pt 不重叠 |
| 8 | 横屏 / 分屏 | 重分页后几何正确 |
| 9 | 深色 / 自定义壁纸 | 页眉页脚对比度可读 |

---

## 十、已知风险与回滚

- 本机无 Xcode/swiftc，全部编译验证依赖 GitHub Actions；本地不能出包。
- `ReaderView.swift` 约 28 万字节，本轮 +458 行，属于大文件高风险改动；回滚点为 `a35217e^`（v1.0.59 基线 `1ac5791`）。
- 分页几何在真机上仍可能出现 1–2pt 级别的视觉差异，需要按 §九 逐项验收后微调常量，不改结构。
- 若 IPA 出现启动即崩，优先检查 `ReaderPageGeometry.swift` 的 `PreferenceKey` 默认值与 `PageCurlReaderView` 回调生命周期。

---

## 十一、下一阶段工程（书源解析）

完整评估见 `docs/书源解析能力评估-1.0.60.md`。摘要：

| 编号 | 缺口 | 落点 | 优先级 |
|---|---|---|---|
| S1 | `webJs` 只当启用信号，未 `loadUrl("javascript:...")`；`sourceRegex` 未做子资源嗅探；`overrideUrlRegex` 未实现 | `WebViewFallback.swift` / `SourceEngine.swift:801` | P1 |
| S2 | Java 兼容类缺失：`BigInteger`、`ByteBuffer`、`TextUtils`、`TimeUnit`、`SecretKeyFactory`/`DESKeySpec`、`BufferedInputStream`/`InputStreamReader`、`StringBuffer`、`BitmapFactory` | `JSCoreRuntime` | P2 |
| S3 | XPath 不可翻译时静默失败 | `HtmlRuleExtractor` | P2 |
| S4 | 第三方书源回归集不足 | `SourceReadSwiftTests` | P2 |
| S5 | 诊断面板未覆盖 WebView 链路 | 阅读器诊断 | P3 |

重要更正：`sourceRegex` 不是正文清洗正则，而是 Legado `BackstageWebView.SniffingWebClient.onLoadResource` 的 WebView 子资源嗅探正则；正确落点是 `WebViewFallback.swift`，不是 `ContentParser` / `HtmlRuleExtractor`。

主链现状（已具备）：搜索 / 详情 / 目录 / 正文 / 发现；CSS、Jsoup、XPath 子集、JSONPath、`##`、`@put@get`、`<js>`、`jsLib`、Packages、Cookie、GBK、分页、诊断。

---

## 十二、文件清单

新增：

- `SourceReadSwift/Features/Reader/ReaderPageGeometry.swift`（203 行，LF）
- `SourceReadSwiftTests/ReaderPageGeometryTests.swift`（128 行，LF）
- `docs/书源解析能力评估-1.0.60.md`（234 行）
- `docs/CODEX_HANDOVER_1_0_60.md`（本文档）

修改：

- `SourceReadSwift/Features/Reader/ReaderView.swift`（+458/−?，CRLF）
- `SourceReadSwift/Features/Reader/PageCurlReaderView.swift`（+77，CRLF）
- `SourceReadSwift/Features/Reader/ReaderSettingsModels.swift`（默认值，CRLF）
- `SourceReadSwift/App/Info.plist`、`project.yml`、`SourceReadSwift/Shared/AppVersion.swift`（版本号）
- `SourceReadSwiftTests/ReaderSettingsModelsTests.swift`、`SourceReadSwiftTests/SearchURLResolverTests.swift`
- `docs/SOURCE-CAPABILITY-MATRIX.md`、`docs/书源字段兼容矩阵.md`、`docs/legado-js-compatibility-matrix.md`
- `PROJECT_FULL.md`（§十三）、`PROJECT_HANDOVER.md`（顶部指针）

---

## 十三、复现命令

```powershell
cd D:\Gemini反重力\SourceReadSwift2
git fetch origin
git checkout codex/reader-feedback-fixes
git log --oneline -3

# 版本核对
Select-String -Path project.yml -Pattern 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
Select-String -Path SourceReadSwift\App\Info.plist -Pattern 'CFBundleShortVersionString|CFBundleVersion' -Context 0,1

# CI（需要 GitHub token 的辅助脚本，位于 E:\codex-temp\sourceread\scripts）
python -X utf8 E:\codex-temp\sourceread\scripts\ci_jobs.py <run_id>
```

构建入口：`.github/workflows/ios.yml`（build + test）与 `.github/workflows/unsigned-ipa.yml`（unsigned IPA）。

---

## 十四、交接结论

v1.0.60 把阅读页几何从「三处各自计算」收敛为「一份 `ReaderPageGeometry` + 容器 metrics 回传」，三种阅读模式的 tap / inset / 标题高度问题都在代码层修掉，并补了 8 个几何单测防回归。真机视觉验收与书源 S1–S5 是下一阶段的两条主线。
