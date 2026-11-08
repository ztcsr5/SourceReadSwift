<!-- BUILD135_CHECKPOINT_BEGIN -->
# 当前任务 · Build135 首页越界书台与原生返回（未交付）

- 当前 b8679786e089f9effa526c20d1675aa880172c7c / codex/build135-book-stage-continuity。基线 f69bd42 与既有8份修改、旧IPA原样保留。未reset/stash/clean。
- 0f99983 的 iOS / Floating / Unsigned 均绿，iOS18/26取消/完成、段落保留已验证，但视频有全屏白纸合成层缩回，不算视觉完成。保留qa/book-passage-135-0f99983。
- f584c63 证据表明：真实 UIKit ALIGN_CONFIGURED 已执行，但系统询问时 lazy 首页 UIImageView 未挂载，ALIGN_SOURCE ready=0 无 ALIGN_RECT；26 真实上下滚动用例在136行失败，日志13:55:17 BEGIN interactive=1、13:55:18 END cancelled=0（仅纵向手势），独立手势取消/完成不冒充安全。18 专项同一滚动用例也失败。原始日志、图、失败门禁与包收据保存在精确SHA，未交付、不重跑绕过。
- 18442c6 用补偿提交撤回公共 UIKit preferredTransition 对齐实验和专用来源适配；保留书台、SwiftUI 原生缩放、原有返回手势、WebKit 已有保护及确定性故障夹具。未碰其他用户修改。
- 当前 b867978 仅让新书台的正文返回交给已有 SwiftUI 系统过渡，不叠加全屏白纸 UIHostingController。旧路径保留，不替换导航delegate、不开新手势、不轮询帧。新增日志门禁要求真实取消/完成均走系统表面，原纵向滑动/正文游标/取消重进断言不变。
- 本机63项、Swift语法、YAML/diff通过。正跑本HEAD同一套 CI；下一步真实视频对比，若仍有整页/闪变如实记录，不以门禁绿代替视觉。
- 仅同HEAD三workflow成功、真实同书同主题截图和交互视频已审阅、dSYM/CRC/SHA通过后才正式放桌面；当前未交付Build135。iPhone13Pro手感/120Hz/真实TTF/LiveContainer安装待真机。启动页暂停，12用户手测不访问网关。证据 F:/SourceReadSwift/book-passage-135/<HEAD>。

<!-- BUILD135_CHECKPOINT_END -->

