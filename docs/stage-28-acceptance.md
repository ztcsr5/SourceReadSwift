# Stage 28：EPUB/RSS 阅读体验与 UI 问题验收

本阶段把用户提出的 23 项阅读界面、搜索、源管理和数据问题收口成一张可复核清单。状态只在代码、测试或真机证据存在时更新；Windows 不伪造 iOS UI/帧率结果。

## 当前清单

| # | 问题 | 当前状态 | 证据/入口 |
|---:|---|---|---|
| 1 | 阅读设置打开后无法退出 | 已修复 | `ReaderChromeStateMachine`，设置面板 X/完成/遮罩/下滑统一关闭 |
| 2 | 滑动条没有说明、不能精确输入 | 已修复 | `ReaderNumberInput` + 排版/高级帮助文案 |
| 3 | 高级页重复翻页、字号、朗读设置 | 已修复 | 高级页只保留朗读速度、定时、常亮、选择、预加载和点击区域 |
| 4 | 自动滚动无效或重复 | 已修复 | `ReaderPlaybackCoordinator` 与自动滚动代际保护 |
| 5 | 朗读总从章节开头开始 | 已修复 | 从当前可见段落开始，空段落过滤 |
| 6 | 目录跳章后菜单状态串页 | 已修复 | 章节/EPUB/书签导航统一 `presentOverlay` / `closeReaderChrome` |
| 7 | 章节字体不一致 | 已修复 | 正文统一 `UIFont.systemFont` |
| 8 | 阅读菜单与右上角操作重复 | 已修复 | 阅读菜单保留控制项，右上角只提供“书籍详情/换源” |
| 9 | 阅读器低帧 | 代码已收口，待真机 | TextKit 重建、分页 debounce、图片/HTML 后台解析；持续 120 Hz 需 ProMotion + Instruments |
| 10 | 主页/发现顶部标题滚动样式 | 代码已对齐，待真机 | 三个根页使用系统 large title，滚动由 UIKit 负责折叠 |
| 11 | PC 无法打开 Web 写源 | 本轮收口 | 优先展示 Wi‑Fi/private IPv4；无 LAN 地址时明确提示；离开页面停止监听 |
| 12 | 书架不能批量管理 | 本轮收口 | 全选/反选/清空/标记已读/移动分组/删除，底部使用 `safeAreaInset` |
| 13 | 源库状态卡片过大、入口重复 | 本轮收口 | 紧凑动作网格，单一导入入口，检测/导入/Web 写源同层 |
| 14 | 书源不能批量管理 | 已具备并收口 | 源管理书源/仓库/RSS 三类批量启用、停用、删除、测试 |
| 15 | 书源不能打开可视化详情 | 已修复 | `SourceVisualDetailView` 展示 Search → Detail → TOC → Content |
| 16 | 设置/发现/源管理入口重复 | 已修复 | 源管理为唯一管理入口，设置移除重复 Web 写源 |
| 17 | 外观切换生硬 | 已收口，待真机 | 主题切换使用局部 easeInOut，不驱动正文树重建 |
| 18 | 底部栏遮挡末尾内容 | 已修复 | 根页、书架批量栏、阅读器、RSS 阅读页统一安全留白 |
| 19 | 数据备份不完整 | 已修复 | schema v3 覆盖书架/分组、书源/仓库/RSS、净化规则、RSS 状态、阅读偏好，恢复失败回滚 |
| 20 | 搜索默认不精准 | 已修复 | `DiscoverViewModel.matchMode = .exact`，可切换模糊并按相关度排序 |
| 21 | 智能网页小说模式不清晰 | 已收口，待真机 | WKWebView 预览 + 提取正文说明、失败状态和返回网页入口 |
| 22 | 搜书结果混乱 | 已收口 | 规范化关键词、同源去重、精准/模糊分层、相关度排序、按书源分组、失败源折叠 |
| 23 | 发现顶部找书/订阅/写源重复 | 已修复 | 发现页只保留搜索与智能网页阅读；RSS/写源从对应管理入口进入 |

## 本阶段验证门

### Windows 静态门

```powershell
git diff --check
node ci-log/extract-prelude.js
node --check ci-log/js-prelude-check.js
```

### GitHub Actions 门

- `.github/workflows/ios.yml`：XcodeGen、iOS 编译和 XCTest。
- `.github/workflows/unsigned-ipa.yml`：unsigned IPA 产物。

### 真机门

- iPhone ProMotion 设备上用 Instruments Core Animation/Animation Hitches 检查阅读器拖动、分页、RSS 滚动和主题切换。
- 记录设备、系统、屏幕刷新率、平均/峰值帧率、hitch 数和内存峰值；CI 只证明可编译和测试，不证明持续 120 FPS。

