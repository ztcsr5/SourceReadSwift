# 阅读菜单 / 设置面板栈溢出 · 2026-11-02

## 现象与证据
- 用户：iPhone 13 Pro，报告 iOS 27.0.1。进入阅读后滑动一会，再点菜单闪退；不是必现。
- IPS 32,289 bytes，SHA256 `bb7f4051f26bde87f6e698df218df42a390a2452d947155483a0ed73f82df131`。原始日志留在用户提供的位置，不提交个人标识。
- 主线程 `EXC_BAD_ACCESS / SIGSEGV / Thread stack size exceeded`；访问 Stack Guard，日志给出的主线程栈为 1008 KB。101 个栈帧不是无穷递归的证据。
- 应用 image UUID `2d9ea9af-044f-3dc1-bc28-2809985c0154` 与桌面 build 130 / `87e6df3` IPA 完全一致。LiveContainer 是宿主进程名称，不能据此判为容器故障。
- 5 个连续应用帧（`0x413ef4`, `0x413c64`, `0x41252c`, `0x410f2c`, `0x4109ac`）均解析为 `ReaderView.settingsPanel` 的嵌套构建闭包。最顶层应用帧位于类型值见证大小驱动的栈分配检查后；父链是 VStack → ScrollView → VStack → VStack → GeometryReader。
- 脱敏符号证据：`F:/SourceReadSwift/reader-motion-117/87e6df3357cd4806094888dbc9d163875167d52b/crash-investigation/SYMBOLICATION.json`。使用仓库脚本 `scripts/symbolicate_reader_crash.py` 核验 UUID，不用不匹配的模拟器符号。

## 可证伪假设与验收
- 假设：外观 / 排版 / 高级的巨大具体 SwiftUI 值，被条件分支和多层容器继续内联与复制，耗尽真机栈；不是阅读正文数据越界。相同路径上的可用栈余量不同，可以造成偶发。
- 先加入 `ReaderSettingsStackTests`：每页与选页边界的具体值 ≤ 16 KB（32 份仍小于报告栈的一半），记录旧实现实际值。此预算不是实际帧大小或 FPS 测量。
- 再通过非泛型、延迟构建的设置边界切断传播；滑块也独立构建，避免只把巨型值搬到一个新闭包。仅设置层使用类型擦除，阅读正文热路径不变。
- 必须保留原有排版 / 页眉 / 章节名 / 字体导入 / 壁纸 / 高级辅助控件与绑定；不改导航、进度、书源或阅读窗口。
- 原生 XCTest 和 Release arm64 构建必须通过；补延迟构建、绑定与实际三页挂载回归。模拟器栈更大，之前全绿不能代表真机栈安全。
- 真机复验仍必需：滑动模式连续阅读，再反复打开关闭菜单 / 设置并切换三页；保留位置、退出再进。没有该复验不能声明真机闪退已经消失。

## 当前状态
- 基线 `87e6df3` CI 全绿，但已被真实设备崩溃推翻稳定性验收；不要继续把 build 130 当作稳定包。
- 回归测试提交 `18e1e84`：iOS26 run41462572070/job125335099190 跑162测试，仅新预算断言2项失败。旧值：appearance4104、layout23520、advanced5104、selection23522 bytes。原始日志1082292 bytes，SHA256 `9b3433051d0b11302fc6f79f0637af9b9135ec2dd9641cd2bdf3fa67375413c6`，已存 exact-head 证据目录。预算保持16KB，不降低断言。完整 regular 基线仍在跑；后续修复推送若取消，不计作通过。
- build131 源码通过本地 Swift 语法解析、YAML 与 diff 检查；原生 SDK / XCTest / 视觉结果仍待完整修复 CI，不宣称已通过。
- 新包必须使用新 build 号，保留旧 IPA、不覆盖用户书籍与设置。修复与新包 CI 结果在 RECOVERY 中补记。

## 后续定位能力
- 无签名 IPA 的 CI 显式生成并单独留存对应 arm64 dSYM，不混入安装包。使用 Apple 官方 DEBUG_INFORMATION_FORMAT=dwarf-with-dsym 设置：[构建调试信息](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)。下载后仍需核对 UUID，不以相同源码或模拟器符号代替。
