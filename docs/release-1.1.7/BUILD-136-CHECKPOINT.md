# Build 136 检查点（未交付）

- 实验分支 codex/forest-brand-136，基线 b8679786e089f9effa526c20d1675aa880172c7c；已推送 ba63dbc21e8a144a11d7daaa72063faf93b8ca98（9153c19 主题、2be805a 控件、bffd443 首页/书架、ba63dbc 实拍后的材质与裁切修正）。
- 参考图只取左书右文、微倾、书脊和纸页侧边。不复制背景、绿色标题或续读按钮；继续使用透明玻璃书台、整卡直读和独立三点。不改阅读器引擎、书源、导航架构。
- 本机 63 项 Python 回归通过，Swift 语法扫描无新增错误。旧 bffd443 专项 iOS 18：1660 单测（2 原有跳过）、12 UI 全通过；iOS 26：106 单测、12 UI 全通过。已打开实际首页、外观及寻书截图。旧综合 iOS 的 classic 详情→正文断言失败，原始日志保留；不跳过、不放宽。旧设备目标构建可核验，未送桌面。
- 当前 ba63dbc 精确 SHA 流水线：iOS 41855530595 / Floating 41855530524 / Unsigned 41855530727。等综合和专项门禁均完成，再查看最终 SHA 双运行时截图及同封面前后对照，最后核验并放桌面。
- 证据 F:/SourceReadSwift/forest-brand-136/<SHA>。已有未提交修改保持原样；无 iPhone 13 Pro 真机、LiveContainer 安装和 120Hz 结论。

## Runner 容量波动

- 41855530524 和 41855530727 首次的 3 个 job 未获 hosted runner、没有步骤，按同一 SHA 各重排一次（HTTP 201）。iOS 41855530595 的 build 同样未获 runner，native-tabs 已实际进入 iOS 26 测试；原生结束后才单独重排 regular，不取消原生。
- 原始 Checks 注解与重排响应见精确 SHA 目录 CI_RUNNER_CHECKS.json、RUNNER_RETRY_*.json。不判为产品错误或通过；没有新 IPA 上桌面。

## 第二次容量失败与备用执行器

- ba63dbc：iOS 26 主门禁 192 单测 + 5 UI 通过；首页专项 106 单测 + 12 UI 通过、32 张实拍已取回，截图包 13339444688。已看同封面前后对比，书边和落影完整，无旧卡片外侧灰雾，首屏书架仍可见。此处仅为 iOS 26 模拟器证据。
- 两次 macOS arm64 调度失败见旧 SHA 的 CI_RUNNER_CHECKS*.json。dcc371032f16c40171ceead43e33b4d12b83d1a9 仅改本分支 macOS 15 的三个 runs-on，改用 GitHub macos-15-intel；iOS 26 原生执行器、SDK、测试与 arm64 iPhoneOS 编译不变，重新验准确 SHA。63 项本地检查通过，八份原文档 SHA 未变化。
- 仍无正式验收 IPA 上桌面。截图只代表 ba63dbc 的 App 代码，不能代替 dcc3710 的完整门禁；待 iOS 18 与设备构建，以及最终 SHA 视觉复核。

## 2026-11-05 00:15（上海）

- 当前已推送 dcc371032f16c40171ceead43e33b4d12b83d1a9。精确 run：iOS 41863110314 / Floating 41863110277 / Unsigned 41863110317。API 已确认 macOS 15 的三个任务确实使用 macos-15-intel（RUNNER_LABELS.json）。最后检查五个任务仍 queued。
- GitHub 官方从 16:05 UTC 开始调查 Actions 服务异常：https://www.githubstatus.com/incidents/xr3myzj7ms51 。不把外部调度误报成产品测试结果。
- 本聊天构建验收 heartbeat sourceread-build-136 已启用；状态无变化时不发消息。只有同 SHA 门禁全绿、实拍核验、IPA 结构及符号完整性通过才上桌面；不会覆盖旧包。
- 可先看本轮 App 同封面对照 F:/SourceReadSwift/forest-brand-136/ba63dbc21e8a144a11d7daaa72063faf93b8ca98/review/Build135-vs-136-liquid-glass.png；dcc3710 与此 App 源码相同，差异仅 CI runner。

- 用户明确要桌面体验包，已单独交付旧 bffd443 的真实未签名 Build 136 PREVIEW：C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build136-bffd443-forest-brand-PREVIEW-unsigned.ipa。复核包体、UUID、复制后 SHA256；记录 IPA_PREVIEW_DESKTOP.json。此包不含 ba63dbc 的材质与裁切修正，不算最终验收；dcc3710 监控继续、旧包不覆盖。

- 用户指出 CI 未通过后再次核实：dcc3710 五个 job 均 cancelled / 0 steps，原始 check 注解已落 CURRENT_FAILURE_REVIEW.json；GitHub Actions partial_outage，暂不盲重跑。桌面预览附加说明，明确 bffd443 的综合 UI 存在正文就绪失败以及缺两项视觉修正。没有改源码、没有把预览登记为验收交付。

## 继续修复，不以基础设施故障代替产品诊断

- 当前已推送 cec1dadc94b7a472889d72116c00a54c74d01f21；新 iOS 41870297659 / Floating 41870297850 / Unsigned 41870297827，尚在队列，未声称通过。
- 原 bffd443 的综合失败现场已从 41850760988 artifact 13336434314 取回。failure-detail/B2F5F684-ED0C-487E-89E5-A674C8AE9C12.txt 显示 reader.webScrollSurface 下没有正文 AX 元素，同时显示“未能恢复阅读位置”“重试定位”。这是实际恢复错误，不是单纯 UI 查询失误。
- 74904dc 发现并修复一个可复现缺口：启动 probe 对完整空文档（无 bridge、无 content）返回0而非有界重建；生产 JS 小测试红→绿，保持 navigation.isLoading 保护、原启动重试上限、8秒超时、字符游标。新增真实 WKWebView 空文档故障注入（待 macOS 运行），原 >500/<=600 断言保留。不能认为已经证明它是那次 UI 失败的唯一原因。
- cec1dad 增加综合门禁 reader-startup.log（仅 book-passage 子系统）和正文失败截图；原12秒正文断言与全部测试选择不变，避免下次没有启动状态证据。
- 本地64项测试通过，改动Swift解析及YAML差异检查通过，8份原文档SHA未变化。修复与回归证据F:/SourceReadSwift/forest-brand-136/startup-empty-document。桌面旧PREVIEW不改名成新版本。
- sourceread-build-136 已更新到新HEAD，实际编译或测试失败需继续最小修复，不只报告后停止；纯容量故障/官方事故未恢复时不盲目重排。完成交付才删除监控。

## 构建命名（用户要求；已本地验证，暂不推送）

- 当前 HEAD 仍 cec1dad；不要为了标题取消正在执行的真实构建。
- 工作树新增本轮4个待提交文件：.github/workflows/{ios,unsigned-ipa,floating-desk}.yml 与 scripts/test_reader_controls_workflow.py。不是外部用户改动，不丢弃、不重做。原八份dirty文档未变。
- 增加 run-name：SourceRead 1.1.7 · Build 136 · IPA 未签名测试包 / iOS 完整验证 / UI 专项（无 IPA） · 流水号。保留底层 workflow.name 与 artifact.name，现有证据脚本不失效。
- 未来 IPA 名为 SourceReadSwift-1.1.7-build136-<SHA7>-unsigned.ipa，summary含Build与完整SHA，不能拿workflow运行次数当Build号。
- 新命名回归2项先红后绿，全部workflow单测6项绿；3个YAML可解析，无测试选择/时限/并发规则变化。pending-build-labels/有独立补丁和收据。等当前包和门禁收尾后独立提交命名改动，不在中途盲推导致30分钟重来；如实际产品修复必须新推送，可将命名作为独立提交一并推。

## 01:10 上海检查点（cec1dad；未最终交付）

- Unsigned41870297827成功，已下载缓存并复核CRC/plist/build136/minOS16/arm64/字体/ProMotion/匹配dSYM。25852382bytes，SHA256 bec9e47096eb66acdf84526e5b6de0a418ce0aee85c8a4f3cafcf5a8ee376b55，UUID ce022724-5168-3add-95ca-81ce6c4be952。IPA_PREVIEW_CHECK.json delivered=false；桌面未放此新包。
- iOS原生job126715210859：193单测 + 5UI，均零失败；新增完整空文档注入与原缺bridge注入两项真实WK测试通过。不是最终完整UI全绿，也不是证明旧失败唯一根因。
- 综合regular126715211199和18专项126715211147仍编译；26专项126715210348未获执行器/0步骤取消。官方Actions已经operational；需等18兄弟完成后才对该取消job同HEAD重排一次，记录响应，不取消进行中测试。
- 构建命名4个未提交文件继续保留，不因命名现在推送取消已有作业。

## 03:08 上海 · 持续执行，命名落地与标准环境对照

- 当前已推送 875317cc82b0b673c55255be401d5e8e15accafb，iOS41892279445 / Floating41892279423 / Unsigned41892279273。954e241已提交先前4个命名文件，875317c仅恢复临时Intel调度至原ARM标准执行器；App源码与cec1dad完全相同，原8份dirty文档未变。
- 该推送在此前所有任务结束后进行，没有取消仍运行的兄弟任务。当前全部标题已显示版本/Build/用途。66项本地测试绿，不改原5/12秒断言，也不增加45/15分钟门禁预算。
- cec1dad：18专项1661tests/2既有skip/0failure；UI实际“取消后再次完整返回”第264行5秒hittable断言失败，原生首次cancel END cancelled=1；第二次pop缺END。整体步骤超15分钟导致xcresult不完整，综合job被45分钟总时限中止（注解有证据），不等同测试通过。
- 原始 return-failure/desk-motion.mp4 已完整下载 CRC通过（69533930bytes），实际检查 av帧：第二次pop可见阅读器退出、源封面重现，但hittable门禁仍未通过；没有贸然改产品转场。875317c是单变量执行器对照，不把它预判为根因修复。
- 发现GitHub API在设置run-name后run.name也返回展示标题；外部collect.py改为按精确workflow.path和HEAD识别，verify_book_candidate同样按unsigned workflow path鉴别，不能再凭旧英文name漏掉新run。未改检查门槛或证据真假。
- 自动任务已更新到875317c并5分钟跟进；本聊天仍持续等待完整结果，不要求用户每次失败重新授权。只有实质修复/完成/重大失败才通知。

- 用户明确希望手测与自动回归并行以免每轮等待1小时；最新875317c体验包已独立放桌面 SourceRead-1.1.7-B136-875317c-森林绿-体验版-未签名.ipa（25852624bytes / SHA256 f73d2b6475d9fb82f588e4ee9210bcbc52f4d01f96912513d803bbcda936b4c0）。LATEST_MANUAL_PREVIEW_DELIVERY.json finalAccepted=false，附说明明确自动回归未完成及此前返回复测风险。不是旧bffd443，不覆盖旧包，不标记最终交付，自动回归继续。用户关心森林绿，输出截图必须标明主题，不将classic兼容回归误作森林主视觉。
