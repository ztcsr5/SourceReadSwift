# 第二批：漫画阅读器移植

## 边界

- 只更换漫画阅读体验。纸间继续使用当前 JSON 书源、请求上下文、本地 CBZ、离线漫画、书架和进度记录。不新增 AidokuRunner、WASM 扩展、第三方漫画资产或私有系统接口。
- 唯一开发线为 `codex/next-from-build150`。按用户授权先确认仓库已改为 Private，之后才能推送含移植代码的提交；只在私有 Actions 产出验收证据，不发公开 Release。

## 上游和接线

- Aidoku 主仓库锁定于 [95d1468d](https://github.com/Aidoku/Aidoku/commit/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd)。保留 Skitty 和 Mantton 在 [偏移保留布局](https://github.com/Aidoku/Aidoku/blob/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd/Aidoku/Features/Reader/Readers/Webtoon/VerticalContentOffsetPreservingLayout.swift) 的署名，适配至 `ComicOffsetPreservingLayout`。页码和剩余页计数采用 [ReaderToolbarView](https://github.com/Aidoku/Aidoku/blob/95d1468d599a154f03d6a1dd06bf839d3ff3f7bd/Aidoku/Features/Reader/Toolbar/ReaderToolbarView.swift) 的逻辑；系统玻璃、原生滑杆和设置表单接入纸间现有 UIKit / SwiftUI 组件。不移植上游私有 Lens 类。[GPLv3 原文](../licenses/Aidoku-GPL-3.0.txt)保留在此仓库。
- 条漫最多挂载当前话及紧邻的前后一话。只拼接完整相邻话，未完成的章节不越过；在拖动、惯性和缩放结束后应用会改变布局的补入，依据同一页的稳定标识和内部位置补偿偏移。翻过去又折返时重用仍挂载的图片页，不按章节强制重建整页。
- 远端 ±10 章仍只预取地址；图片只跟随屏幕和有限的前后页行进。传输与解码继续使用现有并发/缓存预算；真实图尺寸入布局后才显示位图，以免先缩在占位框再弹大。已有可见图片不取决于全局缓存是否刚淘汰该项。
- 右上角「大小」提供真实绑定的漫画设置；设有阅读模式、连续滚动、图片品质、双击、滑动收栏、背景、点按方向、翻页微动效、页图预取、黑边及方向。没有上架未接线的超分、实时文本或宽图切割开关。

## 验收

1. Windows 只做语法和脚本契约检查。没有本地 Xcode。
2. 私有 Actions 的 `.github/workflows/comic-reader.yml` 跑 iOS 26 编译和针对性 XCTest / XCUITest：真实图片复用、拖动中延后重排、向前和向后跨话、双击/捏合、双向翻页、CBZ 离线、回书架和恢复进度。专项结果与全量结果分开记录。
3. 最终同一 SHA 再跑 `ios.yml` 和 `unsigned-ipa.yml`。120 Hz、真机快甩的触感和外部网络书源稳定性以 iPhone 实测为准，不能从模拟器截图推断。
