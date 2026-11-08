# 音频、导出与异步生命周期接续

本页记录本轮真实读取和可复现线索；尚未取得新 SHA 全部门禁通过结果。

## 已进入生产工作树

- `AudioBookPlaybackCoordinator`：上一检查点已合并播放/停止状态、旧章节与封面回调隔离、通知令牌清理修复。`2f20592` 和 `8fee410` 都是修复前的原生失败基线；修复进入 `78e5318`，不能将这些旧失败视作修复版结果。
- JavaScript UTC 格式桥接：保留源传入的格式串和毫秒偏移；生产 JS 回放通过。不是整套聚合源兼容证明。

## 正在取失败基线

- `CloudTTSClient`：任务组虽收到超时，仍须等待未回调的接收子任务退出；取消同样可能被拖住。`CloudTTSCompletionTests` 让接收保持未完成，要求调用方先退出，然后释放夹具以避免挂住 CI。
- `CloudTTSPlayer`：停止后迟到的旧播放器 delegate 仍会触发完成/错误，可能推进新朗读会话。新增回归与上述同属 `8fee410`。
- `BookExportService`：同名导出覆盖旧分享文件、章节按缓存时间顺序输出、导出时间误用最后阅读时间、超长及控制字符文件名。3 个导出回归已进入 `8fee410`。
- `8fee410` 的 iOS 26 已得到失败基线：445 项选定单测、12 条失败断言，包含朗读取消/超时等待、旧播放器回调与全部 3 个导出回归。原日志 `job-127544132161.log` 为 1,540,317 字节，SHA-256 `0e6824f6e0e269076c66fde0792102a6aa4c960cdc2162bc7ba38eb32a2e40b2`。
- 取得上述失败基线后，`CloudTTSClient`、`CloudTTSPlayer`、`BookExportService` 已从独立副本合入工作树；合并前逐文件校验与 `8fee410` 一致，备份在 `F:/SourceReadSwift/project-audit-20261106/audio-export-before-merge`。等待后续新 SHA 验证。
- `LocalVoiceLibrary`：先删旧文件再复制；来源丢失及来源等于目标时都会丢失原音频。两个新增原生回归已写入，尚未运行。
- `AsyncTimeout`：通用超时器同样等待不响应取消的子任务；取消前已排队的操作仍可能启动。新增 4 个原生回归，尚未运行。
- `FrameRateSceneAnchor.AnchorView`：`appliedWindow` 强引用与窗口子视图关系可能形成保留环。新增窗口释放用例，尚未运行；不是已测得的所有卡顿根因。

## 其他完整读取发现

- `TTSSettingsView` 未保存预览任务，离开页面后仍可能收到音频并启动播放；本地音频导入错误被压成成功数量，清空也无法报告部分失败。
- `OfflineChapterCacheView` 的导出构建与写盘已转到后台，增加导出中/失败状态与退出后的迟到结果清理。仅按书籍 URL 分组仍可能混合不同源的同 URL 缓存，待独立修复。该文件本轮只读了离线缓存部分。
- `SourceProxyManager` 和设置页直接绑定输入，每次字符编辑都重建请求 session；缺少主机/端口验证。
- `BackgroundKeepAliveManager` 全文已读：静音保活会改写共享音频会话，停止时会尝试关闭它；到期再次申请任务不保证延长系统后台预算，异步到期回调还可能在停止后重新申请。需独立修复，不能宣称任意后台任务可无限运行。
- `SourcePipeline` 全文已读：阶段重试忽略 sleep 取消，且诊断时间转换未验证有限正数；后续需和通用超时器一并复核，不把普通阶段超时视作真实取消。
- `GlobalSearchIndex` / `GlobalSearchView` 全文已读：本机检索有 150 ms 防抖及 100 项结果上限；现阶段每次输入仍重建索引，取消不会主动中断已启动的 detached 搜索，超大书架需后续采样。

## 当前验证

- `python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'`：104 项通过（新增 CI suite 登记同步后）。
- `python -B -X utf8 scripts/audit_current_swift_syntax.py 8fee41008890fe7075021597d5212075fd18c3d4`：10 个差异 Swift 文件无新增语法诊断。这不是 SDK 类型检查。
- 菜单取消失败增加按轮次截图与 AX 层级；正文启动恢复失败增加 WebKit 状态。保留原断言和 3 / 15 秒等待预算。
- UI 未新增视觉验收；没有新 IPA，没有真机 120 FPS 结论。
- 新失败基线快照 `78e53183811d333711d9012f7a87da992befad44` 已 dispatch，包含声音导入/通用超时/窗口释放新用例及失败诊断，保留全部原套件。三项生命周期修复仅在 `pending-lifecycle` 独立副本，等待对应失败证据。

## 回滚边界

本轮新增测试和诊断改动未改用户 Git 索引。已存在修复以原副本及候选 SHA 对照；只撤销对应文件的本轮差异，不整体 reset 工作树。
