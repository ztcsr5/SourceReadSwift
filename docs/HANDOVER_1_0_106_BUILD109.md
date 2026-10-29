# 1.0.106 build 109 · 交付说明

- 提交：`91da7758b2660c3b323972cae8cf2a152e27b769`（10 个文件，远端字节 == 本地字节）
- CI：`40900706922` iOS success（编译 + XCTest）、`40900706853` Unsigned IPA success
- 包：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.106-109.ipa`
  - size 12560508
  - SHA256 `E815A5A2325D048B9442B34976CAD0092DE7C69299C74A5BE3B507C01143DAAC`
  - Info.plist：1.0.106 / 109 / MinimumOSVersion 16.0
- 二进制自检：`ReaderPrepaginatedTextView`×26、`prewarmSize`×3、`ReaderTocFilterCache`×58、`scrollTocToCurrentChapter`×10、`BookTOCacheStore`×168

## 本轮（109）改动

1. **每页卡顿 · 三条根因**
   - `ReaderPageTextView.swift`：新增 `ReaderPrepaginatedTextView`，`setPage` 后在 `layoutSubviews` 里对已量到宽度的容器执行 `ensureLayout`，把 TextKit 字排从「上屏第一帧」挪到离屏预热。
   - `PageCurlReaderView.swift`：预热签名加入视口尺寸，修掉「首次 sync 在容器未测量时把空转记为已预热」的冷页永不预热。
   - `ReaderCJKPunctuationCompression.swift`：逐字符 O(全文) 改为按标点范围跳点循环。
2. **排版**：`ReaderView.swift` L4156 行距滑块的说明缩短，标题不再挤两行。

## 108 已带

- 底栏四个常驻入口：目录 / 换源 / 书签 / 设置（`ReaderView.swift` L3537-3560）
- 主题去 material + 独立 opacity + 描边；阅读器 `preferredColorScheme` 跟随主题而非系统
- 三点菜单关闭用 `Transaction(disablesAnimations:)`，不再闪
- 目录 `ReaderTocFilterCache` + `enumerated()` ForEach 降掉帧
- 再开目录 `scrollTocToCurrentChapter` 定位当前章
- 详情页目录两阶段加载（首屏 6 页 → 后台全量 + `BookTOCacheStore` 落盘）

## 装机验收（#1）

1. 本地导入书，同一章快速连翻 10 页 → 看首帧是否「空白一瞬再出字」。
2. 慢速 5 页 → 对比是否仍有下一页加载感。
3. 章末倒数第 3 页起继续翻，测跨章衔接。
4. 若快翻仍卡：把 `prewarm` 的 `+1` 从 `asyncAfter(0)` 改为同步构建，候选扩到 ±4。
5. 若出现空白页：先删 `layoutSubviews` 里的 `textContainer.size` 赋值，只留 `ensureLayout`。

## 76 书源现状（2026-10-29 23:44）

- 结构通过 9/76（1.0.103 真机 PASS4 8 条 + #7 顶点小说离线四步全通）
- 空壳 20 条；其中 8 条在 `docs/sources/shareBookSource11-fixed-1.0.95.json` 已有 5/5 规则待验：#34 #48 #52 #53 #62 #64 #65 #66
- 登录墙 3 条（#02 #11 #21）；详情失败 4 条；目录 0 章 7 条；正文 0 字/驱动超时 2 条
- 真机复测受阻：`192.168.31.205:8080` 23:44 连接被拒（App 内 web 服务未运行）