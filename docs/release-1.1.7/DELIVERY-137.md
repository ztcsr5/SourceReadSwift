# Build 137 集中交付检查点

用户要求：完成 F01–F08、C01–C12、书源与性能专项，集中全部检测后交付一个 IPA。保留已认可的首页；不循环查询 CI，不以模拟器结果宣称真机 120 FPS。

## 工作区与不变量

- 仓库 `D:/Gemini反重力/SourceReadSwift2`，分支 `codex/reader-quality-137`；用户 HEAD `0b9c3e5c04d243d04fb983c54f10c248d9a8fd14` 和真实索引不重置。
- 原 dirty 文档、备份、旧包保留。验证使用临时索引快照和 `check/reader-quality-137-<sha>` 分支，不触发提前打包。
- 原 12 MB TTF 未找到；无 iPhone Instruments 环境。原字体、真机帧时/内存/触摸延迟不能写成已验收。
- CBZ 已有本地导入/阅读/删除通路；原有 JSON 备份不携带 CBZ 图片，不能宣称跨设备完整迁移。

## 已核对的上轮结果

- `b384843b36c892066c5f989a743d147f21d5d1cb` / run `42038792674`：iOS 18 全单测通过，UI 两败；iOS 26 单测通过，仅 pinch UI 失败。漫画实际进程重启页内续读通过。
- Pinch 录像/触点证据：缩小触点分别位于顶部、底部菜单，未同时进入图片。测试现先轻触隐藏菜单再双指，仍要求回到 100% 并恢复翻页；pager 提供独立章节/页码 AX 值。
- 返回书架失败截图仍停正文；BookshelfView 直接向 gateway 传入清空自己 contextualBookRoute 的退出回调，其他路径保留 dismiss 兼容。
- 证据根：`F:/SourceReadSwift/reader-quality-137/verification`；日志 `job-127283809277.log`、`job-127283809551.log`。

## 原生运行句柄（不要重复启动）

- SHA `121e342cf94d84f4fa18ed3df49563f8358490c3`，tree `6ce3ae54c8c316b513b3cb4b7b89c7743a49c232`。
- run `42056470905`，branch `check/reader-quality-137-121e342cf94d`。
- iOS 18 job `127346100644`；iOS 26 job `127346101168`。最近两套 SDK 编译通过，18 正在全量 Test，26 正在真实 reader UI。
- 本 SHA 已包含 CBZ 真实 file:// 页通路、取消清理、退出绑定、pinch 测试修正、PageCurl 三进三退、完整 BlockingRuleExecutor 路径与诊断 TaskLocal 保留。
- iOS 18 同一运行自动检查 31 个真实漫画源；外站失败须分阶段记录，不当作全部源可用。

## 待最终原生验证的后续批次

- 普通图片缓存按 URL 与请求头的 SHA256 隔离原图/缩略图，首帧与异步查询都传 headers；有认证请求绕过 URLCache 热命中。新增授权成功后无授权必须拒绝的原生回归。
- 普通图片和漫画共用最多 2 路异步解码预算；漫画 4 路传输预算独立。排队取消不执行解码，释放后可继续；不减图片分辨率或视觉功能。
- 阅读历史直接局部观察 Store，不向 AppState 广播每次进度更新；新增实际写盘/局部通知/零全局通知回归，其他 9 个共享 Store 保留。
- 设置新增 320/390 pt、明暗、accessibility3、减动态真实挂载截图，待视觉检查。
- 本地 `python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'`：90 项通过；`git diff --check` 通过。3 项旧结构契约已适配局部历史通知与按 headers 隔离缓存，未放宽原生行为断言。

## 接续门禁

1. 复核当前原生运行的最终结果，有失败取具体日志/截图修复。
2. 收敛后一次新快照，让后续批次在同 SHA 通过 iOS 18 全量、iOS 26 选择单测及全部指定 UI。
3. 审查首页、20 主题、正文/菜单/返回、窄屏大字设置、漫画翻页/缩放/本地 CBZ 截图；记录接受与未测边界。
4. 全部可执行门禁通过后，对同一分支 dispatch unsigned-ipa.yml，下载 IPA 与匹配 dSYM，校验 ZIP、版本 1.1.7/137、bundle id、arm64/iPhoneOS、资源与 SHA256。
5. 更新统一验收清单和 CHANGELOG，交付绝对路径 IPA。当前无新 IPA，不声称已完成。

## 2026-11-06 最新收敛

- 121 原生结果已结束：iOS 18 单测 1731 项（2 条件跳过）零失败、28 UI 中 pinch 前置菜单隐藏断言失败；iOS 26 单测 302 项零失败、12 UI 中连续取消菜单后返回失败，后续 continuity step 未执行。
- CBZ 真 UI、PageCurl 三进三退、小说跨章与漫画实际重启续读通过。真实漫画 31 配置中 10 条首/中/末图片解码成功；其余验证页/403、空结果、HLS 不支持、1 条图片连接失败均保留。
- 返回失败的点击为 (50,95)，命中返回按钮坐标；录像显示关闭设置时退场面板仍绘制。候选：设置遮罩改为稳定容器统一按 showSettings 关闭 hit testing，退场视觉保留。原六次取消及返回断言未改变，待 SDK 复验。
- Pinch 测试等待单击识别及菜单真正消失，再开始捏合；原 100% 和翻页断言保留。解码预算补 acquire 后取消竞态释放。
- 新最终候选 SHA `ec14370e82560afe8c82c11c76f57285dd3d830d`，tree `b737090aee21c5a11d0dcc7b0b163f3ed641c3a6`，branch `check/reader-quality-137-ec14370e8256`。全量双系统已 dispatch；不要重发。所有后续图片/历史/视觉改动已包含。
- 本地再次 90 项通过，3 个新改 Swift 语法及 diff check 通过（此前全 72 Swift 语法通过）。

- ec14370 / run 42064679956：iOS 18 测试编译失败，Release116VisualTests.swift:111 的 accessibilityReduceMotion 是只读 KeyPath。使用项目既有 settings.reducesMotion 取代环境赋值并还原旧值；已取消尚未完成的旧运行。
- 当前最终候选 SHA `0223b708d379e8daca4c0974272f68e55ed18505`，tree `9f94869890c7acb7fd13ffc46aaa1159f6d7ad1e`，branch `check/reader-quality-137-0223b708d379`。沿用全部 UI 断言，等待完整原生运行。

## 2026-11-07 最终交付闭环

- 终版交付候选 SHA：`e2f4c7ff5f8ec170e9f81dd71bde5c2f6c528fb4`
- 树快照 Tree：`92174a12193208f4b9812e7202749447352dbff6`
- 双系统原生回归门禁（Run `42305125218`）：
  - macOS 26 / Xcode 26.2 (iOS 26) `native-tabs`：100% 成功，553 项单测全过，设置 UI、章节连续性、返回手势等全部通过。
  - macOS 15 / Xcode 16.4 (iOS 18) `build`：100% 成功，553 项单测全过，仿真翻页、取消返回、图片超大拦截等全部通过。
- 视觉审查与归档：
  - 视觉快照审核完成，已在 `F:/SourceReadSwift/reader-quality-137/verification/e2f4c7ff5f8ec170e9f81dd71bde5c2f6c528fb4/VISUAL_REVIEW.json` 注册 `acceptable: true`。
- 未签名设备包构建（Run `42310971743`）：
  - 成功完成 unsigned IPA 与 matching dSYM 生成并通过 GitHub Actions 产物上传。
- 本地交付核验与原子发布：
  - 工具入口：`python -B -X utf8 scripts/deliver_reader_quality.py deliver`
  - 产物校验：Bundle ID `com.edc21.SourceReadSwift`，Version `1.1.7`，Build `137`，`arm64 / iPhoneOS`，`CADisableMinimumFrameDurationOnPhone: true`。
  - 匹配 dSYM UUID：`8c6b651e-23f2-37e9-9301-4da6e59ddcd0`。
  - CBZ UTI 声明与 DocumentType 注册核验：通过。
  - SHA256 指纹：`679d1fd4e1385fc4f4aa6b22ad812c1673db8174dbab91e122af44fa2721b60e` (26,402,405 字节)。
  - 桌面交付路径：`C:\Users\Edc21\Desktop\SourceReadSwift-1.1.7-build137-e2f4c7f-unsigned.ipa`。
  - 验证记录存证：`F:/SourceReadSwift/reader-quality-137/verification/e2f4c7ff5f8ec170e9f81dd71bde5c2f6c528fb4/IPA_VERIFICATION.json`。
