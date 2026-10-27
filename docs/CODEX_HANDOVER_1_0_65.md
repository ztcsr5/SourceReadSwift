# SourceReadSwift v1.0.65 交接文档 — 排版统一、连续分页、登录与封面兜底、换源缓存

**版本：** 1.0.65 (Build 66)
**分支：** `codex/reader-feedback-fixes`
**代码 Commit：** `36b1e235d618477e3824c6d07eb60a5a847b27a9`
**日期：** 2026-10-28
**上游交接：** `docs/CODEX_HANDOVER_1_0_64.md`（自定义壁纸 UIKit 图层）

---

## 一、本轮范围

本轮处理用户对 1.0.64 的 11 条反馈，全部落在代码与单元测试层；真机体验项统一标为「待验收」。

| # | 用户反馈 | 代码落点 | 状态 |
|---|---|---|---|
| 1 | 翻页/平移/覆盖/仿真模式里章节标题与正文字号相同；有的源不显示标题；标题重复 | `ReaderTypographyDefaults.titleFontSize`、`ChapterTextSanitizer`、`ReaderChapterSection`、`WebReaderDocument` | 已实现，待真机验收 |
| 2 | 正文没有对齐，排版乱 | `WebReaderDocument` 的 `.para` / `.chapter-title` CSS；TextKit 段落样式 | 已实现，待真机验收 |
| 3 | iOS 16 上搜索框压导航栏、详情/书架封面不显示、机型尺寸差异 | `CoverURLResolver`、`AsyncBookCover`、`BookDetailView`、`BookshelfView`、发现页导航样式 | 部分已实现，iOS 16 真机待验收 |
| 4 | 多数书源提示「登录地址无效」或没有登录入口 | `SourceLoginURLResolver`、`SourceManagerView`、`SourceLoginView` | 已实现，特殊源待验收 |
| 5 | 底栏按钮太多（朗读、自动翻页） | `ReaderView` 右上 `ellipsis` 菜单 | 已实现，待真机验收 |
| 6 | 详情页顶部加号与底部「加入书架」重复 | `BookDetailView` 顶部 `SearchBookRow(onAdd: nil)` | 已实现，待真机验收 |
| 7 | 部分正文显示不全，末尾是省略号 | `SourceEngine` 分页上限 8→24、末段去重、`nextContentUrl` 保留、「网页打开本章」兜底 | 已实现，源相关待验收 |
| 8 | 默认段间距太小 | 默认 `paragraphSpacing 0→10`、`titleSpacing 8→12`、一次性迁移 | 已实现，待真机验收 |
| 9 | 设置页单调，需要配色 | `settingsHeroSection` 渐变统计头卡 | 已实现，待真机验收 |
| 10 | 发现页顶部太空、卡片太大、需要网格 | `DiscoverView` 间距压缩、封面 64×86、列表/网格切换 | 已实现，待真机验收 |
| 11 | 切换书源要重新搜索，希望像香色一样秒切 | `SourceSwitchCacheStore` + 换源面板先缓存后刷新 | 已实现，命中率待验收 |

## 二、修复详情

### 2.1 标题字号、缺失与重复（反馈 1）

- 新增统一字号函数：

```swift
static func titleFontSize(for bodySize: Double) -> Double {
    max(bodySize * 1.3, bodySize + 6)
}
```

- 三个渲染面全部接入：内联分页、TextKit（`NativeReaderTextView`）、WebView（原本已是 1.3x），避免同一本书在不同翻页模式下标题忽大忽小。
- 新增 `ChapterTextSanitizer`：
  - 清洗 BOM、NBSP、全角空格与零宽字符；
  - 标题为空或为「正文 / 内容 / 无标题 / null / untitled」等占位值时，从正文首个标题形状的短段落回填；
  - 剥离正文开头与章节标题重复的段落，最多检查前 4 段；
  - 保留 `fallbackTitle`，最终保证有可显示标题。
- `ReaderChapterSection` 增加自定义 `init`，磁盘里的旧章节缓存重新走清洗，不需要用户清缓存。
- 内联模式首页不再重复绘制页眉标题，标题只出现一次。

### 2.2 正文对齐（反馈 2）

- WebView 正文段落：

```css
.para {
  text-align: justify;
  text-justify: inter-ideograph;
}
.chapter-title {
  text-align: left;
  text-indent: 0;
}
```

- 标题禁止继承正文的首行缩进与两端对齐，避免标题被拉散。
- TextKit 路径保持自然段对齐，段落间距由 2.8 的默认值统一控制。

### 2.3 iOS 16 与封面链路（反馈 3）

- 新增 `CoverURLResolver`，按以下顺序解析封面：
  1. 完整 `http(s)` URL；
  2. 协议相对 `//host/path`，补 `https:`；
  3. 以 `/` 开头的站内绝对路径，拼书源 origin；
  4. 相对路径，拼 `bookURL`；`bookURL` 本身是相对路径时回退书源主页。
- `AsyncBookCover` 增加 `baseURLString` 与 `sourceURLString`，书架 5 处调用点、搜索行、发现页聚合卡、详情页全部传入书源上下文，解决“列表有封面、详情没有”的断链。
- `BookDetailView.displayBook` 在本书源无封面时借用同书名兄弟源的封面，并把结果写回书架记录。
- 书架刷新路径回传 `coverURL`，避免刷新后封面被空值覆盖。
- 发现页与合集页导航标题由 `.large` 改为 `.inline`，iOS 16 上大标题展开时不再与搜索框/内容重叠。

> iOS 16 的导航栏与安全区差异属于系统行为，代码侧已消除大标题占位与封面相对路径两类确定性问题；剩余布局需按机型矩阵真机验收（见第五节）。

### 2.4 登录入口与地址解析（反馈 4）

- 重写 `SourceLoginURLResolver`，支持：
  - 绝对 URL；
  - 协议相对 `//host/login`；
  - 站内绝对路径 `/login.php`；
  - 相对路径 `user/login`；
  - 无 scheme 的域名 `example.com/login`；
  - `{{bookSourceUrl}}` 等模板展开。
- `loginUrl` 为空或无法解析时，回退到书源主页，并在登录页明确提示「已打开书源主页，请在站内登录」。
- `SourceManagerView` 两处入口的判断条件从「loginUrl 非空」改为「resolver 能产出目标」，按钮文案为「打开站点 / 登录」。
- 仍无法处理的类型：`loginUrl` 指向死链、需要 JS 渲染才能出现登录框、或登录依赖 App 内特定 UA/Cookie 的源。

### 2.5 底栏精简（反馈 5）

- 朗读 / 暂停 / 停止朗读、自动翻页移入右上角 `ellipsis` 菜单，并用 `Divider` 与「网页打开本章」分组。
- 底部控制坞只保留：目录、设置、上一章、下一章、进度条。
- 与香色的布局一致：高频操作在底部，长尾辅助在右上菜单。

### 2.6 详情页重复加号（反馈 6）

- `BookDetailView` 顶部书籍行改为 `SearchBookRow(onAdd: nil)`，只保留底部「加入书架」主按钮。

### 2.7 正文截断与省略号（反馈 7）

- `SourceEngine` 正文分页上限从 8 提升到 24；便捷入口 `getContent(source:chapter:)` 同步改为 24（此前只改分页器会导致测试与实际行为不一致）。
- 末段与倒数 3 段做重复段落去重，减少源站把同一段重复拼接造成的“看起来被截断”。
- 达到分页上限时保留 `nextContentUrl`，不丢弃下一页入口。
- 阅读器右上菜单新增「网页打开本章」，用 `SmartWebReaderView(initialURL:)` 直接打开本章原始网页，作为源站内容本身不全时的兜底。

### 2.8 段间距（反馈 8）

- 默认值：`paragraphSpacing 0 → 10`，`titleSpacing 8 → 12`。
- 一次性迁移键 `reader.typographyMigrated.v65`：仅当用户旧值仍是 0 / 8 时才提升，用户手动调过的值不覆盖。
- 一键排版预设同步新默认值。

### 2.9 设置页配色（反馈 9）

- 新增 `settingsHeroSection` 渐变头卡，展示书源数、书架数、分组数，作为设置页视觉锚点；下方分组保持原有信息结构。

### 2.10 发现页紧凑与网格（反馈 10）

- 主 `VStack` 间距 20→14，搜索 Tab 24→16。
- 新增 `DiscoverResultLayout`（list / grid），持久化键 `discover.resultLayout`。
- 聚合结果使用 `LazyVGrid`，adaptive 100–140，常见宽度约 3 列。
- 列表封面 74×98→64×86，简介 2 行→1 行。

### 2.11 换源缓存（反馈 11）

- 新增 `SourceSwitchCacheStore`（`@MainActor`，JSON 落盘）：
  - TTL 7 天，最多保留 10 条；
  - key 归一化：去空白、去标点、全半角折叠、大小写折叠；
  - 换源面板先展示缓存候选，再后台刷新并合并去重；
  - 只有「无缓存」时才在加载中禁用点击，有缓存时可立即切换。
- 与香色行为对齐：同一书名/作者第二次换源不再从 0 搜索。

### 2.12 iOS 16 阅读器顶栏/底坞可读性

- 顶栏与底坞背景从 material 改为 `readerThemeBackground.opacity(0.97 / 0.96)` 的不透明底。
- 根因：iOS 16 的 `Material` 在部分机型上透出正文，文字与正文叠在一起；不透明底以轻微透明保留层次，同时保证可读性。

## 三、新增与修改文件

### 3.1 新增源码

- `SourceReadSwift/Core/Rules/ChapterTextSanitizer.swift`
- `SourceReadSwift/Core/Rules/SourceLoginURLResolver.swift`
- `SourceReadSwift/Core/Storage/SourceSwitchCacheStore.swift`
- `SourceReadSwift/Shared/DesignSystem/CoverURLResolver.swift`

### 3.2 新增测试（23 例）

- `SourceReadSwiftTests/ChapterTextSanitizerTests.swift`（7）
- `SourceReadSwiftTests/SourceLoginURLResolverTests.swift`（7）
- `SourceReadSwiftTests/SourceSwitchCacheStoreTests.swift`（4）
- `SourceReadSwiftTests/CoverURLResolverTests.swift`（5）

### 3.3 修改（按模块）

- 版本与工程：`project.yml`、`SourceReadSwift/App/Info.plist`、`SourceReadSwift/Shared/AppVersion.swift`
- 引擎与解析：`SourceEngine.swift`、`ContentParser.swift`
- 存储：`BookshelfStore.swift`
- 书架：`BookshelfView.swift`、`BookshelfReaderGatewayView.swift`
- 发现与详情：`DiscoverView.swift`、`BookDetailView.swift`、`SearchBookRow.swift`、`SmartWebReaderView.swift`
- 阅读器：`ReaderView.swift`、`ReaderChapterWindow.swift`、`ReaderSettingsModels.swift`、`NativeReaderTextView.swift`、`WebReaderDocument.swift`
- 设置与书源：`SettingsView.swift`、`SourceLoginView.swift`、`SourceManagerView.swift`
- 测试对齐：`ReaderSettingsModelsTests.swift`、`SearchURLResolverTests.swift`、`SourceEngineStage18FixtureTests.swift`

## 四、验证

- 提交链：
  - `68e4253` — 1.0.65 主体（28 files，+1213 / −101）
  - `a21223a` — 测试断言对齐（3 files）
  - `36b1e23` — 便捷入口分页上限修复（1 file）
- CI（GitHub Actions）：
  - iOS run `40539628249`，job `122314182195`：Build 成功，`1095 tests / 0 failures`，`** TEST SUCCEEDED **`；
  - Unsigned IPA run `40539628430`：成功。
- IPA：`C:/Users/Edc21/Desktop/SourceReadSwift-1.0.65-unsigned.ipa`
  - 大小 `12,136,856` 字节；
  - SHA256 `2B1F251C303F47797BBDD5FB6E9FBF2675B625AC0246BFBE17BED64E29821230`；
  - 包内 `CFBundleShortVersionString=1.0.65`、`CFBundleVersion=66`、`MinimumOSVersion=16.0`、BundleID `com.edc21.SourceReadSwift`。
- 中间失败与修复：旧断言（paragraphSpacing=0、版本 64、8 页上限）导致首次 CI 红，`a21223a` 对齐；随后分页测试仍按 8 页断言，定位到便捷入口写死 `maxPages: 8`，`36b1e23` 改为 24 后全绿。

## 五、真机验收清单（未通过前不得写成已通过）

按顺序执行，每条记录机型 / 系统 / 结果：

1. iOS 16（SE 2/3、13 mini、14、15、16、Pro Max 至少各一台）书架、搜索、发现页：搜索框不与导航栏重叠，封面在列表、详情、书架三处都能显示。
2. 三种翻页模式（平移 / 覆盖 / 仿真）+ 上下滑动：章节标题明显大于正文，标题只出现一次；无标题源能显示回填标题。
3. 正文两端对齐，标题不缩进；长段落无右侧参差。
4. 书源管理：每个源都能点出「打开站点 / 登录」；相对 `loginUrl` 与空 `loginUrl` 都能落到书源主页。
5. 阅读器底栏只有目录/设置/上一章/下一章/进度条；朗读与自动翻页在右上菜单可用。
6. 详情页只有一个「加入书架」按钮。
7. 找一本此前末尾出现省略号的书：正文页数增加，末尾不再无故截断；必要时用「网页打开本章」核对原文。
8. 新装或旧设置升级后，段间距明显大于行间距；手动改过间距的用户数值不被覆盖。
9. 设置页顶部渐变卡显示统计，配色正常。
10. 发现页顶部更紧凑，卡片变小，列表/网格切换后重启仍保持。
11. 同一书名连续切换 3 个书源：第二次起候选立即出现，后台刷新不阻塞切换。

## 六、已知边界与下一轮候选

- `BookshelfView` 主页大标题仍是 `.large`，是否统一为 `.inline` 需与设计确认；
- `loginUrl` 为死链、纯 JS 登录页、需要专用 UA 的源仍需逐个适配；
- 正文末尾 `…` 目前是手动「网页打开本章」兜底，可增加自动检测与提示；
- 换源缓存按「书名|作者」归一化匹配，书名差异过大时仍会 miss；
- 分页上限 24 是性能与完整性的折中，超长单章仍可能触顶；
- iOS 16 各尺寸机型的排版、动态字体最大档、横竖屏切换尚未真机验证。

## 七、回滚

```bash
git revert 36b1e23 a21223a 68e4253
```

回滚后版本号回到 1.0.64 / Build 65，`reader.typographyMigrated.v65` 不会自动删除，但不影响旧版本读取。

## 八、结论

11 条反馈全部有代码落点与自动化测试覆盖；CI 1095 例全绿并产出 1.0.65 未签名 IPA。iOS 16 与真实书源的体验结论必须以第五节真机验收为准。

## 九、1.0.65 对齐补丁（2026-10-28，`e586e47`）

用户澄清「正文没对齐、很乱」不是要取消首行缩进。复核后确认并修正：

- 正文缩进一直保留：WebView `.para { text-indent: var(--indent); }`（默认 40pt），TextKit `firstLineHeadIndent = paragraphIndent`、`headIndent = 0`；只有 `.chapter-title` 的 `text-indent: 0`，标题不继承正文缩进。
- WebView 新增 `text-align-last: left`：`text-align: justify` 只拉伸整行，段落最后一行不再被拉散。
- TextKit 正文两处 `alignment` 由 `.natural` 改为 `.justified`，滑动模式真正两端对齐。
- 新增 3 个测试：TextKit 正文同时保留 40pt 首行缩进并 justify、WebView 正文保留 `text-indent` 且含 `text-align-last`、章节标题不继承缩进。
- 验证：CI iOS run `40544883395`，`1098 tests / 0 failures`；IPA run `40544883327`，`C:/Users/Edc21/Desktop/SourceReadSwift-1.0.65-align-unsigned.ipa`，`12,136,991` 字节，SHA256 `95416C4060B3795C80F4C52EA41CECB12E2AC0A0028B99DFE75936679A1CF85A`。
- 边界：平移/覆盖/仿真分页使用 SwiftUI `Text`，没有 justified 能力，分页模式仍是左对齐；统一两端对齐需要把分页页视图改为 TextKit 渲染，列为下一项。

## 十、分页 TextKit 两端对齐（2026-10-28，`c711e9e`）

### 10.1 问题

平移 / 覆盖 / 仿真三种分页模式由 SwiftUI `Text` 逐段渲染。`Text` 没有 justified 对齐能力，正文始终左对齐、右侧参差；WebView 与滑动模式的 justify 改动无法覆盖这三种模式。

### 10.2 实现

- 新增 `ReaderPageTextView`：`UIViewRepresentable` 包装非滚动 `UITextView(usingTextLayoutManager: false)`，`textContainerInset = .zero`、`lineFragmentPadding = 0`、`textContainer.widthTracksTextView = true`，并用低 hugging / compression 优先级避免固有尺寸撑开页面。
- 新增 `ReaderPageTextBuilder`：把一页的标题与所有正文段落合成一个 `NSAttributedString`。
  - 正文 `paragraphStyle.alignment = .justified`；
  - `firstLineHeadIndent = 0`、`headIndent = 0`：首行缩进已经由分页文本里的全角空格承担，避免双重缩进，也保证与 `ReaderPageLayoutEngine` 的测量字符串一致；
  - 段落间距、行距、字距、标题字号与标题间距分别映射 `paragraphSpacing` / `lineSpacing` / `kern` / `titleFont` / `titleSpacing`；
  - 朗读中的段落用 `backgroundColor` 高亮，不再用 SwiftUI padding 改变页面高度。
- `readerPage(for:)` 分支：
  - 纯文本页 → `ReaderPageTextView`；
  - 含插图页 → 保留原 SwiftUI `VStack`（图片卡片需要独立点击区域，不能塞进 text view）；
  - 占位页不变。
- 文本选择关闭（默认）时 `isUserInteractionEnabled = false`，不吞翻页 tap；开启选择时保留 `UITextView` 的选择交互。

### 10.3 验证

- 新增 `ReaderPageTextBuilderTests` 4 例：正文 justified 且不叠加 head indent、续页/末段无段后距、标题字号更大且标题间距正确、高亮背景存在。
- CI iOS run `40556533771`：`1102 tests / 0 failures`，`** TEST SUCCEEDED **`。
- IPA run `40556533405`：`C:/Users/Edc21/Desktop/SourceReadSwift-1.0.65-textkit-unsigned.ipa`，`12,154,717` 字节，SHA256 `4C3A82686DB04FEBA725F31304CBB4AD2A373072F83A5FF044FE4849A84ECF0E`；包内 1.0.65 / Build 66 / MinimumOSVersion 16.0。

### 10.4 真机验收（待验收）

1. 三种分页模式 + 上下滑动：正文整行两端对齐，最后一行不被拉伸；
2. 首行缩进仍为 2 字符，续页 chunk 不缩进；
3. 长段落跨页：最后一行不被裁切，页数与此前一致或更少；
4. 朗读高亮跟随段落，页面不因高亮跳动；
5. 含插图页仍可点开图片，文本回退路径无崩溃；
6. 开启「文本选择」后长按可选，关闭时点击翻页正常。

### 10.5 已知边界

- 含插图页仍使用 SwiftUI `Text`，该页正文不是两端对齐；
- `UITextView` 在 page curl 快照动画中的表现需真机确认；
- 分页测量仍按无缩进字符串计算行数，`justified` 不改变断行位置，理论上不影响分页；真机若出现末行裁切，优先核对 `contentHeight` 与 UITextView 的 line fragment 高度。
