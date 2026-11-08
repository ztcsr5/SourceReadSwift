# SourceRead 1.1.7 · Build 133 交付

## 改了什么

| 范围 | 结果 |
|---|---|
| 正文滑动、顶部状态栏 | 保留 WKWebView 原生惯性，合并几何与位置采样，停止后保留最后锚点；分页轻触不参与正文滑动。工具栏唤出时，独立纸色层保护状态栏，不重排正文。 |
| 书台 | 轻触继续，长按不打开；独立三点保留详情、置顶与删除确认，正文选字及其他书架长按不动。明确标注全书进度，不足 1% 不显示为 0%。 |
| 续读与扉页 | 冻结章段游标，由一个正文加载器负责缓存及网络，滚动首屏不先算分页。正确落点就绪再展示；超时保留记录，允许重试。首次从详情进入独立扉页，详情菜单可重看；不计章节、不写进度。 |
| 主导航 | 普通页面常驻，正文隐藏；兼容分支持有独立栈。iOS 26 关闭[底栏自动缩小](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior/never)，用静态模板固定图标；旧栏只动选中背景。目录末行可避开底栏。 |
| 玻璃 | 保留越界构图，只在背板和兼容底栏加入静态白紫柔光与边缘反射；暗色降低高光，高对比/减少透明度有降级。 |

过程记录：D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.7/BUILD-133-DEVICE-POLISH.md。首轮实际发现本地导入预填的首章名被误当成进度、默认按钮在长按松手时触发阅读；两项已修并保留更严格的 UI 断言。

## 影响面
- 1.1.7 / Build 133，Git 32336bba34853cd279c88252faad53f1edecdfc3。无数据格式迁移；净化、缓存、换源及阅读设置保留。
- C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build133-32336bb-device-polish-unsigned.ipa；23852669 bytes。
- SHA256 82b0c933074361d70dc3ba21c3dc4c0336b7b0c3495d53249da9dc0b87c7ba1b；App/dSYM UUID 8fe6a8c8-0f40-3f86-b0e2-befd9ce97b78。
- 未签名 iPhoneOS arm64，最低 iOS 16。供 LiveContainer 测试，未代签或安装。旧包未覆盖；已核对 Build 132 备份哈希。

## 怎么验证
- Windows：46 项通过。生产 HTML 的 Chromium 合成来回滑动复现：原 17 次文档高度读取，候选实测 4 次，最终段落正确。不是设备帧率。
- iOS 18 完整 CI：1641 单测（2 项原有条件跳过）、15 UI，0 失败。
- iOS 26 原生 CI：190 专项单测、5 设置 UI，0 失败。
- 双系统书台专项：18 为 1641 单测（2 项原有跳过）+10 UI；26 为 68 单测+10 UI，0 失败。重复测试不合计。
- 两系统验证长按、三点、首读扉页、续读到保存段落、详情目录避让、详情与外观跨标签保留。已查看明暗、320 pt 和大字号实拍截图。
- CRC、plist、arm64、字体、ProMotion、符号 UUID、复制后 SHA 均通过。
- CI：iOS 41770076284；Floating Reading Desk 41770076279；Unsigned IPA 41770076278。证据：F:/SourceReadSwift/device-polish-133/32336bba34853cd279c88252faad53f1edecdfc3。实际截图：F:/SourceReadSwift/device-polish-133/32336bba34853cd279c88252faad53f1edecdfc3/review/Build133-iOS26.jpg。

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build133-32336bb-device-polish-unsigned.ipa'
git -C 'D:\Gemini反重力\SourceReadSwift2' diff --name-only 948703a52224d4ee0848cff8c0beef2ca8ffc665..32336bba34853cd279c88252faad53f1edecdfc3
```
预期 hash 如上。待 13 Pro 真机复验：连续快速正反滑和惯性、跨章、进退/快速切标签动画、真实搜索与远程书源、LiveContainer 安装。未宣称 120fps。

## 怎么回滚
```powershell
git -C 'D:\Gemini反重力\SourceReadSwift2' switch codex/product-quality
```
代码回到 948703a52224d4ee0848cff8c0beef2ca8ffc665。已有文档与备份保留。手机先备份再回装 Build 132：F:/SourceReadSwift/product-quality-117/948703a52224d4ee0848cff8c0beef2ca8ffc665/SourceReadSwift-1.1.7-build132-948703a-quality-unsigned.ipa。
