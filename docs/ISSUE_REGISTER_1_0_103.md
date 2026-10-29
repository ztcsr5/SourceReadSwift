# SourceReadSwift 问题总表（1.0.103）

- 版本：1.0.103 / Build 104
- 分支：`codex/reader-feedback-fixes`（推送分支 `codex/swift-v2-lifetime-reader`）
- 真机基线：1.0.98/99；LAN `192.168.31.205:8080` 当前未监听（TCP 拒绝），1.0.106 复测未跑
- 当前安装包：1.0.106 基线（2026-10-29 18:16，SHA256 `35a8a31b…`）；`e41b5164d` 新包待装（iOS `40864237402` / IPA `40864237393`，1344 tests 0 failures）；问题编号沿用 1.0.103
- 状态图例：
  - `OPEN`：未修或仍能复现
  - `PARTIAL`：部分路径已改，边界仍存在
  - `FIXED?`：代码已改、CI 已过，真机未验收
  - `BLOCKED`：缺真机/服务/样本，当前无法推进
  - `DEAD`：上游站点失效，不再投入
  - `RESOLVED`：已修且有验证证据

## 一、P0 · 阅读器核心

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| R01 | 覆盖/平移/仿真三种翻页掉帧，明显不到 120Hz | FIXED? | `e41b5164d`：`CoverPageReaderView` 三槽稳定 identity，翻页改为**移动已有** `UIHostingController`（不再重建 rootView），仅排版 revision 全量重建，identity 变化清 `CATransform3D`；此前每次翻页重建 3 个 host 是卡顿主因 | 真机 `CADisplayLink` 采样对比 1.0.106；仿真仍是系统 `.pageCurl`（60Hz 设计），若要 120Hz 需自绘 |
| R02 | 翻页跳回前面的章节（第 5 章跳到第 2 章） | FIXED? | 1.0.66 用 `ReaderPageIdentity` 替代数组下标；1.0.81/83 提交后用锚点复算；`ReaderPageSelectionTests` 9 例 | 用用户视频场景回归：预取插章、覆盖 320ms 延迟、章界连续翻 |
| R03 | 不能无限前后跨章滑，读完一章要手动点下一章；预缓存不足 | FIXED? | `e41b5164d`：`BookDetailView.load(force:)` 保留 `content`，4 处回调删 `content = nil`，书级稳定 `.id("reader-\(bookID ?? sourceUrl)")`；`BookshelfReaderGatewayView` 去掉 `localNavigationRevision`；预取循环每章 `Task.yield()`。翻章不再整屏重建/整页 loading | 真机回归“读完一章继续往下翻”；跨章 5 章窗口边界复测；prefetch 命中率仍待采样 |
| R04 | 章节标题重复/缺失；标题字号与正文一样；有的源不显示标题 | PARTIAL | 1.0.65 已加 `ChapterTextSanitizer` + `titleFontSize`；1.0.103 UI 队列仍列“标题重复” | 抽 76 源逐源看标题节点；标题只渲染一次；无标题时用章节名；iOS16 单独验 |
| R05 | iOS16 双引号导致正文不对齐，最后一个字不齐；iOS17+ 正常 | FIXED? | `17c9285`：`ReaderCJKPunctuationCompression` + TextKit/WebView 末端标点压缩；`ReaderPageTextBuilderTests.swift:111` 回归用例；该提交在 `cc9b4297` 祖先链内，iOS run `40855813316` 测试通过 | 真机 iOS16 对比长段落末尾引号；若仍不齐，量 `lineFragmentPadding`/`paragraphStyle`；iOS17 回归 |
| R06 | 顶部空白太多；状态栏位置不佳 | PARTIAL | 1.0.59 已加 `.ignoresSafeArea()` 并收紧 `pageTopInset`；1.0.65 继续修 inset；用户仍反馈 | iOS16 真机量 `safeTop`、`pageTopInset`、`contentInset`；四种模式统一 |
| R07 | 正文显示不全，末尾是省略号 | PARTIAL | 1.0.65 分页上限 8→24、末段去重、保留 `nextContentUrl`、加“网页打开本章”兜底；仍与源站内容有关 | 复现具体书源；检查 `content` 规则、`nextContentUrl`、分页上限；源站本身缺字则明确标注 |
| R08 | 默认段间距太小，段距应大于行距 | FIXED? | 1.0.65 默认 `paragraphSpacing 0→10`、`titleSpacing 8→12`，带一次性迁移 | 真机看长段落/对话段；设置页可调；导出一组对照截图 |
| R09 | 自定义壁纸比例错、裁切、设置面板被裁 | PARTIAL | 1.0.63 加 frame/clipped；1.0.64 改 UIKit `UIImageView` + 降采样 + 三种填充；用户仍反馈“和前面一样” | 复现导入图片比例；固定容器尺寸；`scaleAspectFill/Fit/Fill` 三档；参考栖阅独立图层 |
| R10 | 阅读菜单太宽、留白多、不透明，与顶部菜单不一致 | FIXED? | `3e70e4d03`：`ReaderSettingsLayoutPolicy.maxPanelWidth` 统一 16pt gutter（390→358、844/1024→560、24→0）；面板底色 0.97 主题色 + 18pt 圆角 + 0.6pt 边线 + 阴影；`ReaderAutomationPolicyTests.swift:67` 宽度用例 | 真机竖屏/横屏/iPad 看宽度与留白；CI 编译测试已过 |
| R11 | 滑动模式状态栏透明，正文透出挡住 | FIXED? | `3e70e4d03`：新增 `ReaderScrollChromePolicy.statusScrimHeight`（safeTop+header+10），滚动模式顶部 0.97 实色遮罩 + 10pt 渐变；`ReaderView.swift:2800`；测试覆盖 69/93/30 | 真机滚动模式看时钟/刘海区；开/关顶部章节栏各一版 |
| R12 | 底部菜单按钮太多，朗读/自动翻页占位 | FIXED? | 1.0.65 已把朗读/自动翻页移入右上 `ellipsis`；底部只留目录/设置/上一章/下一章/进度 | 真机确认底部五项；右上菜单分组；不再新增底栏按钮 |
| R13 | 目录里选一章后继续往下翻，进不了下一章（章节衔接断裂） | FIXED? | `e41b5164d`：新增 `ReaderChapterJumpDisposition`（activate / loadIntoWindow / outOfRange）+ `ReaderPendingChapterJump`；TOC/书签/进度条跳章改走 `beginWindowJump` + `loadIntoWindow`，不再回调 owner 重建；`resumePendingContinuation` 先 resume 再 trim；`ReaderChapterWindowPolicyTests` 4 例（未加载章留在窗口、已加载章 activate、越界拒绝、pending 默认值） | 真机按用户路径复现：目录选章 → 往下翻 → 应自然进入下一章；iOS16 单独验；CI 已过 1344 tests |

## 二、P1 · 阅读交互与设置

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| I01 | 搜索时键盘不能点空白收起，只能按回车 | FIXED? | `17c9285`：`DiscoverView.swift:159` 加 `.dismissKeyboardOnTap()`；`365` 保留 onSubmit 收起；该提交在 `cc9b4297` 祖先链内，iOS run `40855813316` 测试通过 | 真机搜索页点空白/滚动/点结果三路验证；iOS16 单验 |
| I02 | 键盘弹起时导航栏跟着上移 | FIXED? | `17c9285`：`DiscoverView.swift:164` 加 `.ignoresSafeArea(.keyboard, edges: .bottom)`，只让列表避让键盘 | 真机键盘弹起/收起看顶部搜索栏是否固定；iOS16 单验 |
| I03 | 阅读页页脚/home indicator/安全区位置 | PARTIAL | 1.0.59/1.0.65 已调页脚和底部间距；用户仍反馈状态栏/页脚 | 统一 `safeAreaInsets` 基准；四种模式页脚位置一致 |
| I04 | 竞品有音量键翻页、双栏、左右独立边距、页脚三开关 | OPEN | `竞品翻页与阅读设置对照.md`：栖阅有 `VolumeButtonPageTurnMonitor`、`_doublePageMode`；香色有页脚三开关 | P1 先做音量键；P2 做双栏/左右边距；页脚开关已补，验真机 |
| I05 | 覆盖与平移视觉差异小，没有真正“上一页压住下一页”叠层 | OPEN | 1.0.84 明确“真正的叠层尚未实现” | 覆盖模式加三页叠层/方向阴影；平移保持滑动；分开验收 |
| I06 | 仿真翻页只有 60Hz，无法达到 120Hz | OPEN | 1.0.84 明确系统 `pageCurl` 按 60Hz 设计，应用层无法提高 | 接受 60Hz 并优化手感；或自绘卷页（成本高，单独立项） |

## 三、P1 · 书源引擎与解析

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| S01 | 76 源结构通过仅 8/76，正文≥500 字仅 6/76 | OPEN | `sweep76_share11_1029b.json`；旧 10 是 1.0.90 单关键词/单线程口径 | 装 1.0.103 后跑 `sweep76_v4.py`；统计 PASS4 + quality 两列 |
| S02 | 20 条空壳（原始 JSON）；rebuilt 文件 18 条 | OPEN | 20/20 与旧报告完全一致；天域/爱奇已在 rebuilt 补齐 | 统一真机库与测试输入；15 条活站逐站补规则；5 条死站标记失效 |
| S03 | 32 条搜索 FAIL | OPEN | 网络/站点 10、列表 0 项 14、JS/响应解析 3、书旗字段空 2、URL/JS 桥 3 | 先修引擎类（爱丽丝/UAA），再逐源修规则；瞬断加进 `TRANSIENT` |
| S04 | 7 条目录 0 章 | OPEN | 圣灵、含遇见、木里、日落、百度、连尚、爱下；1.0.103 覆盖木里/日落/百度/连尚 | 装 1.0.103 逐条复测；圣灵 `src` 变量、爱下 `init=$.data.book` 单独查 |
| S05 | 4 条详情未解析 | OPEN | 七猫×2、番茄 APP、STV；1.0.103 覆盖七猫、STV | 装 1.0.103 复测；番茄 APP 详情规则单独查 |
| S06 | 爱书音正文 0 字 | OPEN | 搜索/详情/目录已通，正文规则返回空 | 查 content 规则/资源类型/分页；必要时 webView 兜底 |
| S07 | 顶点小说驱动超时 | DEAD | `TimeoutError`，站点侧长期超时 | 标记失效源，不再占并发配额 |
| S08 | 3 条登录墙 401 | OPEN | 少年梦、魔丸、番茄四合一；`source.getLoginInfoMap()`/Cookie 缺失 | 做书源登录面板 + Cookie 持久化；登录后再跑搜索 |
| S09 | 书旗×2 搜索命中 11 项但 bookUrl 为空 | OPEN | `GetUrl()` 的 `Token()` 读 `shuqi_token` Cookie；旧版 1 项、新版 11 项，搜索已恢复 | 真机日志确认 Cookie 是否落盘；不要改 `getLoginHeaderMap()` 的 null 语义 |
| S10 | 14 条列表 0 项/接口变更 | OPEN | 玖玖、次元姬、蕃茄、zenneko、书山、NovelHub、聚合书源、本地番茄红果、番茄沐凡、QQ浏览器、塔读、话本、千白羽、书音FM | 逐源看响应结构；能换关键词的先换词；接口死的标记失效 |
| S11 | 5 条站点断/超时 | DEAD | 速读谷×2、错层、Icu、八叉；PC 复核 Icu/八叉 TLS reset | 52书库是瞬时超时，单独重试；其余标记失效或切备用域 |
| S12 | 1.0.103 的 8 条定向修复未真机复测 | BLOCKED | 七猫×2、爱丽丝、木里、日落、UAA、百度、连尚；LAN 当前 HTTP 0 字节 | App 切前台/重开服务后跑 `verify_named.py` |
| S13 | Legado 方言仍有边界差异 | PARTIAL | 已修：相对 URL、`source` 插值、`.length()`、`_.java`、`getElements` JSON、间接 `JSON.parse`、`@js` exploreUrl；仍有嵌套 JSON/JS 变量/加密分支 | 按 76 源失败样本补单测；优先 JSON 递归解包、JS 变量上下文、DES 分支 |
| S14 | 探针把相对 searchUrl 误判为非法 | RESOLVED | 1.0.86 `SearchURLResolver.splitURLAndDirectiveSuffix` + `SourceRequestBuilder.resolveURL`；997 条语料 URL 缺陷 19→2 | 保留回归；新增源继续跑同一探针 |
| S15 | 空壳/无 searchUrl 源没有发现页分流 | PARTIAL | 1.0.103 新增 `step=explore`；但 20 条空壳本身连 exploreUrl 都没有 | 有 exploreUrl 的源走 `PASS_EXPLORE`；无任何规则的仍按空壳处理 |

## 四、P1 · 书源数据、登录与换源

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| D01 | 没有完整的书源登录系统 | OPEN | 3 条 401；`loginUrl` 解析有了，但登录表单/Cookie/`source.getLoginInfoMap()` 不完整 | 先做 WebView 登录 + Cookie 持久化；再做 loginUi 表单；最后做 401 自动重试 |
| D02 | 空壳源需要逐站重建 | OPEN | 15 条活站，5 条死站；bqg128 需要 Cookie + webView | 先做无 JS 的：言情、天域、夜读阁、东滩、365、阅友、茶马、宝华；再做 API 型 |
| D03 | 失效源没有统一标记/降权 | OPEN | 速读谷、集书阁、顶点、Icu、八叉、番茄沐凡 | 源健康状态加 `DEAD`；搜索并发跳过；UI 标灰 |
| D04 | 切换书源要重新搜索 | FIXED? | 1.0.65 `SourceSwitchCacheStore`，换源面板先缓存后刷新 | 真机测已搜过的源是否秒切；缓存 key 用书名+作者；失效回退 |
| D05 | 真机库与测试输入不统一 | OPEN | 原始 JSON 20 空壳；rebuilt 18；sweep 测原始文件 | 固定一份 `sources-76.json` 作为唯一输入；导入/导出/体检都用它 |

## 五、P1 · 主页/发现/详情/设置

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| U01 | 主页书架比例怪、白块、左上角多余入口 | PARTIAL | 1.0.30 已删“管理”、hero 卡缩小、封面占位；用户仍觉得“书架奇怪” | 重新对首页做一次视觉稿；书架/继续阅读/推荐分区；真机 5 机型看比例 |
| U02 | 发现页顶部块太高、书卡太大、缺网格 | FIXED? | 1.0.65 压缩间距、封面 64×86、列表/网格切换 | 真机看顶部块高度；网格列数可调；小屏/大屏各一版 |
| U03 | 设置页单调，缺配色 | FIXED? | 1.0.65 渐变统计头卡 | 真机看头卡/分组；深色模式对比度 |
| U04 | 详情页顶部加号与底部“加入书架”重复 | FIXED? | 1.0.65 顶部 `SearchBookRow(onAdd: nil)` | 真机确认只剩底部主按钮 |
| U05 | iOS16 封面不显示：书架/详情/发现断链 | FIXED? | 1.0.65 `CoverURLResolver` + 5 处调用点 + 兄弟源借封面 | iOS16 真机逐页看封面；相对路径/协议相对/无 scheme 各一例 |
| U06 | “纸间”名称/文案太一般 | OPEN | 1.0.66 重写关于文案；用户仍说可以换 | 产品命名单独定；关于页保留自述，不再堆“核心特色” |
| U07 | iOS16 搜索框压导航栏/大标题重叠 | FIXED? | 1.0.65 发现/合集导航 `.large`→`.inline` | iOS16 真机看搜索框、导航栏、键盘三者关系 |

## 六、P1 · 性能与稳定性

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| P01 | 主页/书架像假 120Hz，滚动不跟手 | PARTIAL | 1.0.66 封面原图解码改缩略图；仍有首页/发现滚动反馈 | 真机 `CADisplayLink` 采样；封面统一降采样；列表行避免大图同步解码 |
| P02 | 多源搜索卡顿、超大目录崩溃 | FIXED? | 1.0.59 目录改按需 `selectedChapterForReading`；搜索防抖 0.2→0.4s；并发可调 | 真机 3000/10000 章目录各测一次；搜索 12 源并发测掉帧 |
| P03 | 滑动模式帧率不稳 | OPEN | `NativeReaderTextView` `allowsNonContiguousLayout=false`，`rebuild()` 同步 `ensureLayout`；已有 `ReaderPerf` 探针 | 真机 Debug 采 `avg/worst`；按 `读者反馈修复清单` 第六节判定；再决定拆 SwiftUI 子树或改 glyph 查询 |
| P04 | 大壁纸/长章节内存压力 | PARTIAL | 1.0.64 壁纸最长边 2800px 降采样；长章节仍有整篇布局 | 真机 Instruments 看内存峰值；长章节分块；壁纸缓存上限 |

## 七、P1 · 测试、版本与交付

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| T01 | 10 与 8 口径不一致，容易误判退化 | OPEN | 旧 1.0.90 单关键词/单线程/180s；新 1.0.98/99 五词/并发3/150s/无重试 | 统一用 `sweep76_v4.py`：重试、checkKeyWord、quality 分列、固定输入 |
| T02 | 1.0.103 未真机复测 | BLOCKED | ping `192.168.31.205` 通；TCP 8080 主动拒绝（服务未监听）；ARP MAC `0e-f9-10-72-df-90` | iPhone 打开 App 保持前台/重开服务；恢复后跑 `verify_named.py` + `sweep76_v4.py`；重点 #14/#28/#37/#51/#73 |
| T03 | iOS16 真机矩阵未跑 | BLOCKED | 只有编译级证据；SE/mini/标准/Pro/Pro Max 未覆盖 | 至少 SE2/3、13 mini、14/15 标准、Pro Max 各一台；按 `IOS16-COMPAT-AUDIT` 第七节 8 条验收 |
| T04 | LAN 服务/代理不稳定 | PARTIAL | `HTTP_PROXY` 会劫持 LAN；`sweep76_v3` 无重试；当前 App 挂起 | v4 已绕代理/重试；App 侧加 keepalive/前台提示；服务不可用时明确 `BLOCKED` |
| T05 | 桌面 IPA/版本太多，分不清最新 | RESOLVED | 1.0.103 已归档到 `E:\codex-temp\ipa-archive\SourceReadSwift-1.0.103-unsigned.ipa`（12,439,805 B，SHA256 `25aedffc…`）；桌面只剩 1.0.106 `SourceReadSwift-1.0.106-20261029-35a8a31b.ipa`（12,477,827 B，SHA256 `35a8a31b…`） | 后续文件名固定 `版本-日期-sha8`；新包只保留最近 3 个 |
| T06 | docs 提交未推送 | RESOLVED | `cc9b4297` docs 已推送；iOS run `40855813316` + IPA run `40855813405` 均 success；本次 docs 更新随验证单独推送 | 保持 docs 变更单独 push 并附 CI run |

## 八、P2 · 产品与竞品差距

| ID | 问题 | 状态 | 证据/根因 | 下一步 |
|---|---|---|---|---|
| Q01 | 书名/文案/品牌感 | OPEN | 用户明确说“纸间可以换了，文案太一般” | 单独做命名/文案；关于页保留一段自述 |
| Q02 | 竞品功能差距：双栏、音量键、左右边距、页脚开关、本地声音 | PARTIAL | 页脚开关已补；本地声音 1.0.59 已做；音量键/双栏/左右边距未做 | 按 `竞品翻页与阅读设置对照.md` 的 P1/P2 排序做 |
| Q03 | App Store/合规/隐私 | OPEN | 当前是 unsigned IPA/TrollStore 路径；未做商店审核材料 | 另开交付线：隐私清单、权限文案、崩溃收集、签名 |

## 九、建议修复顺序

### 第 1 波：阅读器 P0（先让“能看”）
1. R05 iOS16 双引号对齐 + R06 顶部空白/状态栏。
2. R04 标题重复/缺失/字号。
3. R10 菜单宽度/透明度 + R11 滚动模式状态栏透字。
4. R09 自定义壁纸比例/裁切。
5. R01/R02/R03 三种翻页手感、跳章、跨章预缓存。

### 第 2 波：书源 P1（让“有书看”）
1. 装 1.0.103，跑 `verify_named.py` + `sweep76_v4.py`，确认 8 条定向修复。
2. 书旗 Cookie、爱下/圣灵/含遇见目录、爱书音正文。
3. 20 空壳按“无 JS 优先”重建；5 死站标记失效。
4. 3 条 401 做登录面板 + Cookie。

### 第 3 波：UI/交互 P1
1. 搜索键盘收起 + 导航栏固定。
2. 主页书架比例、发现页网格、设置页配色。
3. 封面 iOS16 链路、换源缓存。

### 第 4 波：性能与竞品
1. `ReaderPerf` 真机采样，决定 TextKit/SwiftUI 优化。
2. 平移页面池/预热；仿真 60Hz 取舍。
3. 音量键、双栏、左右边距。

## 十、当前阻塞

- 1.0.103 真机复测：LAN TCP 可连，HTTP 0 字节，App 侧挂起/后台冻结。
- iOS16 真机验收：缺 SE/mini/标准/Pro/Pro Max 矩阵数据。
- 书源登录：缺登录面板与 Cookie 持久化，3 条 401 无法仅靠解析层解决。
- 空壳：20 条里有 5 条站点死，剩余 15 条需逐站写规则。
