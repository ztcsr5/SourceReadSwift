# 阅读设置四项修复 · 代码验证（不打包 IPA）

## 当前结论 · 四项代码验证已完成
- 已提交并推送 `00879ecf9ac96d489515bd8d81cfcbb4da8a5b16`，同HEAD iOS run41551100902 **SUCCESS**：regular125638604761=1611unit/2原有skip/0fail+5真实UI/0fail；native125638605003=188unit/0fail+5真实UI/0fail。12项本地Python回归通过；所有16个变更源码/测试/配置/脚本与被测提交一致。
- ①设置改为以当前书名为锚的“字 / 纸 / 章”单列调校索引，移除宣言大卡、编号双列；②设置层只用局部route，自有返回/关闭与44pt完整命中区域，空白点击不穿透遮罩；③实际pop开始按owner释放底栏，取消时重获，其它owner不受影响；④设置/经典面板/菜单复用同一材质，iOS26原生玻璃，旧系统regularMaterial，纸面/壁纸/减少透明/增强对比仍尊重安全fallback。
- 已实际查看最终同HEAD regular18+native18=36张截图：白、竹、暗阅读现场，6个功能区、滑动与平移、连续两轮设置、关闭后菜单和实际回书架底栏；未见明显错路由/横溢/标题栏裁切。范围是390pt竖屏，不冒充320pt/横屏/辅助字号、真机iOS27/交互取消/帧率验收。
- 证据 `F:/SourceReadSwift/reader-controls-117/00879ecf9ac96d489515bd8d81cfcbb4da8a5b16/VERIFICATION.json`、`VISUAL_REVIEW.json`、`IMPLEMENTATION_CHANGESET.json` 和原日志；截图条目CRC/SHA已核对。源码16文件与提交一致；原有dirty文档和备份保持，不reset/stash/clean。
- **没有IPA操作**：最终HEAD仅iOS手动工作流，无Unsigned工作流、无IPA生成/下载/桌面覆盖。未改阅读引擎、书源/书架业务或首页视觉结构。首页探索/启动页仍暂停，12仍由用户手测，不访问网关。
- 复核：在仓库运行 `python -B -X utf8 scripts/reader_controls_ci.py` 应显示run41551100902双job completed/success；`python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'` 应为12项OK。Windows本地没有Xcode，SDK和真实UI通过来自上述远程Mac。
- 外观回退：使用“切换经典设置”入口一次恢复经典布局，不必撤销误返回/底栏修复；若要撤销代码，按本轮独立提交逐项revert，不reset或覆盖既有文档修改。

### 文件清单（本轮相对仓库）
- `.github/workflows/ios.yml`
- `SourceReadSwift/App/ReaderRegressionLaunch.swift`
- `SourceReadSwift/App/SourceReadSwiftApp.swift`
- `SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift`
- `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`
- `SourceReadSwift/Features/Reader/ReaderChromeEditor.swift`
- `SourceReadSwift/Features/Reader/ReaderChromeSurface.swift`
- `SourceReadSwift/Features/Reader/ReaderSettingsWorkbench.swift`
- `SourceReadSwift/Features/Reader/ReaderTabChromeExitBridge.swift`
- `SourceReadSwift/Features/Reader/ReaderView.swift`
- `SourceReadSwiftTests/ReaderControlsMaterialTests.swift`
- `SourceReadSwiftTests/ReaderTabChromeExitTests.swift`
- `SourceReadSwiftUITests/ReaderSettingsFlowUITests.swift`
- `docs/release-1.1.7/READER-CONTROLS-133.md`
- `project.yml`
- `scripts/reader_controls_ci.py`
- `scripts/test_reader_controls_workflow.py`

## 以下为复现与修复历史（以当前结论为准）

## 授权与边界
- 用户在2026-11-03明确要求开始完成四项：去模板化设置、点击误返回、返回书架底栏迟到、恢复菜单玻璃。
- 首页视觉探索仍暂停；不改书源、正文引擎、阅读位置语义，不顺手修改其他页面，不打IPA。
- 基线84a43d6；保留原有dirty文档与备份，不reset/stash/clean。

## 复现证据
- 用户7.3秒录屏：字体排版页约3.9秒短暂变全屏，4.0–4.4秒回正文；用户确认没有多余操作，第二次再开设置会退出书籍。约6.0秒已到书架、6.8秒底栏才回。
- 集成中的工坊标题/关闭栏丢失，而独立挂载截图有；既有测试使用initialRoute直接挂载，没有真实点击。
- 工坊含NavigationStack/NavigationLink，嵌在具有系统zoom、隐藏导航栏的真实阅读器；首要验证假设是设置局部导航被外层导航接管或重置，不把假设写成已证实根因。
- 工坊背景未接入ReaderChromeSurface；菜单材质选择没有实际控制工坊。旧系统fallback也是不透明纸面。这一项可直接从源码确认。

## 当前阶段
- 先补XCUITest：真实RootTabView→真实本地书架→阅读器→连续两次设置/功能区→返回，另测分页和退出后的底栏。只在DEBUG显式测试参数下使用隔离书架及内置公版书；不替换生产业务模型。
- 测试基线单独推送到codex/reader-controls-red-133，只手动运行iOS工作流的reader_settings_only；push的[skip ci]仅避免自动IPA打包，不冒充测试通过。
- 待保留基线原始结果后验证最小修复：局部显式设置路由、及时且可取消的底栏恢复、单层系统玻璃及无障碍纸面fallback；保留131栈边界。
- 本机Windows无Xcode；Swift语法分析不等于SDK编译，静态截图不等于点击/手势验收。最终需完整iOS门禁与真实集成截图，不下发IPA。

## 实施检查点（当前最高优先级）
- 当前已推送 f1c7fe25abc4a18cde606e2ba50771a39e42d411，四项代码已落地，未声明验收完成。只手动dispatch iOS完整门禁；所有push提交的[skip ci]只为不自动打IPA。独立基线abaca7e/run41529512832继续，不取消。中间候选1d0/run41531617694被最终含真实pop测试、三主题过程截图与空白点击隔离的候选替代，不冒充通过。
- 设置：移除嵌套NavigationStack/NavigationLink；显式局部route和自有返回/关闭栏。面板玻璃空白有独立点击承接，不穿透至关闭遮罩。ReaderView的设置状态仍不调用外层dismiss。
- 视觉：去掉宣言大卡、编号双列，改为字/纸/章的单列调校索引，装帧和辅助是次级行。只改阅读设置，不改正在阅读模块。
- 材质：设置和经典面板共用ReaderChromeSurface；iOS26原生玻璃，旧系统regularMaterial，减少透明/提高对比/用户选纸面或壁纸则尊重不透明fallback。Reader菜单明暗按阅读主题，不跟系统主题错配。
- 底栏：ReaderTabChromeExitBridge在实际pop开始只释放各自owner，取消时重获；原onDisappear仍是兜底。保留其它owner和131非泛型设置边界，不清空全局状态，不加延时。
- 验证：真实XCUITest从RootTabView本地书架进入正常ReaderView，连续两轮设置，覆盖6功能区、分页、玻璃空白点击与返回底栏；截图覆盖真实白/竹/黑阅读现场。另有实际UIKit pop时序、取消/重复/其它owner和实际材质像素比较。
- 已运行本地8项Python回归，全部绿；12个改动Swift解析与2YAML解析、git diff --check通过。Windows无Xcode，以上不等于SDK编译；当前SDK/UI门禁结果待读取。
- 继续命令：python -B -X utf8 scripts/reader_controls_ci.py --watch；基线加 --head abaca7e4e589d0a8e75147a3f70ff03700621e72 --branch codex/reader-controls-red-133。证据F:/SourceReadSwift/reader-controls-117/<HEAD>。任意失败保留原日志、分清产品与夹具/模拟器，再最小修复，不放宽断言；最终需实际查看ReaderSettingsFlowUITests的过程截图，不能只看独立静态图。
- 039706e之后真实pop/主题/过程截图/点击隔离已包含在当前HEAD，不要重做、回退或误认为未推送。旧dirty文档/备份保留。桌面仍只有此前已交付132/84a43d6；本轮绝不复制/打IPA。

- 当前最终完整验证run41532930645：regular125578029721/native125578030525。基线观察进程53784、最终观察进程32447（单次--watch最多20分钟，结束后按原命令续，不把观察进程结束当任务暂停）。实际过程截图提取工具F:/SourceReadSwift/reader-controls-117/scripts/read_snapshots.py，参数--head <SHA> --runtime regular|native；失败基线可加--include-failures。读取同run最新精确HEAD紧凑截图artifact，选中条目CRC/SHA、48MB总预算/5MB单次Range，产出INDEX与分组contact图。尚未跑截图提取，待结果/附件存在。

## 最新恢复点 · 测试夹具修正
- 当前已推送ab0f343ef984a48e9c3078e04d4f79e451b8392d；f1c7fe2的产品已SDK编译成功，但ReaderControlsMaterialTests:45试图写只读SwiftUI无障碍环境值导致测试编译失败。已改为UIViewController override accessibilityContrast trait，透明许可读取真实系统并断言；材质像素差>8、其它产品断言不变。不是产品测试通过，也没有放宽阈值。
- 独立基线abaca7e的native125565792134实际3UItests/2fail；失败点虽是等待面板，但已实际查看visual-native/contact.jpg，失败截图确实已回书架；原日志确认Tap reader.openSettings resolves Button then synthesizes event。因此不是仅缺AX标识的假设，不需要重做基线或回填AX来掩盖。原始UI_FAILURE.json在精确head。基线regular也失败，待读取完整首行/截图，不能笼统合并数量。
- 正在重新跑ab0f343的完整iOS门禁，不打IPA；旧f1编译失败记录保留在精确head/FAILURE.json。后续只处理实际SDK/UI失败，不再顺手新增其它功能。

## 最新恢复点 · 实际交互继续修复
- 已推送7612e8ece3bdcf8d4ab8c1f3fc81145a18b6fb68，已手动dispatch完整iOS，未打IPA。ab0结果不能说绿：regular1610项/2旧skip/4断言失败(材质1、真实pop1、WebKit冷启动2)，真实UI5项/4失败；native187项/2失败后UI受60秒和整个35分钟启动/编译/测试总预算截止，非完整验收。精确HEAD FAILURE.json保留日志哈希/原始错误。
- 实际查看17张regular原始/联系图：新路由保持面板内、真实回书架底栏一项已通过，但返回/关闭按钮点击后仍停原面板。e082fad只补header的44pt contentShape，保留原失败UI断言。734d63e补上下双色校准回归，移除CGContext垂直翻转；独立PIL对同一截图下部差22.5817、镜像区域6.188，与失败6.144对应；>8阈值不改。7612e8e以真实owner发布事件记录source未disappear，而不强迫UIKit在pop函数返回前同步开始，仍断言释放先于消失，产品bridge不改。
- WebKit失败日志为GPU冷启动42.5秒/Networking27.3秒、document无bridge且loading，在原15秒fixture预算到期；不擅改引擎和原字符范围断言，随完整门禁再验。没有修改超时/skip来掩盖任何失败。
- 继续scripts/reader_controls_ci.py；先查当前HEAD最新run，不再停在ab0。若header仍不接收，再依据原始点击坐标/真实截图定位，不盲调动画。

## 最新恢复点 · 常规门禁已绿 / 原生基础设施一次重跑
- 当前仍7612e8ece3bdcf8d4ab8c1f3fc81145a18b6fb68；run41540696869 regular125603793649已SUCCESS，1611unit/2原有skip/0fail +5真实UI/0fail；原WebKit长段回归、材质校准/差异、真实pop释放时序均绿，header hit-shape修复使两次设置访问与全部6route局部返回绿。已实际查看18张regular过程/材质图（contact1+2），白/竹/暗、滑动+平移模式、首页回根、菜单玻璃，无明显错路由/横溢。
- native125603793387在测试前编译耗尽35分钟共享step预算；boot04:24已就绪，无产品compiler error，原始754819字节job日志+41055字节artifact CRC/SHA保存NATIVE_ATTEMPT1.json。不能称原生测试通过。已对该job仅实际重跑一次POST201，收据NATIVE_RERUN.json，新job125621268157排队/运行中；不得再发重复rerun或推新HEAD取消它。常规成功/截图保留。
- 继续python -B -X utf8 scripts/reader_controls_ci.py --watch。新attempt的jobs列表可能不再直接列旧regular，原始成功日志仍是同HEAD有效证据。若基础设施再次耗尽预算，读取迁移/编译实际阶段，针对性区分build预算与产品60秒限时，不放宽产品断言；不能盲目第3次重跑。没有IPA交付，本轮桌面不变。

## 最新恢复点 · CI阶段根因修复（不再盲重跑）
- 当前已推送00879ecf9ac96d489515bd8d81cfcbb4da8a5b16，只有CI和策略测试改变，所有产品/交互代码与已全量+5UI绿的7612完全一致。手动dispatch完整iOS已204，继续scripts/reader_controls_ci.py查询最新run。
- 7612原生一次实际重跑125621268157：188unit/0fail，首个多页面UI在点击第一个装帧入口前59.56秒被继承的单测60秒总额终止（不是面板3秒等待失败）；runner恢复后heading/pageTurn真实UI分别58.93/50.69秒通过，但混合启动/编译/测试35分钟step再次到期，后面case不完整。原1195308字节日志SHAa8dd194844ae6b1c98ae8cd03c3e9a8ff67248bf68e11f0b006f3b435021319a与NATIVE_ATTEMPT2.json留存。不算完整原生通过，不再第三次盲重跑。
- 00879ec按Apple官方build-for-testing/test-without-building拆分：boot25min、compile35min、产品unit15min（每项60sec完全保留）、新UI15min（多屏总180sec），job60min。所有35个原生产品class原封保留；新UI的每次页面3/5秒、局部返回/不误退/源消失前释放的断言不改。unit/UI分别xcresult和截图子目录；artifact加run_attempt保留旧证据不冲突。不是产品性能阈值放宽，也没skip用例。4项本地CI策略先3fail后全绿，加原8项共12green；YAML/diff通过。
- 外部read_snapshots适配多个manifest和-attempt后缀，仍精确HEAD/CRC/SHA/范围下载。7612的18张regular已实际查看，00879ec需要同头最终新截图再验。无IPA，首页探索暂停，12用户手测不访问网关。
