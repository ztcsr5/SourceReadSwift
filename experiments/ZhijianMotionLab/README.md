# 纸间 · 动效实验 0.1

独立 Bundle ID `com.edc21.ZhijianMotionLab`，iOS 16+，与正式纸间并存；不读取其书架、书源、凭据、进度或偏好。无网络依赖、权限申请或第三方运行库。借鉴 REX 录屏的景深/节奏/空间关系，所有 UI 代码重新实现，没有导入 REX 安装包资源、商标、着色器或私有代码。先看 `docs/STATUS.md` 的原生验证状态。

## 安装 / 运行
macOS 安装 Xcode 与 XcodeGen，在本目录运行 `xcodegen generate`，打开生成的 `ZhijianMotionLab.xcodeproj`。选择 `ZhijianMotionLab` scheme 和 iPhone 模拟器；真机签名使用自己的 Team。启动后五步序章：景深书海、书架重排、藏书票、资源环绕、海报入口。可跳过，首页右上角或实验设置可回放；首页左右切换海报、查看简介、试读、保存段落书笺。

## 测试
`xcodebuild -project ZhijianMotionLab.xcodeproj -scheme ZhijianMotionLab -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO test`。CI 会选实际可用的 iOS 26 模拟器，测试数据隔离/持久化/空态/边界、320/390 窄屏截图与真实点击流程，并导出约 28 秒引导到首页录屏。`--lab-tour` 仅在显式传入时驱动录屏演示，不对普通启动自动翻页。普通启动状态持久化，阅读位置需在段落下明确“记到这里”，不是正式阅读器自动锚点。

## 发布 / 退出实验
独立 `.github/workflows/motion-lab.yml` 构建测试 IPA（未签名），不改变正式版 CI 或版本号。需要签名侧载。卸载“纸间·动效实验”即可完全退出，正式纸间不受影响。本工程是视觉实验，不提供真实书源搜索、漫画引擎、TTS、用户统计或跨导航封面 Hero 的完成声明。
