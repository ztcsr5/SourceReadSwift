# iOS 16 兼容性审计 — SourceReadSwift 1.0.65

**审计日期：** 2026-10-28
**审计对象：** 1.0.65（Build 66），分页 TextKit 改造之后
**代码基线：** `ffb9da4`
**部署目标：** iOS 16.0（`project.yml` 的 `deploymentTarget.iOS` 与 `IPHONEOS_DEPLOYMENT_TARGET` 均为 16.0）

---

## 一、结论（先看这一段）

1. **API 层已确认可用。** CI 以 iOS 16.0 为部署目标编译通过。任何未加 `#available` 的 iOS 17+ API 都会在编译期报 availability 错误；本轮 Build 成功，说明代码没有裸用 iOS 17 API。
2. **静态扫描没有发现 iOS 17-only 的 SwiftUI 入口。** `ContentUnavailableView`、双参数 `onChange(of:initial:)`、`scrollTargetBehavior`、`scrollPosition`、`containerRelativeFrame`、`safeAreaPadding`、`symbolEffect`、`phaseAnimator`、`@Observable`、`SwiftData` 均 0 命中。
3. **唯一高于 16.0 的 API 是 `presentationBackground`（16.4）。** 它已有 `if #available(iOS 16.4, *)` 分支，16.0–16.3 直接跳过，不会崩溃。
4. **运行时显示不能由编译证明。** CI 的测试跑在 runner 自带的最新 iPhone 模拟器上，不是 iOS 16；当前开发机是 Windows，没有 iOS 16 模拟器或真机。因此不能声称“iOS 16 绝对没有显示 bug”，只能确认“没有 iOS 17 依赖，且已堵住可静态定位的 iOS 16 inset / 尺寸问题”。
5. **本轮补了 4 项 iOS 16 防御**（见第四节），目标是消除 UITextView 在 `UIPageViewController` 子控制器里首行下移、页面被内容高度撑开、以及文本容器初始尺寸为 0 的三类常见问题。

## 二、编译级证据

| 项 | 值 |
|---|---|
| 部署目标 | iOS 16.0 |
| Swift | 5.9 |
| Build destination | `generic/platform=iOS Simulator` |
| CI Build | 通过（run `40559137785`） |
| CI Test | 通过（1102 例 / 0 失败） |

编译级能证明的是：**代码里出现的每个系统 API，在 iOS 16 上都有实现**。它不能证明布局结果、动画快照和字体行高与 iOS 17+ 一致。

## 三、静态扫描结果

扫描范围：`SourceReadSwift/**/*.swift`。

| 检查项 | 命中 | 处理 |
|---|---|---|
| `#available(iOS 17` | 0 | 无 iOS 17 专属分支 |
| `ContentUnavailableView` | 0 | 未使用 |
| `onChange(of:initial:)` | 0 | 未使用 iOS 17 双参数版本 |
| `scrollTargetBehavior` / `scrollPosition` | 0 | 未使用 iOS 17 滚动 API（`ReaderScrollPositionPolicy` 是自定义类型名） |
| `containerRelativeFrame` / `safeAreaPadding` | 0 | 未使用 |
| `symbolEffect` / `phaseAnimator` / `keyframeAnimator` | 0 | 未使用 |
| `@Observable` / `SwiftData` / `@Model` | 0 | 未使用 |
| `presentationBackground` | 1 | 已有 `#available(iOS 16.4, *)` 分支 |
| `UITextView(usingTextLayoutManager:)` | 2 | iOS 16.0+；`NativeReaderTextView` 已有 16.0 分支，`ReaderPageTextView` 部署目标即 16.0 |
| 其他 `#available` | 4 处 | iOS 13（zlib）、iOS 15（ProMotion）、iOS 16.0（TextKit1）、iOS 16.4（sheet 背景） |

## 四、本轮 iOS 16 防御（`ffb9da4`）

`ReaderPageTextView` 在 `makeUIView` 中新增：

```swift
view.contentInset = .zero
view.contentInsetAdjustmentBehavior = .never
view.textContainer.maximumNumberOfLines = 0
view.textContainer.lineBreakMode = .byWordWrapping
```

并新增：

```swift
func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width, let height = proposal.height else { return nil }
    return CGSize(width: width, height: height)
}
```

逐项原因：

| 设置 | iOS 16 风险 | 作用 |
|---|---|---|
| `contentInsetAdjustmentBehavior = .never` | `UIPageViewController` 子控制器的安全区会通过 content inset 再传给 `UITextView`，正文首行下移或被裁 | 禁止系统自动加 inset，页面几何只由 `ReaderPageGeometry` 决定 |
| `contentInset = .zero` | 默认 inset 在部分机型上非零 | 清掉额外内边距 |
| `maximumNumberOfLines = 0` + `byWordWrapping` | 容器初始宽度异常时可能错误截断 | 明确多行、按词换行 |
| `sizeThatFits` 返回 proposal | `UITextView` 的内容高度会参与 SwiftUI 测量，可能把页面撑长 | 页面尺寸完全由 `pageSurface` 的固定 frame 决定 |

## 五、按模块的 iOS 16 判断

| 模块 | iOS 16 行为 | 证据 | 结论 |
|---|---|---|---|
| 分页正文（平移/覆盖/仿真） | `UITextView` TextKit1，justified | `ReaderPageTextView`、`ReaderPageTextBuilder`；CI Build 通过 | 可用；首帧与快照待真机 |
| 滚动模式 | WKWebView + CSS | iOS 16 WKWebView 支持 `text-align: justify` / `text-align-last` | 可用 |
| 书架/发现/详情 | SwiftUI 基础布局、`AsyncImage` 兼容层 | 无 iOS 17 API | 可用；布局待真机 |
| 导航大标题 | `.inline` | iOS 16 支持 | 可用 |
| 登录/封面 | 纯 URL 解析 | 无系统版本依赖 | 可用 |
| Sheet 背景 | 16.4 才有 `presentationBackground` | `#available(16.4)` | 16.0–16.3 无背景，不崩溃 |
| 朗读/自动翻页 | AVSpeech / Timer | iOS 16 支持 | 可用（非本轮范围） |

## 六、仍然只能真机确认的 3 件事

1. **`UIPageViewController.pageCurl` 对 `UITextView` 的快照。** iOS 16 的 page curl 会对子控制器视图做图层快照；TextKit 视图在快照瞬间是否完整，编译无法证明。
2. **首帧布局。** `UIViewRepresentable` 第一次 `updateUIView` 时 bounds 可能还是 0；`widthTracksTextView` 会在下一次 layout 修正，但如果 iOS 16 上出现首屏空白/错位，需要把 `textContainer.size` 的首次赋值显式化。
3. **字体行高与分页高度。** 苹方在 iOS 16 与 iOS 17+ 的 ascent/descent 可能有细微差异；分页用 TextKit 测量，理论上一致，但 SE/mini 的小屏 contentHeight 更紧，末行裁切会最先暴露。

## 七、真机验收矩阵（必须执行）

机型：iPhone SE 2/3（667pt 高、无刘海）、13 mini（812pt、刘海）、14/15/16 标准、Pro、Pro Max。
系统：iOS 16.0–16.7 至少两台不同小版本。

每条记录机型 / 系统 / 模式 / 结果：

1. 平移、覆盖、仿真、上下滑动：正文整行两端对齐，最后一行不被拉伸。
2. 首行缩进 2 字符；跨页续上的段落开头不缩进。
3. 长段落跨页：末行不被裁切，总页数不比旧版多。
4. 朗读高亮跟随段落，页面不因高亮上下跳。
5. 含插图页可点开图片，文本回退路径不崩溃。
6. 关闭文本选择时点击翻页正常；开启后长按可选。
7. 书架/搜索/发现/详情：搜索框不压导航栏，封面三处都显示。
8. 阅读器顶栏/底坞：正文不透出，按钮不被安全区裁切。

## 八、如果 iOS 16 真机仍然出问题，排查顺序

1. 末行裁切 → 先看 `ReaderPageGeometry.contentHeight` 与 `UITextView` 的 `lineFragment` 高度；把 `contentInsetAdjustmentBehavior` 临时改回 `.automatic` 对比。
2. 首屏空白 → 在 `updateUIView` 里打印 `view.bounds`、`textContainer.size`；必要时 `DispatchQueue.main.async` 再赋一次 `attributedText`。
3. 仿真翻页闪白 → 改用 `.scroll` 过渡做 A/B；若 scroll 正常、pageCurl 空白，则是快照问题，需要在翻页前强制 `layoutIfNeeded()`。
4. 字体行高差异 → 用 `UIFont.lineHeight` 与 `ReaderPageLayoutEngine.measureHeight` 对同一段文本做对比日志。

## 九、结论

- **可以确认：** 没有 iOS 17-only API 的裸调用；iOS 16 编译通过；UITextView 的 inset / 尺寸路径已加防御。
- **不能确认：** iOS 16 真机上的 page curl 快照、首帧布局、字体行高。
- **因此：** 这份审计不能替代真机。把 1.0.65 装到至少一台 SE 和一台 13 mini 上跑第七节 8 条，才能给出“iOS 16 可交付”的结论。

## 十、验证记录

| 项 | 值 |
|---|---|
| 代码基线 | `ffb9da4`（iOS16 inset / 尺寸防御） |
| CI iOS | run `40559137785`，Build 成功，`1102 tests / 0 failures` |
| CI IPA | run `40559137604`，打包成功 |
| IPA 路径 | `C:/Users/Edc21/Desktop/SourceReadSwift-1.0.65-ios16-unsigned.ipa` |
| IPA 大小 | `12,155,355` 字节 |
| SHA256 | `761616A840F65F6E44CE149EA65EA9592C68A8D661B68C4CB09677F4ED173AB9` |
| 包内版本 | 1.0.65 / Build 66 / MinimumOSVersion 16.0 |
