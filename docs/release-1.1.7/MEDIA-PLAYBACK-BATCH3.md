# 第三批：视频、有声书和小说 TTS

## 边界与当前状态

- 沿用唯一开发线 `codex/next-from-build150`、私有仓库及 JSON 书源。漫画入口补正提交为 `1fdcf946`；第二批专项不能证明本批已通过。
- 当前是原生专项候选，不是完整回归交付。四批完成后再集中跑 `ios.yml` 和最终 IPA；不声称模拟器证明 120 Hz。

## 实现

- `VideoPlaybackSession` 独立管理 AVPlayer、剧集请求、有效时长后续播、请求代际、观察者清理、进度持久化及锁屏控制。
- `NativeVideoPlayerView` 使用公开 AVPlayerViewController，保持原生播放、时间轴、全屏、画中画、倍速和输出设备控件。独立剧集目录、连播、画面比例和锁定入口；旧 VideoPlayerView 暂更名 LegacyVideoPlayerView，待新路径原生门禁后单独清理。
- `MediaStreamRequest` 保留播放 URL 的书源指令及请求上下文，大小写不敏感地合并请求头；剔除非法字段与连接 framing 字段。继续使用既有 AVURLAsset 请求头兼容选项，HLS 子请求与外站防盗链仍需真实书源验收。
- `MediaPlaybackOwnership` 在主线程交接视频、有声书及小说 TTS；被替代的播放器只能释放自己的锁屏回调与记录。TTS 的段落数量不再伪装为音频秒数。
- 有声书恢复和书签使用章节的持久化 index，避免稀疏目录被当成数组下标；同一本书重新打开播放器不重启正在播放的章节，缓冲、失败和重试具备可见状态。
- 语音设置默认展示系统/讯飞/HTTP 文字合成；原录音包作为明确的兼容功能保留，避免把导入 MP3 当成 TTS。

## 验证

- `MediaStreamRequestTests` 覆盖包含空格的请求指令、签名查询、请求头覆盖和非法地址。
- `VideoPlaybackSessionTests` 使用仓库自己生成的 24 秒 H.264/AAC 文件验证真实 AVPlayer 续播、暂停、同播放器切集和旧完成通知；另测取消后迟到规则响应与旧朗读对象不清掉新播放记录。
- `AudioBookPlaybackCoordinatorTests` 增加稀疏目录和播放控制交接时取消旧加载。
- `.github/workflows/media-playback.yml` 是本批 macOS 专项；运行编号与结果应在实际结束后补录。当前没有运行结果，不以 Windows parser 检查代替编译。

### 首次原生构建与修正

- `5b11b8ef` 的媒体专项 `43852632813` 和设备构建 `43852632550` 均未通过：`NativeVideoPlayerView.swift:190/201/205` 的 AVKit 回调越过 MainActor 修改播放状态，测试尚未执行。
- 将非隔离回调中的状态写入显式切回 MainActor，保留回调完成/取消语义。Windows 216 项脚本检查通过，1 个 Swift 文件无新增 parser 诊断、名称遮蔽 0、差异检查通过；修正版仍需独立原生验证。

## 回滚与后续

本批独立提交可逐个 revert，无数据迁移或书源格式变更。第四批仍待完成：更多翻页、文本选择入口、开合书转场、启动过渡及取消阅读时长打扰；不得因本批交付遗漏。
