# SourceReadSwift v1.0.64 交接文档 — 自定义壁纸 UIKit 图层与导入降采样

**版本：** 1.0.64 (Build 65)
**分支：** `codex/reader-feedback-fixes`
**代码 Commit：** `9d2b35a4386029d6f9a43e162bec9fd2d60fa2eb`
**日期：** 2026-10-27
**上游交接：** `docs/CODEX_HANDOVER_1_0_63.md`（壁纸 Image 加 frame/clipped）

---

## 一、问题现象

v1.0.63 给 SwiftUI `Image` 加了 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 与 `.clipped()` 后，自定义壁纸下设置面板左右被裁、顶部工具条返回按钮被裁的问题仍然复现。用户怀疑与图片导入比例有关。

## 二、参考实现

### 2.1 栖阅（SwiftUI + WKWebView）

解包符号与字段：

- `staticBackgroundImageView`：壁纸是独立的 `UIImageView`，背景固定、正文滚动；
- `backgroundImageOpacity`、`dimmingOverlay`：壁纸强度与压暗层；
- `backgroundImageFile` / `darkBackgroundImageFile`、`backgroundImageData` / `darkBackgroundImageData`、`backgroundImageBase64` / `darkBackgroundImageBase64`：浅色 / 深色两套壁纸，文件 + Data + Base64 三种存储；
- `_showingBackgroundImagePhotoPicker`、`_backgroundImageFileImporter`、`_backgroundImageImportTarget`：相册与文件导入入口。

### 2.2 开元阅读（Flutter）

- `ReaderBackgroundImage...` 模块与 Flutter `BoxFit`；
- 文案「背景图片强度」「上下滚动时整张背景固定显示，仅中间正文滚动」。

### 2.3 共同点

壁纸是独立图层（UIImageView / ImageView），不参与正文排版与父级测量；导入后按屏幕/最长边处理；有填充方式与强度控制；浅色/深色分开存储。

## 三、根因（二次定位）

v1.0.63 仍使用 SwiftUI `Image`。在 `ZStack` 的提案阶段，`Image` 仍可能按“比例填充后的理想尺寸”参与父级测量；`.frame` 只能限制最终绘制框，不能保证测量阶段不把 `ZStack` 撑宽。1080×2160 壁纸在 390×844 视口按高度填充需要 422×844，根布局仍可能被撑到 422pt，左右各溢出约 16pt。

## 四、修复

### 4.1 壁纸改为 UIKit 图层

新增 `SourceReadSwift/Features/Reader/ReaderWallpaperView.swift`：

```swift
struct ReaderWallpaperView: UIViewRepresentable {
    let image: UIImage
    let fillMode: ReaderWallpaperFillMode
    ...
}

final class ReaderWallpaperUIImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}
```

`intrinsicContentSize` 为 `noIntrinsicMetric`，布局完全由 SwiftUI 提案决定，从根上切断“壁纸撑大根布局”的路径。`contentMode` 映射：

| 模式 | UIImageView.ContentMode | 效果 |
|---|---|---|
| 填充 | `.scaleAspectFill` | 等比铺满，裁掉溢出 |
| 适应 | `.scaleAspectFit` | 完整显示，留边 |
| 拉伸 | `.scaleToFill` | 铺满，允许变形 |

`readerBackdrop` 与 `pageBackground` 全部改用 `ReaderWallpaperView`。

### 4.2 导入降采样

`ReaderCustomWallpaperStore.saveWallpaper` 先按最长边 `2800px` 等比降采样，再 JPEG 存盘；亮度检测改用降采样后的位图。相册原图常见 12MP，直接解码会长期占用大量内存。

### 4.3 设置面板

`customWallpaperSection` 新增「壁纸填充方式」三档 Picker。切换后 `@AppStorage("reader.customWallpaperFillMode")` 变化，壁纸层即时重建。

### 4.4 保留 v1.0.63 的根布局锁定

根 `ZStack` 的 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 保留，作为第二道保险。

## 五、验证

- 新增 `ReaderWallpaperLayoutTests` 4 个用例：等比缩放、不放大、零尺寸、`contentMode` 映射；
- 版本三处同步：1.0.64 / Build 65；
- CI：GitHub Actions run `40507109670`（commit `9d2b35a`）：Build 成功；Test `1072` 个用例、`0` 失败、`** TEST SUCCEEDED **`（2026-10-27T13:02:57Z）；
- IPA：GitHub Actions run `40507109655` 成功；产物 `C:/Users/Edc21/Desktop/SourceReadSwift-1.0.64-unsigned.ipa`，`12,038,495` 字节，SHA256 `036F5DF8C970BCABE401DA713A1B6DE7684F8351C5764DF7D584C2DAB964E72C`；包内 `CFBundleShortVersionString=1.0.64`、`CFBundleVersion=65`、`MinimumOSVersion=16.0`。

## 六、真机验收（未通过前不得写成已通过）

1. 自定义壁纸下设置面板左右完整，标题、分段控件、颜色圆点、底部按钮均不被裁切；
2. 顶部工具条返回按钮完整；
3. 三种填充方式显示正确：填充裁切、适应留边、拉伸铺满；
4. 切换填充方式即时生效；
5. 导入大图后无卡顿、无明显内存告警；
6. 预设背景无回归；
7. 滚动与分页三种模式下壁纸行为一致。

## 七、回滚

`git revert 9d2b35a`。

## 八、文件清单

新增：

- `SourceReadSwift/Features/Reader/ReaderWallpaperView.swift`
- `SourceReadSwiftTests/ReaderWallpaperLayoutTests.swift`

修改：

- `SourceReadSwift/Features/Reader/ReaderView.swift`
- `SourceReadSwift/Features/Reader/ReaderSettingsModels.swift`
- `project.yml`、`SourceReadSwift/App/Info.plist`、`SourceReadSwift/Shared/AppVersion.swift`
- `SourceReadSwiftTests/SearchURLResolverTests.swift`
