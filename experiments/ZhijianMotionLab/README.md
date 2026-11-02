# 纸间 · 视频对照测试 0.1 / build 2

独立 Bundle ID `com.edc21.ZhijianMotionLab`，iOS 16+，与正式纸间并存。用户否决首版原创海报和自由创作方向；build 2 改为逐镜对照 REX 视频的六段结构、电影票和影视主页。被否决的生成海报已经从资源包移除。无网络请求、账号、权限申请、第三方运行库或 REX 可执行代码。参考图片取自用户提供且已授权静态 UI 研究的 IPA，清单与哈希见 `docs/REFERENCE-ASSETS.json`，不能据此认定取得正式分发许可。

## 安装 / 运行
macOS 安装 Xcode 和 XcodeGen，在本目录运行 `xcodegen generate`，打开生成的 `ZhijianMotionLab.xcodeproj`。选择同名 scheme 和 iPhone 模拟器；真机签名使用自己的 Team。启动依次是悬浮海报、模块预览、电影票、追更卡、资源环绕、统计卡流；可以跳过，设置中可以重播。主页可左右切海报、查看简介、加入/移除待看、搜索离线片目。素材是包内快照，非实时榜单，不提供播放。

## 测试
`xcodebuild -project ZhijianMotionLab.xcodeproj -scheme ZhijianMotionLab -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO test`。CI 实际验证 Apple SDK 编译、独立持久化、24 部片目资源、320/390 宽度六场景、真实点击及录屏。`--lab-tour` 仅显式传入时驱动录屏演示，不影响普通手动流程。统计示例不代表用户观看记录，资源页保持真实空态。尚未对齐到逐像素/逐帧一致，不宣称 60/120 FPS；首页目前使用包内“辐射”等真实片图，不是视频末尾联网列表中更新后的“德里镇”。

## 发布 / 退出实验
独立 `.github/workflows/motion-lab.yml` 构建未签名测试 IPA，需要自行签名侧载。素材只用于私人视觉对照，不合入正式纸间。卸载“纸间·动效实验”即可退出，正式纸间不受影响。原有阅读试验组件保留但不作为当前影视界面的入口。
