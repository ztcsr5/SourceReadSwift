# SourceReadSwift v1.0.61 交接文档 — 安全区与阅读器 chrome 修复

**版本：** 1.0.61 (Build 62)
**分支：** `codex/reader-feedback-fixes`
**代码 Commit：** `e3560bc5021cd86c06401713e4c595e6fa846097`
**日期：** 2026-10-27
**上游交接：** `docs/CODEX_HANDOVER_1_0_60.md`（阅读界面几何重构）

---

## 一、问题现象

来自真机截图（390×844pt，safeTop 47）：

1. 阅读器顶部工具条压在系统状态栏下面，时间/信号/电池与章节标题重叠；
2. 正文第一章大标题顶到状态栏下方，正文顶部内边距只有约 30pt；
3. 底部控制坞（上一章 / 滑杆 / 下一章 / 目录 / 朗读 / 停止 / 自动 / 设置）贴到屏幕物理底边；
4. 打开设置面板时，面板底部越过 home indicator；
5. 顶部提示条 / 语音错误条同样压到状态栏。

## 二、根因

`ReaderView` 根视图 `.ignoresSafeArea()` 做全屏铺底，所有 chrome 自己负责让开安全区。但安全区来源是：

```swift
UIApplication.shared.connectedScenes
    .first { $0.activationState == .foregroundActive }?
    .windows.first(where: { $0.isKeyWindow })?.safeAreaInsets
```

在 LiveContainer / 侧载容器环境里，key window 可能是容器窗口，`safeAreaInsets` 上报为 `0`；`scene` 也可能取不到前台场景。结果：

- `readerTopSafeInset = 0` → 顶部工具条 `.padding(.top, 4)`；
- `scrollContentTopInset = 0 + 2 + 22 + 6 = 30` → 正文标题顶到状态栏；
- `readerFooterSafeInset = 0` → 底部控制坞只留 10pt；
- `settingsPanel` 读的是 `proxy.safeAreaInsets`，而根视图已经 `ignoresSafeArea`，同样恒为 0。

这不是几何公式错误，而是**安全区数据源在容器环境里失效**。

## 三、修复

### 3.1 新增 `ReaderSafeAreaResolver`

`SourceReadSwift/Features/Reader/ReaderSafeAreaResolver.swift`：

```text
top    = max(所有 UIWindow 的 safeAreaInsets.top, 状态栏高度, 0)
top    = top < 1 ? 按屏幕尺寸兜底 : top
bottom = max(所有 UIWindow 的 safeAreaInsets.bottom, 0)
bottom = bottom < 1 && top >= 44 ? 34 : bottom
```

兜底表（仅在窗口与状态栏都上报 0 时使用）：

| 屏幕（pt） | 机型 | safeTop |
|---|---|---|
| 430×932 | 14 Pro Max / 15 Pro Max / 16 Plus | 59 |
| 428×926 | 12/13 Pro Max、14 Plus | 47 |
| 414×896 | XR / 11 / XS Max | 44 |
| 393×852 | 14 Pro / 15 / 15 Pro / 16 | 59 |
| 390×844 | 12 / 13 / 14 | 47 |
| 375×812（宽 ≤375） | 12 mini / X / XS / 11 Pro | 50 |
| 375×667 / 414×736 | SE / 8 及以下 | 20 |
| 横屏（height < width） | 刘海在侧边 | 0 |

`ReaderView` 改为遍历所有 `UIWindowScene` 的所有窗口取最大值，并叠加 `statusBarManager.statusBarFrame.height`；不再依赖 `keyWindow` 或 `foregroundActive` 过滤。

### 3.2 chrome 修正清单

| 位置 | 旧 | 新 |
|---|---|---|
| 顶部工具条 | `.padding(.top, 4)` | `.padding(.top, readerTopSafeInset + 4)` |
| 底部控制坞 | `.padding(.bottom, 10)` | `.padding(.bottom, max(readerFooterSafeInset, 10) + 10)` |
| 设置面板 | `proxy.safeAreaInsets.bottom` | `readerFooterSafeInset`（面板高度与底部间距都用它） |
| 顶部提示条 | `.padding(.top, 12)` | `.padding(.top, readerTopSafeInset + 12)` |
| 语音错误条 | `12 / 58` | `readerTopSafeInset + (12 / 58)` |
| 目标达成 toast | `.padding(.top, 50)` | `.padding(.top, readerTopSafeInset + 12)` |

阅读页内部几何（`ReaderPageGeometry`）不变：一旦 `readerTopSafeInset` 恢复为 47/59，页眉与正文自动回到 `safeTop + 2` 与 `safeTop + 34`，与竞品量测一致。

## 四、验证

- 新增 `SourceReadSwiftTests/ReaderSafeAreaResolverTests.swift` 10 个用例：灵动岛 59、390×844 的 47、428×926 的 47、430×932 的 59、414×896 的 44、mini 50、SE 20、窗口值优先、状态栏兜底、横屏不臆造顶部安全区。
- 版本三处同步：1.0.61 / Build 62。
- CI：GitHub Actions run `40489685517`（commit `e3560bc5`）：Build 成功；Test `1067` 个用例、`0` 失败、`** TEST SUCCEEDED **`（2026-10-27T10:44:18Z）。
- IPA：GitHub Actions run `40489685657` 成功；产物 `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.61-unsigned.ipa`，`12,024,962` 字节，SHA256 `29C079B42733D20FD48C7B4823A547518ACF0379899413EF3679581A65727BF0`；包内 `CFBundleShortVersionString=1.0.61`、`CFBundleVersion=62`、`MinimumOSVersion=16.0`、`CFBundleIdentifier=com.edc21.SourceReadSwift`。

## 五、真机验收（未通过前不得写成已通过）

1. 390×844 机型：顶部工具条在状态栏下方，章节标题不再与 18:30 / 电池重叠；
2. 393×852 灵动岛：工具条不压灵动岛；
3. 底部控制坞完全位于 home indicator 上方；
4. 设置面板底部不被圆角/手势条裁切；
5. 横屏：顶部不额外留 47pt；
6. 页眉/页脚/页码位置与 1.0.60 几何一致。

## 六、风险与回滚

- 若某些容器连状态栏高度也上报 0，兜底表按屏幕尺寸生效；iPhone 12 mini（812）与 X/XS（812）无法仅凭尺寸区分，统一按 50 处理，最多 6pt 偏差。
- 回滚点：`e3560bc^`（1.0.60 文档头 `da7906b`）。

## 七、文件清单

新增：

- `SourceReadSwift/Features/Reader/ReaderSafeAreaResolver.swift`
- `SourceReadSwiftTests/ReaderSafeAreaResolverTests.swift`
- `docs/CODEX_HANDOVER_1_0_61.md`

修改：

- `SourceReadSwift/Features/Reader/ReaderView.swift`（安全区解析 + 6 处 chrome padding）
- `project.yml`、`SourceReadSwift/App/Info.plist`、`SourceReadSwift/Shared/AppVersion.swift`
- `SourceReadSwiftTests/SearchURLResolverTests.swift`
