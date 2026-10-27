# SourceReadSwift v1.0.63 交接文档 — 自定义壁纸布局溢出修复

**版本：** 1.0.63 (Build 64)
**分支：** `codex/reader-feedback-fixes`
**代码 Commit：** `1e55d3268bc126a34074f6f816692b3fbf608bf6`
**日期：** 2026-10-27
**上游交接：** `docs/CODEX_HANDOVER_1_0_62.md`（滑动模式页脚状态带）

---

## 一、问题现象

真机截图（390×844pt，自定义壁纸 + 深色文字样式）：

1. 设置面板左右被裁：标题「阅读设置」只剩「读设置」，右侧「高级」选项卡、最右颜色圆点、底部壁纸模式按钮文字都被切掉；
2. 阅读页顶部工具条同样左右溢出：返回按钮被裁、右侧按钮只显示一半；
3. 顶部正文压到系统状态栏区域；
4. 只有选择「自定义壁纸」后出现，预设背景正常。

## 二、根因

`readerBackdrop` 中的壁纸没有视口约束：

```swift
Image(uiImage: image)
    .resizable()
    .scaledToFill()
```

`ReaderCustomWallpaperStore.loadWallpaper()` 使用 `UIImage(data:)` 解码，`scale = 1`，图片点尺寸等于像素尺寸。以 1080×2160 壁纸、390×844 视口为例：按高度填充需要 422×844，`.scaledToFill()` 把这个溢出尺寸报告给父级 `ZStack`。根 `ZStack` 取最大子视图尺寸，布局宽度变成约 422pt，居中于 390pt 屏幕，左右各溢出约 16pt，所有 chrome 与设置面板一起被裁。

设置面板的 `GeometryReader` 读取的是被撑大的 `ZStack` 宽度，因此面板自身也按 422pt 布局，问题被进一步放大。

## 三、修复

### 3.1 壁纸限制在视口内

`SourceReadSwift/Features/Reader/ReaderView.swift`：

```swift
Image(uiImage: image)
    .resizable()
    .scaledToFill()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
```

`frame` 让 Image 的布局尺寸等于视口，`clipped()` 裁掉比例填充的溢出部分。壁纸仍然铺满全屏，但不再撑大父级布局。

### 3.2 分页背景同步

`pageBackground` 的壁纸同样加 `.frame(maxWidth: .infinity, maxHeight: .infinity)`；外层 `ZStack` 已有 `.clipped()`。分页 / 覆盖 / 仿真翻页与滚动模式行为一致。

### 3.3 根布局锁定

根 `ZStack` 增加：

```swift
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

把阅读器布局尺寸锁定在视口提案内，防止其它子视图再次把根布局撑大。该修饰符不裁剪绘制，`readerBackdrop` 的 `ignoresSafeArea()` 仍能铺满状态栏与 home indicator 区域。

## 四、验证

- 版本三处同步：1.0.63 / Build 64；
- CI：GitHub Actions run `40504290855`（commit `1e55d32`）：Build 成功；Test `1068` 个用例、`0` 失败、`** TEST SUCCEEDED **`（2026-10-27T12:38:52Z）；
- IPA：GitHub Actions run `40504290853` 成功；产物 `C:/Users/Edc21/Desktop/SourceReadSwift-1.0.63-unsigned.ipa`，`12,031,282` 字节，SHA256 `9AEF2509AA423BF0F44CBAA81257D5561734A43A78612F0AC92FCE8095DD8C29`；包内 `CFBundleShortVersionString=1.0.63`、`CFBundleVersion=64`、`MinimumOSVersion=16.0`、`CFBundleIdentifier=com.edc21.SourceReadSwift`。

## 五、真机验收（未通过前不得写成已通过）

1. 自定义壁纸下：设置面板左右完整，标题、分段控件、颜色圆点、底部按钮均不被裁切；
2. 顶部工具条返回按钮完整，右侧按钮不半截；
3. 壁纸铺满屏幕、比例正确、无明显拉伸或色带；
4. 浅色壁纸（深色字）/ 深色壁纸（浅色字）切换正常；
5. 预设背景无回归；
6. 分页 / 覆盖 / 仿真翻页下壁纸同样正常。

## 六、回滚

`git revert 1e55d32`。

## 七、文件清单

修改：

- `SourceReadSwift/Features/Reader/ReaderView.swift`
- `project.yml`、`SourceReadSwift/App/Info.plist`、`SourceReadSwift/Shared/AppVersion.swift`
- `SourceReadSwiftTests/SearchURLResolverTests.swift`
