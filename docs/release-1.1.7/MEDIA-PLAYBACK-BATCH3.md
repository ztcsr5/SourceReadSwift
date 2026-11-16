# 第三批：视频、有声书和小说 TTS

## 边界与当前状态

- 沿用唯一开发线 `codex/next-from-build150`、私有仓库及 JSON 书源。漫画入口补正提交为 `1fdcf946`；第二批专项不能证明本批已通过。
- `99a7fa287a5e5185e94c3993fbbfd49429f29b22` 已通过媒体原生专项与同 SHA 的设备 IPA 构建；这不是四批完整回归交付。四批完成后再集中跑 `ios.yml` 和最终 IPA；不声称模拟器证明 120 Hz。
- 本文另列 `99a7fa28` 之后的工作区收尾改动，其新增 seek 校验尚未跑原生测试，不能借用前一提交的绿灯证明通过。

## 实现

- `VideoPlaybackSession` 独立管理 AVPlayer、剧集请求、有效时长后续播、请求代际、观察者清理、进度持久化及锁屏控制。
- `NativeVideoPlayerView` 使用公开 AVPlayerViewController，启用原生播放控件和画中画。独立剧集目录、连播、画面比例和锁定入口；全屏和画中画进入期间保留播放会话，失败或退出时复位标记。控件实际可用项仍受系统和设备支持限制。
- `MediaStreamRequest` 保留播放 URL 的书源指令及请求上下文，大小写不敏感地合并请求头；剔除非法字段与连接 framing 字段。继续使用既有 AVURLAsset 请求头兼容选项，HLS 子请求与外站防盗链仍需真实书源验收。
- `MediaPlaybackOwnership` 在主线程交接视频、有声书及小说 TTS；被替代的播放器只能释放自己的锁屏回调与记录。TTS 的段落数量不再伪装为音频秒数。
- 有声书恢复和书签使用章节的持久化 index，避免稀疏目录被当成数组下标；同一本书重新打开播放器不重启正在播放的章节，缓冲、失败和重试具备可见状态。
- 语音设置默认展示系统/讯飞/HTTP 文字合成；原录音包作为明确的兼容功能保留，避免把导入 MP3 当成 TTS。

## 验证

- `MediaStreamRequestTests` 覆盖包含空格的请求指令、签名查询、请求头覆盖和非法地址。
- `VideoPlaybackSessionTests` 使用仓库自己生成的 24 秒 H.264/AAC 文件验证真实 AVPlayer 续播、暂停、同播放器切集和旧完成通知；另测取消后迟到规则响应与旧朗读对象不清掉新播放记录。
- `AudioBookPlaybackCoordinatorTests` 增加稀疏目录和播放控制交接时取消旧加载。
- `.github/workflows/media-playback.yml` 是本批 macOS / iOS 26 专项，不以 Windows parser 检查代替编译。

### 首次原生构建与修正

- `5b11b8ef` 的媒体专项 `43852632813` 和设备构建 `43852632550` 均未通过：`NativeVideoPlayerView.swift:190/201/205` 的 AVKit 回调越过 MainActor 修改播放状态，测试尚未执行。
- 将非隔离回调中的状态写入显式切回 MainActor，保留回调完成/取消语义；随后修正横竖屏渲染测试，将 UIWindow 挂入实际 UIWindowScene，而非脱离应用场景创建空窗口。以下是这些修正之后的实际结果。

### 已完成的原生验证：99a7fa28

| 工作流 | Run / Job | 结果与范围 |
| --- | --- | --- |
| Media Playback Focus | [43855298636](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43855298636) / `133257916348` | success；62 XCTest、0 failures，日志未报告跳过；真实 AVPlayer 续播、暂停、换集、迟到回调隔离、取消、音视频/TTS 所有权及解析测试 |
| unsigned-ipa.yml | [43855298631](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43855298631) / `133257915919` | success；设备构建、IPA 打包、编译后的备选图标校验及符号归档完成 |

- 媒体证据 artifact：`14221412083`，名称 `media-playback-99a7fa287a5e5185e94c3993fbbfd49429f29b22-attempt1`。已下载归档 `F:/SourceReadSwift/batches-20261116/media/99a7fa28/media-native.zip`，6,191,644 字节，SHA-256 `874962f1d8b21daf71b3f1b3e1b16e1fe0a958d3d8a69095072004356d0414df`。
- `media-tests.log` 的 Selected tests 汇总为 62 tests / 0 failures。横竖屏附件分别是 `AF9D8A5F-AEDD-4DAB-BC99-5F6F7F0F4E7C.png` 和 `C37DC86F-46CC-4F6C-90B9-3A8637C116CC.png`，原始文件保留；按仓库规则生成小于 1 MiB 的模型预览后完成目视检查。
- 在 390 × 844 竖屏和 844 × 390 横屏测试窗口中，实际测试视频可见，宽高比正确、留黑正常，标题、剧集目录和更多入口布局完整。AVKit 播放控件在截图中已自动隐藏；`showsPlaybackControls == true` 的断言不能替代实际点击全屏、画中画或输出设备按钮。
- IPA artifact 为 `14219584106`（`SourceReadSwift-unsigned-ipa`，30,527,307 字节）；此处记录工作流产物元信息，未把它当作新工作区改动的构建结果。

### 原生绿灯后的收尾：待最终 SHA 再验证

- `SourceReadSwift/Core/Audio/VideoPlaybackSession.swift`：周期进度回调在 MainActor 任务真正执行时读取 `player.currentTime()`，并校验请求代际和当前 item，避免已排队的旧时间戳在 seek 完成后覆盖新位置。
- `SourceReadSwiftTests/VideoPlaybackSessionTests.swift`：真实视频用例增加暂停后 seek 到 18 秒的验证，同时检查会话与 AVPlayer 时钟，并在 1 秒观察期内断言进度不退回 17.9 秒之前；保留原有换集和旧结束通知断言。此新增断言尚未在 Xcode 上执行。
- 删除 `SourceReadSwift/Features/Reader/VideoPlayerView.swift` 中已无调用的 `LegacyVideoPlayerView`。删除前全局搜索仅剩旧类型声明；书籍详情和书架入口仍调用 `NativeVideoPlayerView.swift` 定义的 `VideoPlayerView`。未更改这些入口或 JSON 书源协议。
- Windows 收尾检查：`python -B -X utf8 -m unittest discover -s scripts -p "test_*.py" -q` 实际通过 216 项；`python -B -X utf8 scripts/audit_swift_name_shadowing.py` 输出 `shadow findings: 0`；`git diff --check` 通过。针对上述两个 Swift 文件使用仓库 `audit_current_swift_syntax.diagnostics` 与 HEAD 对照，均为 0 个新增 parser 诊断，未改写共享 `CURRENT-SYNTAX.json`。
- 下一原生门禁：提交后重新运行 `.github/workflows/media-playback.yml`，或在最终完整 XCTest 中执行上述测试。当前这些收尾改动不能标记为已完成 Xcode 验收。

### 待真机或真实书源验收

- 全屏进入/返回、画中画启动/失败/恢复、输出设备选择、锁屏和后台切换；模拟器截图不覆盖这些操作。
- 带请求头、重定向及 HLS 子请求的真实 JSON 音视频书源；本轮原生播放使用仓库自制测试视频，并未证明所有外站防盗链可用。
- 真机掉帧、音频连续性与刷新率；本轮不提供 120 Hz 保证。

## 回滚与后续

本批独立提交可逐个 revert，无数据迁移或书源格式变更。第四批仍待完成：更多翻页、文本选择入口、开合书转场、启动过渡及取消阅读时长打扰；不得因本批交付遗漏。
