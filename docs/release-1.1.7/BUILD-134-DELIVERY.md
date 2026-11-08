# SourceRead 1.1.7 · Build 134 交付（2026-11-04）

## 改了什么

- 保留越界书台，不改横向信息卡。增加克制的书页边缘、书脊、接触投影和珍珠白/浅紫静态明暗。两行书名统一预留空间，原 280–290 pt 标准模块高度断言保留，切书不带动下面书架。保留旧版开关、减少透明度/动态效果及高对比降级。
- 首页书名优先解析 Songti SC Regular；作者/章名仍用无衬线。实际模拟器系统衬线的中文没有变成宋体，因此加入仅用于首页标题的 Reading Desk Song Regular 离线回退：固定版本 Noto Serif SC 400 的 OFL 子集，3,268,332 bytes、7,851 字符。正文与用户导入字体选择不变。罕见字由系统补字，不伪称全字库。
- 封面不缩小规避模糊：按显示尺寸×scale 和少量透视余量独立解码；194 pt / 3× 为 699 px，上限 896 px。正确尺寸的热缓存优先于转场小图；不同尺寸可共用原始字节，ImageIO 从原图降采样，不重复 JPEG 压缩、不锐化/超分。
- 新增原始字节缓存仅内存：12 项/12 MiB、单项 2 MiB、最长 300 s；遵守显式有效期，no-store/no-cache/private 不进入该缓存。插画与封面命名空间分开。没有擅自改图源地址。
- 开书捕获已解码封面，不在等待页另取小图；重访扉页改取当前章节，不沿用旧页面创建时的章节。仍等真实落点和导航到达，不增加固定播放时间。
- 保留并回归上一轮轻点直读、独立三点/删除确认、取消书台长按、正文选字、首读扉页/续读区别、主底栏常驻、位置保存、原生滚动和诊断隔离。本轮没有重做寻书页面、书源引擎或全局主题。

主要文件（完整差异用下方 Git 命令核对）：
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/FloatingReadingDesk.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/EditorialBookJacket.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/ReadingDeskTitleTypography.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/ReadingHeroCard.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/BookshelfView.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/ReadingCoverHandoff.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/ReaderOpeningPage.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Discover/BookDetailView.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/CachedRemoteImage.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/RemoteImageLoader.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/CoverSourceBytes.swift
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Resources/Fonts/ReadingDeskSong-Regular.ttf（许可证/来源随包）
- D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/FloatingReadingDeskTests.swift
- D:/Gemini反重力/SourceReadSwift2/scripts/test_product_quality_scope.py
- D:/Gemini反重力/SourceReadSwift2/scripts/build_reading_desk_font.py（维护时才用）
- D:/Gemini反重力/SourceReadSwift2/project.yml
- D:/Gemini反重力/SourceReadSwift2/.github/workflows/floating-desk.yml

## 影响面

- 1.1.7 / Build 134；codex/build134-desk-fidelity；Git f69bd4231efaf0c2906a0c0172647a4010febd27。
- IPA：C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build134-f69bd42-desk-fidelity-unsigned.ipa；25802827 bytes。
- SHA256：c5a55b71a9827fbf3337fcd04005b06180e25bab6c3ff93588782f4a55838333。
- 未签名 iPhoneOS/arm64，最低 iOS16；App/dSYM UUID 48c09a93-04d0-3d7d-a08b-fc4afb21a518。供已有 LiveContainer 环境导入测试，不是直接安装的签名发行包；未代签/安装/改证书。建议先备份书架与进度。
- 无存储迁移，旧包和既有工作树修改保留。四个提交：777a9e6、e7239a7、1cc0835、f69bd42；旧未提交文档不混入代码提交。
- **未决风险**：主 iOS18 首跑两条真实 UI 失败（详情续读、设置场景），现场均为“未能恢复阅读位置”，不是设置点击退主页，旧位置未被覆盖。原始日志 job-126400227746.log 和失败截图保留。同 SHA 独立双系统书台测试及唯一一次完整干净重跑都通过，未改断言；不能据此声称偶发失败根因已修复。
- **真机待测**：13 Pro 输入延迟/120Hz 帧时间、正反滑/跨章、返回与取消、真实远程书源加载、真实问题 12 MB TTF、LiveContainer 安装。模拟器冷开仍有可见恢复等待，未宣称秒开或 Rex 同等手感。
- 用户截图中《凡人修仙传》的实际图源/原始字节未提供，不能仅凭截图判定原图尺寸；已验证程序路径，低清素材不能凭空变清。受保护的全本离线存储仍为后续工程，现有约 500 章 LRU 未迁移。

## 怎么验证

- 本机：46 项 Python 测试通过；改动 Swift 语法树、YAML、diff 检查通过。不是本机 iOS SDK 编译。
- 同一最终 SHA 的真实 macOS CI：
  - iOS 41776963555：18 完整 1645 单测（2 原有条件跳过）+15 UI，重跑后 0 失败；26 为 190 专项+5 设置 UI，0 失败。
  - Floating 41776963662：18 为 1645 单测（2 原有跳过）+10 UI；26 为 72 专项+10 UI；0 失败。重复测试不累计。
  - Unsigned 41776963593：设备 Release 构建/导出成功。
- 新增实测：800×1200 源图到 176/699 像素、一次获取；48×72 不放大；no-store/有效期/Age；正确尺寸热缓存首帧；宋体解析与离线回退；短/中/长/混合书名在 288/342/398 pt 下不改变模块高度。
- UI：长按不管理、三点不误开书、目录避让、扉页不写进度/已读直读、恢复保存段落、跨标签保留详情与设置、取消/完成边缘返回、减少动态效果。旧进度/净化/换源/缓存测试随原完整套件运行，不冒充真实书源联网验收。
- 已实际查看同一《剑来》600×800 源图、同主题/分辨率的前后对比，明暗/草木、320 pt、大字号和无封面长名截图。原生 26 录屏 614.3 s，已抽帧检查进入/正文/返回，导出约 27 s 不改速、不补帧摘录；录屏不能证明显示 FPS。
- 证据：F:/SourceReadSwift/desk-fidelity-134/f69bd4231efaf0c2906a0c0172647a4010febd27。
- 对比：F:/SourceReadSwift/desk-fidelity-134/f69bd4231efaf0c2906a0c0172647a4010febd27/review/Build133-vs-134-liquid-glass.png。
- 录屏：F:/SourceReadSwift/desk-fidelity-134/f69bd4231efaf0c2906a0c0172647a4010febd27/review/liquid-glass-reader-entry-return.mp4。
- CRC、plist、三份注册字体/新增字体精确 SHA、arm64、ProMotion、符号 UUID、复制后 SHA 全通过；未签名结构已查。

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build134-f69bd42-desk-fidelity-unsigned.ipa'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py' -q
git -C 'D:\Gemini反重力\SourceReadSwift2' diff --stat 32336bb..f69bd42
```

预期 IPA SHA 如上，Python 输出 Ran 46 tests / OK。CI 不代替真机体验验收。

## 怎么回滚

```powershell
git -C 'D:\Gemini反重力\SourceReadSwift2' switch codex/build133-device-polish
```

回到 Build133 的 32336bba34853cd279c88252faad53f1edecdfc3。手机先备份后回装：
C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build133-32336bb-device-polish-unsigned.ipa。
其 SHA256 82b0c933074361d70dc3ba21c3dc4c0336b7b0c3495d53249da9dc0b87c7ba1b 已再次核对。
无需 reset/stash/clean；不要覆盖用户另有编辑。
