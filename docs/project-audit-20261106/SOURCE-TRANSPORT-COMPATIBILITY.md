# 书源传输 / 花火兼容整批修复

## 改了什么

- `SourceReadSwift/Core/Network/SourceRequest.swift`、新增 `SourceRedirectPolicy.swift`：HTTP 与 HTML 跳转共用 origin（协议/主机/有效端口）校验。跨 origin 仅保留表示层请求头，去掉原站 Cookie、Authorization 和任意自定义令牌头；同源会话仍保留，目标站可使用自己的合规 Cookie。307/308 不向其他 origin 重放 POST/正文。
- 同一委托保留禁用 CFNetwork 自动跳转，但删除信任所有证书的处理。证书错误不再携原请求降级 HTTP；明确配置的 HTTP 源仍支持，连接失败时仅 GET/HEAD 允许一次 HTTPS 升级。同步脚本路径一并使用系统 TLS 验证。
- 登录 `next=https://...` 不再被畸形双域名修复器误当成跳转目标；仅修复紧贴主机的重复协议。HTML 跳转超过 10 次与 HTTP 一样明确失败，不再把中间跳转页当正文成功。
- `SourceReadSwift/Core/Storage/SourceCookieStore.swift`：Secure Cookie 只在 HTTPS 返回；显式小写 Cookie 不再被存储 Cookie 覆盖。
- `SourceReadSwift/Core/Import/HuaHuoBookSourceAdapter.swift`：复用 BookSource 容错解码，保留漫画类型、启用状态、权重、jsLib、concurrentRate、登录校验/结构化表单、自定义配置；对象形式请求头不再使整条花火源适配失败。
- 新增 `SourceRequestTransportTests.swift` 共 12 个 URLProtocol 回归；补 Cookie 2 项、花火完整配置/编码重载 1 项、真实 SourceStore 导入落盘重载 1 项。全部用 `.invalid` 和隔离会话，不访问公共站点或真实 Keychain。
- `HomeLayoutEvidenceTests.swift` 补四主题 320 pt accessibility3 滚动截图，必须到达最后书架行；异常时也销毁挂载窗口。此项补视觉证据，不改生产布局或冒充触控性能。
- iOS26 纳入新套件和精确集成用例；单测结束立即上传独立小日志，不再等设置/漫画/跨章 UI 全结束才拿到单测失败。保留全部原生门禁和操作等待上限。

## 影响面

- HTTPS 不再静默接受无效证书或降级；依赖不可信证书的旧站需要修正证书，不能据此宣称所有外站兼容。跨站令牌自动透传被禁止；若服务需要授权，应为目标 origin 配置其自己的请求/会话，不能恢复全量透传。
- 既有 Cookie 文件及书源库格式不变，无强制迁移。旧花火定义已丢失的字段无法凭空恢复，需重新导入原始定义。
- 没有修改视频解析、AI 网关、包版本或用户索引。没有发布 IPA。

## 怎么验证

```powershell
Set-Location -LiteralPath 'D:\Gemini反重力\SourceReadSwift2'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
python -B -X utf8 scripts/audit_current_swift_syntax.py 77c0e94
git diff --check
python -B -X utf8 scripts/verify_reader_quality.py status
```

- 新 Python 边界契约先 4 项失败，随后补的登录参数/HTML 超限契约也各自先失败，再修复通过；另有直接读取生产正则的 URL 行为回归。它们不替代 Swift 执行。
- 新 XCTest 尚未原生执行。Windows 环境没有 iOS SDK，tree-sitter 无新增诊断不等于 Xcode 编译。
- 本批晚于 `77c0e94`，该候选的结果不能证明这些修改通过。当前旧轮 iOS26 单测步骤失败，仍在收集后续 UI 和 iOS18 结果；未取得完整错误日志前不猜失败项。不创建重叠运行或仅取失败基线的全量快照。

## 怎么回滚

本批原件在 `F:/SourceReadSwift/project-audit-20261106/source-transport-before-merge/<原相对路径>`；首页取证原件在 `F:/SourceReadSwift/project-audit-20261106/home-scroll-evidence-before-merge/HomeLayoutEvidenceTests.swift`。只反向应用本批目标文件差异，新增策略/回归随同撤回，不整体 reset，也不覆盖接手前改动。合并为独立提交后用 `git revert <本批提交>`。

## 仍未关闭

- 新传输与导入 XCTest 的同 SHA 双系统执行、最终首页滚动截图人工检查。
- `77c0e94` 的完整错误和减少动态短侧滑、WebKit 冷启动、漫画大响应结果；当前旧轮未结束。
- 源变量删除没有安全完成：SourceStore 删除先改内存，保存失败没有事务回滚；引擎缓存状态持有持久化闭包，仅清 Keychain 会被在途任务写回。需可撤销代际和删除失败报告，不能把直接删除 Keychain 当完成。
- Cookie 读盘/写盘错误仍吞掉，损坏文件可能被之后的正常写入替换；HttpOnly 标志未在 StoredCookieRecord 重建中恢复。后续需要独立错误/恢复契约，不以本批 Secure 修复冒充全部 Cookie 生命周期已完成。
- 海阔详情/目录/正文适配、线上 11 条定义逐源链路、其余 COVERAGE pending/partial 和真机帧时间证据仍开放；静态图或显示回调不等于稳定 120 FPS。

## 收齐 77c0e94 双系统后的追加修复

- `42207479922` 已完成且失败，没有绿色 IPA 候选。两系统相同的失败为 `ReaderExitSwipeTests.swift:118` 依赖未安装，以及漫画 declared 分支 4 秒超限未结束。iOS18 的减少动态长/短侧滑失败；普通短侧滑通过。iOS26 的普通短侧滑及减少动态长/短均失败。其他设置/漫画 UI 与跨章组通过，不代表这些门禁可跳过。
- 漫画实际传输已经能拒绝无 Content-Length 的超限 chunk；仍只依赖 `expectedContentLength` 判断响应头，在声明长度夹具上遗漏拒绝。新增 `ComicImageResponsePolicy` 同时读取真实 Content-Length（含大小写、非法数字与整型溢出边界），保留原实际取消和 4 秒断言。补直接响应策略 XCTest，原生待验证，不把本地契约绿当传输验收。
- ReaderEdgeReturnWebView 原来仅在 didMoveToWindow 安装依赖。现父视图移动和布局都重试安装，避免导航祖先/手势宿主晚于窗口回调就永久漏装；不改系统 delegate。挂载用例要求完成真实布局后依赖一致，新增先建正文、后挂载窗口的回归；全部真实长/短动作及运动断言未变。它是待原生检验的生命周期修法，普通缩放模式的间歇失败仍开放，不声称唯一根因已证明。
- 当前轮长侧滑失败证据已下载到 `F:/SourceReadSwift/reader-quality-137/verification/77c0e94f2fa40ef263ebe0657c28c8a8d1f6c3bf/case-3f058001b932/SELECTED.json`；录像 7,240,513 字节，预览 260,745 字节（SHA-256 `a7146c1673df81180f2d8401e3d88cf98c12581774219b9e575384f447696ecd`），已查看。VFR 帧在 14.668→25.305 秒有大间隔，不能据此算帧率或精确还原手指中途轨迹；失败前仍正文、后面 teardown 到主屏，未获得回书架成功证据。
- 最新本地全量 `Ran 125 tests ... OK`；相对 77c0e94 的 14 个 Swift 差异文件无新增 parser 诊断，diff check 通过。新增原生回归共 18 项（传输/导入/Cookie 16 项、漫画响应策略 1 项、晚挂载 1 项），未运行。首页滚动截图也尚未生成。
- 漫画策略原件 `F:/SourceReadSwift/project-audit-20261106/comic-response-metadata-before-merge/ComicImageTransport.swift`；边缘返回挂载原件 `F:/SourceReadSwift/project-audit-20261106/edge-priority-lifecycle-before-merge/WebScrollReaderView.swift`。按目标差异回滚，不重置工作树。

## 可验证的整批回滚

已生成并执行 `git apply --check` 通过（未应用）的反向差异：`F:/SourceReadSwift/project-audit-20261106/source-transport-before-merge/ROLLBACK.patch`。只包含本轮 19 个构建/测试路径差异，保留 77c0e94 前已有工作。需要回滚时在实际仓库运行 `git apply "F:/SourceReadSwift/project-audit-20261106/source-transport-before-merge/ROLLBACK.patch"`；若后续又改了同一文件，应先重新 `--check`，不可强制覆盖。

## 提前单测日志接续：漫画取消结果顺序

- UTC 2026-11-06T12:22:34.798074+00:00；当前唯一原生候选仍为 `bea8d77309e46e8a63bc412ab7d08d1b0095cf7d`。iOS26 SDK 编译、全部新增书源传输、Secure Cookie、花火媒体/脚本落盘、漫画响应策略和侧滑晚挂载用例已通过；单测共执行 547 项，只有既有超限传输用例的 declared 分支仍有 2 个失败断言。不能称 iOS26 门禁绿。
- 提前日志 `F:/SourceReadSwift/reader-quality-137/verification/bea8d77309e46e8a63bc412ab7d08d1b0095cf7d/early-unit/native-tab-test.log`，206,032 字节，SHA-256 `381025edf8d2025d2539b7947b2962137161ccea402eb116dd2455952d7a952e`。完整设置/漫画 UI 阶段通过；跨章/手势及 iOS18 尚未结束，保持整批收齐策略。
- 工作树新增待验修法：响应头拒绝或 chunk 超限先从接收表提交 `.tooLarge`，再调用取消；此前顺序允许取消回调抢先完成 continuation。新增直接重入生产 delegate 的 XCTest，模拟取消同步回调，要求应用拒绝不能被 `.cancelled` 覆盖，且重复完成不二次恢复；原真实 URLProtocol 4 秒及 stopLoading 断言未修改。
- 该竞态修法是否解决当前 declared 超时尚未原生验证，不能宣称根因已全部确认。新回归尚未执行；没有为这一项单独派发原生。继续等本轮两系统和 UI 全结束后集中处理。
- 本地先失败的取消顺序契约已转绿；全量 `Ran 126 tests ... OK`，2 个相对当前候选的 Swift 差异文件无新增 parser 诊断，diff check 通过。这不是原生通过。
- 当前工作树已晚于候选；即便该候选其他项绿也不能用它交付当前改动。没有 VISUAL_REVIEW.json、IPA 派发或桌面文件。
