# SourceRead 1.1.7 / build 132 · 产品品质测试候选交付

2026-11-04；源代码 `948703a52224d4ee0848cff8c0beef2ca8ffc665`；分支 `codex/product-quality`。
回退基线 `9c079ce472dc29e5a43176889d9c110bebc4a4f1`。
**不是稳定版发布，不是 iPhone 13 Pro 真机验收完成。**

## 一、改了什么

| 范围 | 确认原因与实际结果 | 验证边界 |
|---|---|---|
| 越界书台 | 保留中央越界、白紫玻璃与书架首屏，书封稍收小并轻倾斜、保留书脊，承托更浅。右上三点/长按复用详情、置顶、删除；轻点直接读。旧紧凑方案开关保留。 | 两运行时白紫/暗色/植物主题、普通/无封面/长书名。原模块高度断言 280–290 pt 不放宽，辅助字号允许纵向增长。 |
| 开书衔接 | TOC、章节加载、阅读器不再各自抢封面；由导航目的地持有一份书籍身份，等导航到达与真实正文就绪再交接。可操作错误会解除遮罩，重试恢复加载反馈。简介共用有界纯文本。 | 实际模拟器进书/正文/返回录屏已看。保留系统 zoom、交互返回及旧系统降级；没有宣称跨所有容器的自定义逐点 Hero 已完成。 |
| 首屏等待 | 录屏发现首屏 0 段只排 rAF，封面覆盖时可等到恢复上限。生产 DOM 冻结 rAF 复现，reset 完成后单次报告位置。 | Chromium 红→绿及原生 WKWebView 通过；“先 ack 后 visible”、旧跳转取消、120 ms 手势节流保持，不加持续刷新。 |
| 阅读位置 | 模式切换曾把窗口平铺段号当章内段号；延迟保存可能组合旧段号与新章节。现在读取同一已提交游标，取消旧防抖，滑条走同一路径。 | 模式/长段 UTF16/相邻章插入/有序持久化回归通过；录屏疑似章节栏滞后未单独稳定复现，不冒称所有跨章情况真机已修。 |
| 拼页与净化 | 只去连续接缝重叠，不再误删新页中的正常重复对话。独立“本章未完”仅在实际补到续页正文后删除；只匹配录屏所示衍墨轩主机的完整独立推广签名。 | 原生夹具覆盖重复、9 页拼接、失败续页、其他主机和正文保留。不会批量改旧缓存；旧章需重新获取。 |
| 详情 | 批量缓存收至目录排序旁下载菜单（后 50/全本/取消），保留进度/失败；阅读为首要操作，隐藏遮挡目录的根底栏，排序单行。 | 实际本地详情和 390 pt 远程加载后布局已看；320 pt 远程截图仍在加载，只确认加载态，不冒称加载后视觉验收。 |
| 阅读设置 | 正文排版、章首、页眉菜单独立归位，经典设置和原键保留；上下菜单共用玻璃基础，复杂壁纸设置加强扩散/保护，墨色跟随实际阅读明暗。 | 两运行时设置 UI、二级返回、重复打开通过；真实竹纹/暗色/分页正文上已看，不替代手机偶发闪退验收。 |
| 下载/清理 | 任务代际防旧取消响应干扰新任务；恢复时核对实际缓存与规则签名，不信历史完成索引。清理前确认并取消下载。 | 持有网络响应/取消重开/缓存缺失原生回归通过，不清理书架/书签/进度。 |
| 换源 | 有章号时严格匹配对应章，确认正文可读后才提交，失败保留旧源和位置。 | 对齐/可用性边界与既有回归通过；真实站点登录/付费/网络仍待联调，跨源段落不保证一致，成功换源从对应章起始段进入。 |
| 日期/诊断 | 历史和离线日期用区域化数字格式；最近诊断/章节失败复制只留允许的结构化元数据，不带请求路径、参数、Cookie、搜索词或原始错误。 | 脱敏和相关回归通过；不泛化为所有高级报告、备份已审计。 |

### 性能工作的真实范围

- 沿用此前已完成的明确开启、最多 30 秒、退出/退后台停止的单实例诊断，普通阅读不自动高频采样；读数是回调，不是显示 FPS。
- 保留有序后台进度/历史写入、读取/删除屏障、有限后台落盘和合并通知。本轮补强游标一致性、首屏就绪；不重写存储，不增加全局 CADisplayLink，不改 ProMotion 配置。
- 最终 HEAD 模拟器夹具：4,124,384 B 正文书架对应 149 B 进度旁路，含重读约 0.0162 s；另一次入队约 0.139 ms，含后台完成约 123.0 ms。它们不是每帧耗时、真机改善百分比或 FPS。
- 搜索已有后台投影、批量发布与取消代际，本轮保持，未凭录屏聚合采样改写。模拟器零硬件周期/指令计数判无效，变帧率录屏不用于证明 120fps。

### 真实运行资料

是原生 App/导航/WKWebView，不是设计稿；书籍来自隔离离线夹具，不能代表网络书源质量。发布版没有替换用户内容。

- 对照图：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/DELIVERY-actual-app.jpg`
- 原始首页/详情/设置：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/home-ios26.png`、`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/detail-ios26.png`、`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/settings-ios26.png`
- iOS 26 进入正文/返回：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/liquid-glass-reader-entry-return.mp4`
- iOS 18 同流程：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/compatibility-reader-entry-return.mp4`
- 原片与未重采样出处：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/liquid-glass-video-excerpt.json`；静态范围：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/VISUAL_REVIEW.json`。

### 未完成与风险（按优先级）

1. **真机 P0**：13 Pro 进出/取消返回/快速切书、后台与重启位置、间歇闪退、真实 QQ 本地约 12 MB TTF。模拟器同体积有效字体/超时/取消通过，不等于用户字体已成功。
2. **离线容量**：原章节 LRU 仍为 500 条，“全本缓存”不代表长篇永久全本离线。修了取消/恢复/误导状态，未临时重建离线库；下一轮应独立处理受保护的离线书籍存储。
3. **位置精度**：进程内模式切换保留 UTF16 位置，重启主要持久化章/段；同一长段内字符级重启、跨源字符迁移未新增保证。
4. **转场手感**：已清除开书多封面/就绪竞争，保留原生进退；没有把模拟器检查写成所有设备达到 Rex 手感，也未为定制 Hero 重写路由。
5. **全局功能评估不等于重做**：书摘返回原文、WebDAV/备份回滚、漫画、有声、源规则/Cookie/代理/LAN 写源保留现有功能和回归。真实提供方/手机后台/LAN 联调、各漫画源及高级导出凭据审计仍需验收。
6. 最低 iOS 16 与兼容分支保留，实际模拟器覆盖 18/26；320 pt 远程详情加载后需补查；最大辅助字号不承诺书架同屏。
7. 启动引导仍暂停；12 用户手测，未访问网关。未重做六套主题或重写书源引擎。

## 二、影响面与 IPA

- 无数据格式迁移，无签名/证书/分发配置改动；原有阅读、书源、漫画、有声、经典设置保留。
- 版本仍 `1.1.7 / build 132`，用短 SHA 区分旧候选。
- 桌面：`C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build132-948703a-quality-unsigned.ipa`
- 大小 23,824,348 B；SHA256 `917d8d86d3dee234e26069f1348b25ab3ccadc69563627ec56525d90324d8ef2`。
- App/dSYM UUID `4de78db8-ccd7-38e9-8451-8e5f6691a002`；符号：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/SourceReadSwift-device-symbols.zip`。
- **真实 iPhoneOS arm64 未签名 IPA**，供现有 LiveContainer 导入测试；不是可直接独立安装的已签名包。本轮未手机安装/代签，容器兼容性须真机确认。升级前先用现有备份流程保留数据；独立侧载沿用用户已有签名流程。
- 已有桌面包交付前后 hash 一致，未覆盖。

## 三、怎么验证

| 工作流 / run | 运行时 | 实际结果 |
|---|---|---|
| iOS / 41754558285 · build | 18 | 1639 单测，2 原有 skip，0 失败；13 UI，0 失败 |
| iOS / 41754558285 · native-tabs | 26 | 188 专项单测 + 5 设置 UI，0 失败 |
| Floating Reading Desk / 41754558377 | 18 | 1639 单测（2 原有 skip）+ 8 UI，0 失败 |
| Floating Reading Desk / 41754558377 | 26 | 66 专项单测 + 8 UI，0 失败 |
| Unsigned IPA / 41754558264 | iPhoneOS | 设备编译/打包、CRC/plist/minOS16/arm64/字体/ProMotion/符号UUID/复制后 hash 通过 |
| Windows | 源码契约、Node/Chromium 生产 DOM、策略 | 42 项通过；28 个变更 Swift 语法/diff 通过；不是本地 iOS SDK 编译 |

不把重复执行相同用例相加成独立用例总数。两项原有 native-only 测试在 18 条件跳过，26 分支实际执行；未跳新增测试或放宽产品断言。

原始日志/大小/SHA/总结：`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/ci-status.json`、`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/VERIFICATION.json`、`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/IPA_VERIFICATION.json`、`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/CHANGESET.json`、`F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/review/PERFORMANCE.json`。
旧编译/高度断言/底栏定位失败证据分别留在各 HEAD 目录；修了合法 ViewBuilder、原高度包络和真实底栏按钮定位，不是删断言。

```powershell
Set-Location -LiteralPath 'D:\Gemini反重力\SourceReadSwift2'
git rev-parse HEAD
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py' -q
git diff --check
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build132-948703a-quality-unsigned.ipa'
```

预期 HEAD `948703a52224d4ee0848cff8c0beef2ca8ffc665`；`Ran 42 tests` / `OK`；diff 无输出；IPA hash 同上。

### 待真机验收（未运行）

1. 备份→导入候选→轻点直接读/长按与三点管理/书架详情；快速进出各 10 次、取消边缘返回，核对封面、底栏、滚动位置。
2. 跨章→目录高亮→切翻页模式→重进→切书→后台→终止重启；逐项核对章/段，不只看百分比。
3. 原 QQ 本地 TTF 导入/应用/重开；失败取消不改原字体。竹纹/暗色/白底重复开设置、二级返回、关闭。
4. 断网/失败换源、缓存/取消重开/清理/重读；超过 500 章遵守现存容量限制。
5. 同电量/温度/低电量/限制帧率条件对照原生列表；有 Mac 后再测 Instruments Hitches / Time Profiler。当前无设备 .trace，不声称 120fps。

## 四、怎么回滚

```powershell
git -C 'D:\Gemini反重力\SourceReadSwift2' switch codex/floating-reading-desk
```

该分支仍指向 `9c079ce472dc29e5a43176889d9c110bebc4a4f1`。切换代码，保留本候选分支及本地文档，不替换手机安装；手机回退沿已有容器/签名流程，先备份。可按 `git log 9c079ce..948703a` 单项 revert，不 reset/stash/clean。

交付前原有 7 个修改文档全部与外部备份 SHA 相符。现仅 RECOVERY 加最新指针、CHANGELOG 加候选记录，旧字节完整保留；其余 6 个文档和未跟踪备份不动。交付文档/回执刻意不再提交，源代码保持精确已测 HEAD；应用/测试/CI 已独立 Conventional Commits 推送。

### 文件清单

- `D:/Gemini反重力/SourceReadSwift2/.github/workflows/floating-desk.yml`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Core/Engine/SourceEngine.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Core/Rules/SourceChapterAlignment.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Core/Rules/SourceDiagnosticReport.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Core/Storage/ChapterContentCacheStore.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Core/Storage/ChapterDownloadStore.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/BookshelfView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/FloatingReadingDesk.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/ReaderOpeningPage.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/ReadingDeskContent.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Discover/BookDetailView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderAtelierPreview.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderChromeEditor.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderChromeSurface.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderSettingsWorkbench.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/WebReaderDocument.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Settings/ReaderDataManagementViews.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Settings/RecentDiagnosticsView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Settings/SettingsView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/LegacyTabBar.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/ChapterDownloadStoreTests.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/FloatingReadingDeskTests.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/ReaderScrollCadenceTests.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/Release111RegressionTests.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/SourceDiagnosticReportTests.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/SourceEngineStage18FixtureTests.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftUITests/FloatingReadingDeskUITests.swift`
- `D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.7/PRODUCT-QUALITY.md`
- `D:/Gemini反重力/SourceReadSwift2/scripts/test_product_quality_scope.py`
- `D:/Gemini反重力/SourceReadSwift2/scripts/test_reader_jump_reports.py`

交付追加：`D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.7/PRODUCT-QUALITY-DELIVERY.md`、`D:/Gemini反重力/SourceReadSwift2/CHANGELOG.md`、`D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.7/RECOVERY.md`。
