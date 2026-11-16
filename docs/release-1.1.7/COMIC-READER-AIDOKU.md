# 第二批：漫画阅读器移植

## 边界

- 只更换漫画阅读体验。纸间继续使用当前 JSON 书源、请求上下文、本地 CBZ、离线漫画、书架和进度记录。不新增 AidokuRunner、WASM 扩展、第三方漫画资产或私有系统接口。
- 唯一开发线为 `codex/next-from-build150`。按用户授权先确认仓库已改为 Private，之后才能推送含移植代码的提交；只在私有 Actions 产出验收证据，不发公开 Release。

## 上游和接线

- Aidoku 主仓库锁定于 [95d1468d](https://github.com/Aidoku/Aidoku/commit/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd)。保留 Skitty 和 Mantton 在 [偏移保留布局](https://github.com/Aidoku/Aidoku/blob/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd/Aidoku/Features/Reader/Readers/Webtoon/VerticalContentOffsetPreservingLayout.swift) 的署名，适配至 `ComicOffsetPreservingLayout`。页码和剩余页计数采用 [ReaderToolbarView](https://github.com/Aidoku/Aidoku/blob/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd/Aidoku/Features/Reader/Toolbar/ReaderToolbarView.swift) 的逻辑；系统玻璃、原生滑杆和设置表单接入纸间现有 UIKit / SwiftUI 组件。不移植上游私有 Lens 类。[GPLv3 原文](../licenses/Aidoku-GPL-3.0.txt)保留在此仓库。
- 条漫最多挂载当前话及紧邻的前后一话。只拼接完整相邻话，未完成的章节不越过；在拖动、惯性和缩放结束后应用会改变布局的补入，依据同一页的稳定标识和内部位置补偿偏移。翻过去又折返时重用仍挂载的图片页，不按章节强制重建整页。
- 远端 ±10 章仍只预取地址；图片只跟随屏幕和有限的前后页行进。传输与解码继续使用现有并发/缓存预算；真实图尺寸入布局后才显示位图，以免先缩在占位框再弹大。已有可见图片不取决于全局缓存是否刚淘汰该项。
- 阅读器右上角「设置」提供真实绑定的完整漫画设置；设有阅读模式、连续滚动、图片品质、双击、滑动收栏、背景、点按方向、翻页微动效、页图预取、黑边及方向。没有上架未接线的超分、实时文本或宽图切割开关。

## 验收

1. Windows 只做语法和脚本契约检查。没有本地 Xcode。
2. 私有 Actions 的 `.github/workflows/comic-reader.yml` 跑 iOS 26 编译和针对性 XCTest / XCUITest：真实图片复用、拖动中延后重排、向前和向后跨话、双击/捏合、双向翻页、CBZ 离线、回书架和恢复进度。专项结果与全量结果分开记录。
3. 最终同一 SHA 再跑 `ios.yml` 和 `unsigned-ipa.yml`。120 Hz、真机快甩的触感和外部网络书源稳定性以 iPhone 实测为准，不能从模拟器截图推断。

## 第一轮原生结果

- `c5142f1c` 首次原生编译发现合并页图请求头的返回类型为字典，已在 `191be4b6` 重新构建请求对象。
- [191be4b6 漫画专项](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43843572138)：iOS 26 编译通过；63 项单测通过，8 项 UI 中 7 项通过。实际双向自动跨话、设置开合保持原位、续读、CBZ、离线下载与左右翻话均通过。剩余一项在缩回适屏的断言失败；扩大到全屏后捏合测试目标从 `y=59` 变为 `y=50`，只给条漫保留全屏铺底，横向翻页恢复原有安全区域，断言不变，等待复跑。
- [同 SHA 设备包](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43843572142)已成功打包，但未作为最终 IPA 交付。

## 第二轮原生验收

- `a36083ef31389f4574948545fa16f53f235af814`：[漫画专项 43845662013](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43845662013) iOS 26 编译通过，63 项 XCTest、8 项 XCUITest 均通过，含恢复安全区后的捏合回到 100% 并继续翻页。Windows 216 项脚本、名称遮蔽检查和 diff 检查通过。
- [原生截图与日志 14215986904](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43845662013/artifacts/14215986904)：`comic-native-chrome` 记录右上角「大小」入口和底部页码；`comic-native-settings` 由真实打开后的设置页采集，使用可离线重复的测试样图而非 Aidoku 漫画资产。
- [同 SHA 未签名设备包 43845662065](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43845662065)成功。未交付正式 IPA，未验证 iPhone 实际帧率。保持原定节奏：下一批视频、听书和正文 TTS；之后处理阅读转场等第四批内容，再在最终 SHA 跑完整回归。
