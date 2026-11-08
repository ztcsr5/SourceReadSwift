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
- 回归测试提交 `18e1e84`：iOS26 run41462572070/job125335099190 跑162测试，仅新预算断言2项失败。旧值：appearance4104、layout23520、advanced5104、selection23522 bytes。原始日志1082292 bytes，SHA256 `9b3433051d0b11302fc6f79f0637af9b9135ec2dd9641cd2bdf3fa67375413c6`，已存 exact-head 证据目录。预算保持16KB，不降低断言。regular 基线记录1584测试/2原始跳过/2预算断言失败（layout23288/selection23290），证据上传阶段被新推送取消，不计通过。原始日志2334774 bytes、SHA256 `9cc86403ea4bf3cb71ce78d8f4ede184dbf1ebc59ffa1bb506200e1f5c5c44f2` 已留存。
- build131 源码通过本地 Swift 语法解析、YAML 与 diff 检查；原生 SDK / XCTest / 视觉结果仍待完整修复 CI，不宣称已通过。
- 新包必须使用新 build 号，保留旧 IPA、不覆盖用户书籍与设置。修复与新包 CI 结果在 RECOVERY 中补记。

## 后续定位能力
- 无签名 IPA 的 CI 显式生成并单独留存对应 arm64 dSYM，不混入安装包。使用 Apple 官方 DEBUG_INFORMATION_FORMAT=dwarf-with-dsym 设置：[构建调试信息](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)。下载后仍需核对 UUID，不以相同源码或模拟器符号代替。

## 修复验证回执（本地，保持源码 HEAD 与 CI 一致）
- 修复提交 `4a5d62ddccf1cd931ed0610fd7fe18399d50f277`，1.1.7/build131。两个 CI 均 SUCCESS：iOS run41465960339（regular1586测试/2原始跳过/0失败，native26 164测试/0失败），device unsigned run41465960417。
- 两套运行时均实测：appearance/layout/advanced 各16 bytes，selection18 bytes；原16384 byte 预算保留，未降低断言。延迟构建与活绑定读取、真实三页挂载均通过。此处是视图值大小，不是函数栈帧或帧率测量。
- 两套运行时各六张真实内容截图均已在320pt浅色/390pt深色检查：三页内容可见，无新增横向溢出；仅覆盖所示视口，不宣称页下全部操作或完整菜单壳已验收。证据 exact-head settings-visual-review/INDEX.json 与 settings-visual-review-native26/INDEX.json。通过 ZIP Range 仅下载目标条目并校验各自 CRC/SHA，不宣称完整截图归档哈希。
- 桌面 IPA：`C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build131-4a5d62d-unsigned.ipa`，26,526,613 bytes，SHA256 `03a7540508149e2046f5c92745f768b245f9057358ed9bf69d85b80634792629`。CRC、plist、arm64、iPhoneOS、minOS16、字体资源和复制后哈希通过；未签名，未安装。
- 独立 dSYM 与安装包 UUID 同为 `2424a5bf-5a12-3edc-8cd5-d437cf59854e`；原始调试符号105089208bytes，单独保留，不混入 IPA。
- 仍待 iPhone13Pro 用户实测：持续滑动，再反复打开菜单、设置、切三页并返回，确认不崩溃且位置不变。不能把 CI 绿当成真机偶发问题已彻底消失。

## 可复核命令与回滚
```powershell
Set-Location -LiteralPath "D:\Gemini反重力\SourceReadSwift2"
python -X utf8 scripts/reader_motion_ci.py
Get-FileHash -Algorithm SHA256 -LiteralPath "C:\Users\Edc21\Desktop\SourceReadSwift-1.1.7-build131-4a5d62d-unsigned.ipa"
```
预期：exact4a5d62d 两个 run success；文件哈希与上文一致。

不推荐回到存在已知栈溢出的 build130。若仅为代码对比，在另建的干净验证工作区可 `git revert 4a5d62d`；这会恢复已知风险并使预算回归失败。不要在当前保留修改的目录执行 reset/clean 或覆盖书籍数据。
