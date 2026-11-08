# 首页、书架与主题审查 · 2026-11-06

本批按用户最新要求覆盖旧版「书台无长按」「首页标题必须宋体」约束。默认森林绿首页保留左书右文、玻璃书台与原导航。没有变更视频解析。

## 改了什么

| 需求 / 发现 | 证据 | 修改 | 验证状态 |
|---|---|---|---|
| 正在阅读恢复长按、移除右上三点 | `heroCard` 原先同时装配阅读按钮和独立 Menu，旧 UI 用例禁止长按 | 原生 `contextMenu` 承接详情、置顶、删除和书台开关；轻点入口与删除二次确认保留 | 本地契约先失败后通过；原生长按和导航返回 UI 已改为新要求，待 CI |
| 首页标题恢复系统字体 | `ReadingDeskTitleTypography` 优先 Songti，再选自带字体 | 改为调用方 Dynamic Type 尺寸的系统 semibold；不改用户正文自定义字体，也未删除字体文件 | Swift Font 等值测试已更新，待 CI |
| 书架筛选默认收起 | 搜索输入和所有类型/分组标签原先始终展开 | 在排序左侧加 44 pt 筛选按钮；折叠不清空查询、类型或分组；按钮显示是否生效 | 结构检查通过；输入→折叠→展开保留内容 UI 待 CI |
| 书架封面像贴图且尺寸大 | `ShelfBookCover` 用 fill-width 外壳，但图片 `.fit` 留白，图片和边框比例分离；网格高 145 pt | 封面、书脊、书页共用固定 2:3 外形，整本一起透视；网格高改为 120 pt，避免按整列宽度解码；真实图片依然显示 | 几何原生测试已加；图像裁切、对齐与阴影实图待 CI |
| 森林绿过深 | 旧主色 `294631`，白底对比 10.423:1；参考图中心绿色采样中位 `(45,67,44)` | 保留偏灰绿方向，提高明度到 `3D6348`；不把背景染绿；白底对比 6.825:1，饱和度略降 | 实际计算通过；真机观感待用户安装确认 |
| 本地漫画和聚合漫画筛选错误 | 原 `mediaKind(for:)` 对所有 `local://` 直接返回 nil，只按源分类 | 优先书籍 `mediaKind`，旧本地漫画按 `local://comic` 识别 `.comic`，之后才查源 | 代码检查完成；与 source agent 的媒体持久化兼容 |
| 主题只是换色 | 现有主题多数共享首页构图；许多组件固定传入圆角，掩盖主题几何 | 新增明确的首页编排、书架陈列策略和预览缩略图；全局卡片圆角按主题收敛，圆形控件保留 | 策略与表面原生测试已加；三个新编排真实 UI 截图待 CI |
| 书架重复筛选/排序 | 同次 `shelfSection` 求值分别获取数组来判空和渲染 | 一次计算后供同一视图使用；大字网格降为两列，标题用语义字体 | 代码与语法检查通过；没有宣称因此达到 120 FPS |

主要文件：

- `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`
- `SourceReadSwift/Features/Bookshelf/{ShelfBookCover,ReadingDeskTitleTypography,ForestReadingCard,ReadingHeroCard,FloatingReadingDesk,ThemedReadingCard}.swift`
- `SourceReadSwift/Shared/DesignSystem/{AppVisualTheme,AppThemeSurface}.swift`
- `SourceReadSwift/Features/Settings/AppearanceSettingsView.swift`
- `SourceReadSwiftTests/{ForestBrandThemeTests,FloatingReadingDeskTests}.swift`
- `SourceReadSwiftUITests/FloatingReadingDeskUITests.swift`
- `scripts/{test_home_presentation,test_product_quality_scope}.py`

## 主题实际差异与影响面

| 主题族 | 首页与书架 | 全局页面 / 控件 |
|---|---|---|
| 森林绿、原初白紫 | 保留原书台；森林左书右文，白紫保留原空间书台；三列小封面 | 白纸/兼容玻璃、原主题默认圆角，森林仅提升强调色明度 |
| 草木、海岸、花笺、水墨 | 仍共享书台布局，没有虚称四种全新首页 | 使用现有独立纸面插画、字体设计和装饰；水墨保留留白结构 |
| 书刊编辑室 | 左侧标题信息、右侧书封、上下分隔与章节边注 | 暖纸、小圆角墨线，内容卡片圆角不再被固定 16/18 覆盖 |
| 石墨工作台、蓝图书库 | 小封面与信息构成索引卡，书架默认列表；用户仍可切回网格 | 等宽标注、利落边框；蓝图保留坐标网格与双线 |
| 藏书票馆 | 封面居中、信息置下的藏书卡；书架默认双列票卡 | 票根缺口、竖向齿线和暖纸 |

四类首页编排已实现；并不是十种完全独立的导航系统。全局主题沿用已有 `pageBackground` / `AppThemeSurface` / `AppThemeOrnament` 路径，不重建导航或清除书架与阅读位置。自定义配色、旧主题选择、书台开关、全局搜索回调保持可用。书架网格/列表切换可以覆盖索引主题的默认列表。

## 怎么验证

已运行：

```powershell
python -B -X utf8 -m unittest discover -s scripts -p 'test_home_presentation.py'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
git diff --check
```

本批新增 3 项先红后绿；全套实际输出 `Ran 100 tests ... OK`。13 个修改/新增 Swift 文件使用已安装 tree-sitter-swift 解析，`syntax_errors: []`。这不是 iOS SDK 类型检查或原生运行。

同 SHA 原生阶段需执行：`ForestBrandThemeTests`、`FloatingReadingDeskTests`、原有 `Release116VisualTests` / `Release117AppearanceTests` / `Release117ThemeCollaborationTests` 和完整 `FloatingReadingDeskUITests`。新 UI 用例 `testCollapsedShelfFiltersPreserveQueryAndThemeLayoutsHaveRealEntries` 覆盖折叠筛选、编辑室/蓝图/藏书票入口与长按；原先 overflow 用例改名为 `testReadingDeskLongPressOffersTheSameBookActionsWithoutActivatingReader`。截图新增前缀 `floating-desk-23-`、`floating-desk-24-`。

仍需检查 320/390 pt、浅/深色、大字、减少动态效果下的真实截图，以及长按取消后轻点、返回原书架位置。设备触摸手感和持续帧时间未测，本批不报告稳定 120 FPS。

## 怎么回滚

本批未提交、未推送、未触发 CI。已存在文件的接手前备份在 `F:/SourceReadSwift/project-audit-20261106/before`，不可整体重置仓库。合并提交后使用该提交的 `git revert <commit>`；未提交状态只恢复上述文件中本批差异并保留主代理添加的全局搜索和其他既有修改。新增 `ThemedReadingCard.swift` 与 `test_home_presentation.py` 应随同反向补丁撤回。

## 双系统窄屏 / 深色 / 大字视觉复核

`928b7a3` 的 24 张原生附件在 `F:/SourceReadSwift/reader-quality-137/verification/928b7a3e86b3bc7070bb5ede99c0b87ff81b8fd9/case-752a5e219d42/SELECTED.json`。两个拼图分别为 409874 / 415441 字节，原图保留。320 pt 普通字号下封面与页缘一致、四种构图不同；390 pt 深色无白块。320 pt accessibility3 暴露索引列表作者截断、主题布局说明挤占阅读卡。已针对这两处修复，未把旧截图当作新布局验收。截图使用应用减少动态，不能证明横向分页动效或真机帧率；部分旧图封面仍处于加载占位，后续布局证据先解码本地夹具。

### e98004a 大字布局复验

`42191145785` 的两套模拟器均生成 12 张首页截图，实看了 320 pt 普通字号、390 pt 深色、320 pt accessibility3 共 24 张。四主题的封面正常显示，搜索图标跟随主题，大字卡片「全书进度」不再挤成多行；索引列表第一项已纵向布局。部分大字书架字段位于首屏下方，仍需滚动取证。两张预览分别为 405920 / 407630 字节，原件和 SHA 记录在 `F:/SourceReadSwift/reader-quality-137/verification/e98004a31bc6947b33e7c9aaa27ae9120f574431/case-752a5e219d42/SELECTED.json`。这是静态视觉复核，不证明手势或流畅度。
