# SourceReadSwift v1.0.62 交接文档 — 滑动模式页脚遮挡修复

**版本：** 1.0.62 (Build 63)
**分支：** `codex/reader-feedback-fixes`
**代码 Commit：** `ec2ffb3391d5a713d6fc6eaba12c3eedbcd807e9`
**日期：** 2026-10-27
**上游交接：** `docs/CODEX_HANDOVER_1_0_61.md`（安全区与 chrome 修复）

---

## 一、问题现象

真机截图（390×844pt，滑动模式）：

1. 底部状态栏（时间 / 页码 / 电量）以半透明文字直接叠在正文最后一行上；
2. 正文与页脚之间没有独立色带，阅读到段尾或章末时文字被遮住；
3. 分页 / 仿真翻页不出现该问题，只有滑动模式出现。

## 二、根因

`readerFooter` 是覆盖在阅读内容之上的透明 overlay：

```swift
.overlay { readerFooter }   // allowsHitTesting(false)
```

它没有背景色，只绘制 20pt 高的状态文字行和底部安全距。滑动模式的 `WKWebView` 同样铺满全屏：

```swift
ReaderWebView(...)
    .ignoresSafeArea(.container, edges: .bottom)
```

文档内部的 `bottomInset` 只给正文尾部增加滚动留白，不能裁剪视口；正文仍会滚到页脚所在区域，页脚文字就压在小说的行上。**底部状态带没有从 WebView 的视口高度里扣除**，是这次遮挡的直接原因。

## 三、修复（保留状态栏，不删除）

### 3.1 新增状态带常量

`SourceReadSwift/Features/Reader/ReaderPageGeometry.swift`：

```swift
static let scrollFooterBandHeight: CGFloat = 40

static func scrollFooterReservedHeight(statusPosition: String) -> CGFloat {
    (statusPosition == "bottom" || statusPosition == "both") ? scrollFooterBandHeight : 0
}
```

40pt = 状态文字行高 20pt + 底部留白 12pt + 与正文的视觉间隙 8pt。

### 3.2 视口底部让位

`SourceReadSwift/Features/Reader/ReaderView.swift`：

```swift
private var scrollFooterReservedHeight: CGFloat {
    ReaderPageChrome.scrollFooterReservedHeight(statusPosition: statusPosition)
}
```

```swift
ReaderWebView(...)
    .ignoresSafeArea(.container, edges: .bottom)
    .padding(.bottom, scrollFooterReservedHeight)
```

顺序必须先是 `ignoresSafeArea` 再 `padding`：先铺满物理屏，再从底部让出状态带。这样 WebView 的可滚动视口止于状态带上方；页脚仍覆盖全屏，但只落在 40pt 空带上。padding 区显示 `readerThemeBackground`，与正文背景连续。

### 3.3 与状态栏开关联动

- `statusPosition == bottom / both`：预留 40pt；
- `statusPosition == top / none`：不预留。

用户如果不想要底部状态栏，在阅读设置把「状态栏位置」改为 top / none 即可，不需要改代码，也不会留下空白。

### 3.4 为什么不删除

删除页脚会同时失去时间 / 页码 / 电量三项信息，并与开元、栖阅的底部信息带不一致。正确处理是给状态带独立空间，而不是删功能。

## 四、测试

`SourceReadSwiftTests/ReaderPageGeometryTests.swift` 新增：

```swift
func testScrollFooterBandOnlyReservesWhenFooterAtBottom() {
    XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "bottom"), 40, accuracy: 0.01)
    XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "both"), 40, accuracy: 0.01)
    XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "top"), 0, accuracy: 0.01)
    XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "none"), 0, accuracy: 0.01)
}
```

CI（GitHub Actions run `40496375952`，commit `ec2ffb3`）：

- Build 成功；
- Test `1068` 个用例、`0` 失败、`** TEST SUCCEEDED **`（2026-10-27T11:35:20Z）；
- 9 个几何用例全部通过。

## 五、构建产物

- IPA：GitHub Actions run `40496375949` 成功；
- 产物：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.62-unsigned.ipa`；
- 大小：`12,026,902` 字节；
- SHA256：`7A33A9243D728B4D0440960FBC8467F5A8FC3A9EA32836E9A577E6BD8CCAC173`；
- 包内：`CFBundleShortVersionString=1.0.62`、`CFBundleVersion=63`、`MinimumOSVersion=16.0`、`CFBundleIdentifier=com.edc21.SourceReadSwift`。

## 六、真机验收（未通过前不得写成已通过）

1. 滑动模式滚到章末：最后一行完整可见，页脚文字在其下方 40pt 带内；
2. 页脚背景与阅读背景连续，不出现横向色带；
3. `statusPosition = top`：底部不额外留 40pt；
4. 横屏：底部不额外留 40pt；
5. 点击底部区域仍能翻页（页脚不拦截触摸）；
6. 深色背景 / 自定义壁纸下状态文字对比度正常。

## 七、回滚

- `git revert ec2ffb3`；
- 或删除 `ReaderView.swift` 的 `.padding(.bottom, scrollFooterReservedHeight)` 与对应计算属性，状态带回到透明叠加状态。

## 八、文件清单

修改：

- `SourceReadSwift/Features/Reader/ReaderPageGeometry.swift`
- `SourceReadSwift/Features/Reader/ReaderView.swift`
- `SourceReadSwiftTests/ReaderPageGeometryTests.swift`
- `project.yml`、`SourceReadSwift/App/Info.plist`、`SourceReadSwift/Shared/AppVersion.swift`
- `SourceReadSwiftTests/SearchURLResolverTests.swift`
