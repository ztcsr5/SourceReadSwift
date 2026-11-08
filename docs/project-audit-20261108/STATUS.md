# 2026-11-08 项目审查与交付

## 当前检查点

- 用户授权：审查、修复九项体验问题、设计图标与主题、上传 GitHub、持续跟进构建、将成功 IPA 放到桌面。
- API 并发：最多主任务 + 一个子任务；不创建定时自动化。
- 工作区原先有 497 个变更/未跟踪条目，保留原改动。`BASELINE.json` 保存本轮开始的构建输入快照（211 个文件）。
- 既有最近原生运行 `42305125218`、SHA `e2f4c7ff5f8ec170e9f81dd71bde5c2f6c528fb4` 双任务通过；不能证明本轮新改动通过。
- Graphify 既有依赖图用于定位，旧行号及关系均需对照当前源码复核。

## 九项验收台账

| 项目 | 当前证据 | 状态 |
|---|---|---|
| 双底部导航 | 已移除两套栏并存路径，首轮 iOS 26 TabChromeRegressionTests 3 项通过 | UI 截图待核验 |
| 图标 | 抽象隙光四配色图标已生成，小尺寸与对比度已检查 | 编译资源通过，待 IPA |
| 开卷过渡 | 使用书名/作者/章节和纸面骨架；首轮图像工具漏绘 ScrollView | 已改真实窗口截图，待复验 |
| 滑动跨章顿感 | 真实 DOM 复现标题脱离及多余滚动；iOS 26 跨章单测 5 项通过 | 完整 UI 仍需排查 |
| 简介不全 | 修正 fallback 并保留持久化长简介；详情原生 5 项通过 | 最终截图待核验 |
| 全局主题 | 4 套双色主题及差异布局；旧精确测试清单已更新 | 新候选待验 |
| 翻页帧率 | 屏外挂载延后；原生挂载 4 项通过 | 真机 FPS 未测 |
| 返回主页冻结 | 冷目录异步、离页取消刷新；新增首次返回即搜索用例 | 正在原生手势验收 |
| 净化规则 | 验证/保存失败/回退净化/保守预设原生测试通过 | 全链完成后归档 |

## 交付门禁

当前树本地检查 → 同 SHA iOS 18/26 回归 → 同 SHA 截图检查 → device IPA 构建 → arm64/资源/dSYM/哈希核验 → 桌面副本。
明确区分单测、模拟器、真机、线上源验证。没有真机证据不承诺 120 FPS，没有逐源实测不承诺全部源可用。

## 集成检查点

- 导航/详情修复已合并，报告 NAVIGATION.md 已完成。
- 真实生产 DOM 回放复现并修复加载到章标题时替换节点与额外 scrollTo。阅读队列和翻页屏外挂载修复已合入，原生回归待跑。
- 图标与四套主题已接入，设计与对比度证据见 DESIGN.md。
- Cookie HttpOnly 磁盘恢复属性已补齐；其它持久化可靠性问题继续保留开放项。
- 交付版本校验硬编码已修，交付回归 5 项、快照回归 7 项通过。
- 全部本地检查最近一次 152 项通过；随后新加快照审查选择器测试，待最终一并重跑。
- SOURCE-INVENTORY.json 是代码清单，不标为完整逐行审查。

## 首个原生候选

- SHA：`ff0f398dd4f70793b93b491abc5ac10287700fa6`；分支 `codex/reader-quality-137-ff0f398dd4f7`；父提交为保留的本轮前工作区快照。
- Run：42398969413，https://github.com/ztcsr5/SourceReadSwift/actions/runs/42398969413 。
- 本地最终 153 项 Python 通过，44 个差异 Swift 文件无新增语法错误，diff check 通过。
- 代码/上传报告冻结；后续结果写本 STATUS，不改变待验证的构建输入。
- 本次跟踪脚本已绑定这个候选，不创建周期任务、不自动重跑失败。原生未完成，没有本轮 IPA。

- 复核提交差异发现 BookDetailView.swift 相对保留基线发生整文件 CRLF 差异；下一次必要修复快照前恢复原 LF，仅减少无关 diff，不改变逻辑。当前候选运行期间不改构建输入。

- 净化补充：多行JS保持单条、保存失败不发布内存状态、旧无效规则留存可删除；执行期限/按书或源作用域仍开放。视频仅修URL候选误选，播放器换集竞态、通知token清理及鉴权流支持作为专项问题记录。

## 原生首轮失败与后续定位

- iOS 26 首轮编译成功；607 项原生测试执行，14 个断言失败，分属 5 个测试方法（开卷2、主题2、漫画1）。源/净化/视频解析、本轮章节增量与预取/挂载回归没有失败。
- 开卷 ImageRenderer 漏绘 ScrollView 的 UIKit 内容；改用真实窗口/子控制器挂载，保留不同书不同图、相同书稳定、等待不移动标题的断言。
- 新主题精确 ID/装饰清单补齐；同时修复 peachMoss 页面无内容却创建 Canvas 的确实缺陷。
- 漫画独立 Foundation 对照：服务端完整104字节响应头、0正文、不发EOF；4秒时 responseCallback=false、taskResponse=false、expectedBytes=0。prefix与chunked正常tooLarge。下一步单变量 Content-Type/nosniff/延迟首字节实验，不改变原验收断言。
- BookDetailView 已恢复 LF；工作树现与首轮候选不同，必须生成新候选并重新通过门禁。当前旧运行继续收集 UI 结果，不作为新树通过证明。
- 本地跟进检查：153 Python tests OK，46个Swift差异文件无新增语法错误，git diff --check通过。
- Antigravity指定记录已核对：最终909fc785的IPA打包成功，但同SHA完整iOS run42391521003失败；双栏/简介问题遗留，旧漫画0字节证据不真实。外部报告 F:/SourceReadSwift/reader-quality-137/antigravity-review-58344832.md。

## 定向诊断候选 6f9df48

- 首轮完整 run42398969413 双任务失败，已保存原始日志/哈希。iOS26实际章节连续阅读和3个阅读返回case通过；失败为旧扉页、旧搜索文案、首次详情1秒predicate采样及单元组已记录项。
- iOS18另有 DetailLifecycleFixture onAppear 再次fulfill引发异常（已加首次门）、主题测试固定200ms尚未挂载Form（已改观察实际挂载/重绘）；不能提前认定为生产Bug或已修复。
- 首次详情侧滑录像20/21秒已回到完整首页，1秒predicate首轮采样与预算冲突；保持1秒上限改即时采样，附响应耗时/失败AX证据。
- 书架筛选字段独立ID filterQuery；全局按钮保持globalSearch；旧源码契约同步准确归属。直接阅读用例保留真实正文/退出/重开断言。
- 新诊断 SHA6f9df48d445a8b9e9011f846082616f992184716，run42403193700，https://github.com/ztcsr5/SourceReadSwift/actions/runs/42403193700 。仅定向诊断，不是IPA门禁。
- 派发前153 Python tests通过，48个Swift差异文件无新增语法错误。原零正文4秒tooLarge断言保留，新增MIME/nosniff/同socket1byte实验。

## 定向结果第一阶段

- 6f9df48 iOS26编译成功；ReaderOpeningTransitionTests三项、精确主题列表、主题挂载重绘均通过。详情cancel夹具发生请求启动3秒超时，实际取消断言未失败；改从原生root viewDidAppear发起导航，待新树验证。
- 漫画3种header在0body均不触发原生response；octet/nosniff释放计数1byte后12ms响应/tooLarge/关闭，png1byte仍不触发。证据不支持原系统首字节前长度契约。需要准确改为系统交付头后立即限额、未交付头按显式配置超时关闭；默认用户18/30秒不缩短。严禁伪造tooLarge。
- 首轮真实主题浅深8图、窄屏首页8图、大字首页8图已初审，无文字覆盖/底栏重复。存外部PRELIMINARY_VISUAL_REVIEW.json，不作为IPA批准。

## 第二个完整候选

- SHA714cfbb0805b55605e823b6db34027f62cd9b57a，tree d3236274f755ac2113658efe2e706b6ca4b23540，分支codex/reader-quality-137-714cfbb0805b，父仍为本轮保留基线05c751a7。源码冻结，等待双系统。
- 定向6f9df48原生UI 13项各自passed，首次详情0.7169秒恢复可点且立即打开搜索；整step在最后case后收尾超过12min，workflow仍failure，不能算整组绿。完整workflow原本按设置/连续/返回分组，无需放宽单case限制。
- 新候选包含漫画短超时配置修复与准确分离契约（系统不可见头部→超时关闭；可见超限/累计字节→tooLarge），真实PNG83byte对照；无私有API/新HTTP栈。
- 详情生命周期fixture改从原生viewDidAppear启动推入；两请求启动3秒/取消2秒原限制保留。
- 本地153Python通过，49Swift差异文件语法无新增错误，diff-check通过。最终同SHA验证/截图/IPA还未完成。

## 714cfbb 原生中间结果

- 两个job编译通过；iOS26执行611项，只有PNG响应交付实验的同一方法2条断言失败：83字节完整PNG前缀仍不足以让独立Foundation/生产交付头，不能把完整图片等同于系统缓冲阈值。原始native-tab-test.log已保存，SHA256 2aff03fa142e73704072990e262c519ffd28d0fad4687c5f4ee5ac2f12fde00f。
- 真正产品契约：三MIME零正文配置2秒超时、真实socket关闭、零缓存/订阅，显式更短请求期限、可见超限和chunked限制均通过。详情真实pop取消两请求通过；开卷/主题/跨章/翻页/净化/视频解析回归通过。
- 当前候选禁止打包，UI继续收集；诊断实验按准确计数和独立Foundation对照修订后需新同SHA完整验证。

## 用户配色纠正与图标重绘

- 用户提供四组明确双色参考并否定原斜环；改为成对使用原始色，不再混四种低饱和色。长春花蓝按明确RGB123/136/215取7B88D7。
- 已生成ICON-DIRECTIONS.png：折序/栖羽/间隙三轮廓，下方四配色，等待用户偏好；全局四主题同步校准原始装饰色与可读文字衍生色。
- 714cfbb的设置/漫画UI阶段12项全部通过；整run因原生诊断失败仍不合格，新资源和主题必须进入后续新快照。

## 双系统714cfbb收尾与设计更新

- iOS18.5主job：1869单元（2项既有skip、同PNG诊断2断言失败），34 UI全部通过；iOS26：611单元仅同诊断失败，12设置/漫画UI+9连续阅读UI+4返回UI全部通过。首次详情测试记录0.7395秒hittable，但XCTest已等待app idle，非手指离开起端到端时间。
- 漫画诊断已改同socket分段至64KiB/4秒，严格response/tooLarge/socket关闭保留，本地通过，待新原生。
- 用户新增3组配色，目前七套色彩沙龙已就绪。保持原始pair与明暗可读衍生色，17总主题全部截图测试已更新。
- 用户要求保留全部平面方向，加入P1/P2启发的曲面方案，拒绝图像API，继续本地CPU曲面渲染。偏好桃粉苔青/松针绿雾灰白/克莱因蓝艾绿，最终图标尚未选定。原AppIcon仍旧斜环，不能提交为最终资源。

## 图标优先：松雾折序微立体

- 用户要求减少并发、优先图标；本轮未启动代理或新 CI，串行处理设计与资源校验。
- 当前 AppIcon / BrandMark 已替换为用户指定的完整折序轮廓、3A6341/E8E8E4 撞色、中央局部折面阴影；上一条“仍旧斜环”已过时。全部旧预览保留。
- 新增 test_master_app_icon.py：尺寸/不透明、原始双色占比、四角满版、40/60/120 缩略双色、实际资源与重绘像素一致，共 5 项通过。修复无限阴影尾部造成远处平色暗 1 级的量化问题，阴影限定在中央边缘 64 px 内。
- 已实际查看更新后 ICON-REVIEW.png（68238 bytes）；原生语法差异检查 18 文件 failures=[]；git diff --check 无输出。未将这些本地结果视为 Xcode 或 IPA 已通过。
- 最终预览另存 ICON-FOLD-PINE-MICRODEPTH.png，当前版本的用户视觉确认和新 SHA 原生/打包仍待完成。

## 定版与最终完整验证准备

- 用户已确认松雾折序微立体作为正式图标，不再迭代造型。无新代理；保持单任务低并发。
- 定向 run42410814438 已结束 failure。漫画20项及新增主题色彩断言通过；xcresult根记录唯一问题为 HomeLayoutEvidenceTests 聚合截图超过单例60秒，并非漫画断言失败。原PNG83/256字节无响应、512字节响应/tooLarge证据已保存。
- 首页截图分为原主题4、初批沙龙4、新增沙龙3三个用例，原三显示状态与滚到底部断言全保留，新增精确覆盖/无重复检查；不增加超时时限。
- 本地159项Python通过（8.489s）。准备将定版图标、7主题与截图分组修订纳入最终完整快照；原工作区/index/基线保持不动。

## 完整候选 92c919b
- SHA 92c919b0a736f5d46b924f440e943bef1b7631d2；tree 1308ed143df1c6f64ce4b061ffd2deb290389fde；分支 codex/reader-quality-137-92c919b0a736；run 42412675736。
- 定版图标、七主题及完整首页截图分组进入同提交。源码与报告冻结，仅本状态文件后续追加进度。
- watcher 会话55383持续跟进；禁止用旧轮成功项代替本轮完整通过。

## 返回问题定向 9101666
- 完整92c919b失败：iOS18 1876单元/2既有skip/0fail、34UI仅首次详情返回1fail；iOS26 618单元全通过，12设置+9连续UI通过，返回4项仅普通动效取消1fail。未打包。
- 详情影片8.997秒已完整首页，gesture完成后8.56秒开始AX查询，两次查询至9.99秒；1.433秒计入远端查询，不能直接当App冻结。新增DEBUG进程内从交互释放到原生转场完成+根视图hitTest计时，保留<=1秒且继续真实封面/搜索可点击校验。
- 保留0.008→0.13短拖动原用例与断言，增加唯一变量终点0.20对照；DEBUG记录WK pan独立计数/位移与gesture identity，不把WK滚动计作native motion。
- 诊断SHA9101666ffef1d837574ab15b3f66b92135ff744d，tree707e3773a33ff999b9074a4eac11149863520eb6，run42463043258；两系统matrix max-parallel1。源码与提交已匹配。
- 本地160 tests passed(9.465s)，语法6变化文件无错误。日志摘要已红绿修复TEST EXECUTE FAILED与异常重启漏报。

## 用户调整交付方式：先构建 IPA，体验测试外部执行
- 用户明确要求先让 GitHub 编译/打包通过，体验测验由其他人进行。本轮停止追加 UI 回归，不删除失败用例、不伪造通过标记。
- 选用主要修复与已定版图标的完整提交92c919b0a736f5d46b924f440e943bef1b7631d2。随后9101666仅诊断相关改动不混入交付。
- 独立unsigned-ipa run42468104063，job128692232602；监视session15676。正常完整验收脚本门禁不改，新增deliver_manual_test_ipa.py仅接受指定提交显式授权记录，保留Release/arm64/元数据/字体/dSYM/hash/ZIP检查，标记full_ui_regression_passed=false。
- 授权记录已保存于该提交证据目录MANUAL_TEST_PACKAGE_AUTHORIZATION.json。

## 最终交付完成：92c919b / Build 138

- GitHub unsigned-ipa run 42468104063、package job 128692232602 均 success；完成后再次查询确认提交与状态一致。
- 桌面交付 C:/Users/Edc21/Desktop/SourceReadSwift-1.1.8-build138-92c919b-unsigned.ipa，24562734 bytes。
- SHA-256：9b2ca0b09dc36d0e97af3cc723cd17472b97a3c2350ddd676ac4df950958032c；桌面实文件复算匹配，旁附 .ipa.sha256。
- 1.1.8 / 138、arm64、iPhoneOS、最低 iOS 16；ZIP、字体/许可证、CBZ 注册、应用/dSYM UUID 已校验。实际包内图标已目视确认为用户定版松雾折序微立体。
- 校验收据：F:/SourceReadSwift/reader-quality-137/verification/92c919b0a736f5d46b924f440e943bef1b7631d2/IPA_VERIFICATION_MANUAL_TEST.json。
- 交接单：C:/Users/Edc21/Desktop/纸间-1.1.8-测试交接-92c919b.md。完整审查报告见同目录 REVIEW.md。
- 未签名、未真机安装；完整 UI workflow 42412675736 仍为 failure，两项返回行为交外部复核。用户已授权先交包；不继续派发诊断或回归，不声明全套通过。
- 9101666 诊断代码未进入本 IPA；原工作区/index 和用户修改保留。本次收尾仅新增交付记录与校验文件。

## 用户转向：优先解决连续滑动卡顿

- 暂停两个返回交互问题；用户明确要求先修章节加载/标题衔接卡顿，必要时重构滑动模式。
- 已复现章间留白锚点丢失：裁章跳22.75px、前插跳22.25px；修复后生产HTML回归偏差小于1px。
- 本轮新增原生drag/deceleration感知、非紧急章节补丁合并延后、临近末尾及时补章、滚动中延后裁窗、mounted→current章节位置映射与后台正文规范化。
- 本地40项reader Python回归通过；7个新增/变化Swift语法无新增错误。
- 候选23934f259d17fcb2ab3bbcee603f5e80024abf48，基于已交付92c919b；run42474195994，两个系统max-parallel=1。仅连续阅读专项，不运行返回手势。
- 工作区/index保持原样，snapshot由临时index与commit-tree构建。NativeBook/HomeReadiness等旧诊断文件未合入本次交付树；WebScroll中的旧DEBUG pan证据保留但不影响Release。

- 23934f2在执行测试前发现新测试JS最后表达式返回DOM元素（WK不支持），主动取消换830f3d1，未算产品失败。
- 830f3d1 iOS26编译通过；72单元仅调度用例坐标比较1失败（native600、JS跳到587后同步未等齐），实际连续跨章UI通过107.951s。锚点3项、既有滚动5项、临近尾部追加、显式跳转、进度映射均通过。
- 同步测试已改先确认JS目标与UIKit一致，保留1px断言。增加build→drag→更新的竞态用例，补书籍身份消息隔离；iOS18尚未测试时取消旧run，准备新同SHA双系统。

- 冻结更新候选565a44ecd93982f9d6293d6da29729155862b817，run42476506826，分支codex/reader-quality-137-scroll-565a44ecd939；包含书籍identity门禁、serialization中途drag用例与JS/UIKit坐标同步测试修正。旧830run已取消，没有重跑同代码碰绿。

- 565a44e run42476506826双系统全部success：各73单元0fail，真实连续跨章/重开位置UI各通过。已派发同SHA Release包。用户追加恢复主页透明玻璃+保留搜索，接续单独修改，不再排查返回交互。


## 滑动包已交付与录屏核对

- 565a44e Release run42478014693 success；桌面已保存 `SourceReadSwift-1.1.8-build138-565a44e-unsigned.ipa`，24,570,441 bytes，SHA-256 `583a31de68cab69cd08de921e4a615ebc86216a28cad5461035a2bba0404e252`。应用/dSYM UUID、arm64、iPhoneOS、ZIP、字体与CBZ注册已校验。
- 同提交滑动专项双系统各73单元与连续跨章/重开位置UI通过；不等于真机帧率已达标。桌面新增 `纸间-1.1.8-滑动修复交接-565a44e.md`。
- 两段录屏已确认：ffe8644a...蓝色益达；24defe87...白色本项目。白色视频8.600–9.333s有0.733s帧间隔，随后第7章标题入画；没有触摸/缓存日志，不能独断为缓存停顿。双方后半程切换分页，连续滑动只对照前半段。详见SCROLL-VIDEO-COMPARISON.md。
- 用户继续要求恢复主页底栏透明玻璃并保留搜索。导航专项由唯一代理继续，父提交565；进度/失败原文保存在TAB-GLASS.md。未重新排查被用户暂停的返回侧滑。

## 七组主题重做 · 2026-11-09

- 用户否定松雾重复 V 边注与笨重首页，要求主题重做。冻结 fbd9173f4066d6c1a4a739f5e24fd8cfcd4923bb，父提交9334c75；run42501448444，26→18串行。
- 去掉七组 atelier 页边/卡片装饰，改紧凑分栏阅读卡、开放书架/目录。保留原始色样、主题ID、有效导航箭头和大字体可达性；reader、forest阅读卡、RootTabView、玻璃底栏与父提交无差异。
- 本地5项保护用例通过（前三项先红后绿）；15个Swift变化文件无新增语法错误。未冒称原生编译已过。详细范围ATELIER-REDESIGN.md，证据THEME_INPUTS.json。
- 9334c75旧包是滑动+玻璃修复，不含此次新主题。下载进程当前正在串行补取symbols。
