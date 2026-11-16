# 四批改动交付与未关闭验收

## 代码与范围

- 共用开发线：`codex/next-from-build150`，仓库保持 Private，未合并 `main`。
- 当前可安装 IPA 对应应用源码提交：`72da14a1`。继承 Gemini 基线 `a1151bcb`，该范围实际为 106 个文件、+6062 / -1876 行；不包含仓库遗留未跟踪脚本和临时文件。
- `72da14a1` 之后本次收尾只调整测试测量时机与审计文档，未更改 IPA 中的应用源码。

| 批次 | 实际实现 | 实现记录 |
| --- | --- | --- |
| 1：JSON 书源与加载 | 按规则输出证据区分漫画/视频，详情提供目录地址时按正确依赖加载，清理破图占位；小说/漫画前后各 10 章候选，共用 2 个请求并发名额与有界缓存；远章漫画预取图页地址，不全量解码图片 | [COMIC-SOURCE-151.md](COMIC-SOURCE-151.md) |
| 2：漫画阅读器 | 适配 Aidoku 的偏移保留布局，稳定页身份和真实图片尺寸，连续前后跨话、图片载体复用、双击/捏合；完整漫画设置从阅读器右上角「设置」进入；继续使用纸间 JSON 源、书架和进度 | [COMIC-READER-AIDOKU.md](COMIC-READER-AIDOKU.md) |
| 3：视频/有声书/TTS | 独立 AVPlayerViewController 视频外壳；剧集、进度、请求上下文、播放所有权和锁屏接线；修复 seek 后旧观察回调回退进度；有声书稀疏章节恢复，小说 TTS 与旧录音包入口明确区分 | [MEDIA-PLAYBACK-BATCH3.md](MEDIA-PLAYBACK-BATCH3.md) |
| 4：阅读交互 | 独立窗口保留主页的「书封开合」「跟手收书」；只动画静态副本；叠化/层叠/涟漪翻页；右上角选字；移除阅读目标弹条；启动底色一致；实屏发现的预热页页码错位已修复 | [READER-INTERACTION-BATCH4.md](READER-INTERACTION-BATCH4.md) |

没有接入 Aidoku 扩展源，没有重新启用系统 `.preferredTransition = .zoom`，没有重新设计寻书页。系统平移仍为默认；可在「设置 → 高级设置 → 阅读页面转场」选择两种新开合。新翻页效果在阅读设置的「翻页」条中。

## 实际验证

| 提交 / Run | 已获得的结果 | 不能据此声称的结果 |
| --- | --- | --- |
| `38f4be41` / [43852398044](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43852398044) | 漫画 63 项 XCTest + 8 项 XCUITest 全过，实际右上角设置和完整设置页已目视核对 | 后续所有改动的全量回归通过 |
| `2d0ad4d2` / [43858557692](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43858557692) | 媒体 62 项 XCTest 全过，无跳过，包含真实 AVPlayer seek 至 18 秒后不回跳 | 所有外站音视频源或真机 PiP/AirPlay 均可用 |
| `72da14a1` / [43861831532](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43861831532) | 阅读交互 67 项原生测试 + 4 项 UI 全过；实际边缘完成/取消、同会话同正文、三种翻页、选字及页脚像素 OCR 一致性通过 | 模拟器测试证明真机 120 Hz |
| `72da14a1` / [43861831582](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43861831582) | 未签名设备 IPA 构建、打包与工作流包校验成功 | 最终完整回归全绿 |
| `1d6a2478` / [43859847018](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43859847018) | iOS 16.4/17.5 兼容 job 均成功；iOS 26 定向 811 项单测通过。普通全量单测 2,128 项、2 跳过、1 失败；运行后由新提交的完整回归替代取消 | 旧提交整体成功，或这些旧 SHA 结果证明页脚收尾通过 |
| `72da14a1` / [43863379338](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43863379338) | GitHub 拒绝启动；普通 build job 无 runner、无步骤，日志 404 | 本轮已执行任何编译或测试 |

最终完整回归的官方失败原因是账户付款失败或 spending limit 需要提高。原始 annotation 保存于 `F:/SourceReadSwift/batches-20261116/full/72da14a1/build-annotations.json`，SHA-256 `b8be69511d16ce8b53606ac6b9fc39581902adfe2aa203e767b7794c212004b3`。重复 dispatch 不能解决账户额度，恢复后再启动完整工作流。

普通全量唯一已知失败为 `Release117ChromeTests.testReaderChromeOnNarrowAndNormalPaper`：按钮转换后高度 `43.99827957893153` 小于 `44.0`。产品控件明确为 44 × 44，HUD 存在独立的 0.98 起始缩放；正文就绪不代表控件动画已稳定，采样时机是待原生验证的解释。测试现增加最多 2 秒的几何稳定等待，再执行原 16 pt 边距与 44 pt 高度硬断言；没有降到 43.99，也没有跳过。该测试修正的 Windows parser / 名称遮蔽 / diff 检查已过，原生复验尚未运行。2 项已有跳过来自需要 iOS 26 的 TabChrome 用例，未新增 skip。

Windows 最新全脚本检查为 218 项通过；这不是 iOS 编译证明。验证结果必须按各自 SHA 和范围引用。

## 交付文件与复跑

IPA 和包内核验清单保存在 `F:/SourceReadSwift/batches-20261116/delivery/72da14a1/`。应用版本 1.1.8 / Build 151，具体文件哈希以同目录核验清单为准；不要覆盖用户以前的 IPA。

额度恢复后，在 GitHub Actions 的 iOS 工作流选择 `codex/next-from-build150`，两个定向输入都保持 false，执行全部任务；核对最终分支提交的常规构建、iOS 26、16.4、17.5 与未签名 IPA 结果。当前未将四批目标标为完成，完整验收仍未关闭。

本地复核：

```powershell
Set-Location -LiteralPath 'D:\Gemini反重力\SourceReadSwift2'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py' -q
python -B -X utf8 scripts/audit_swift_name_shadowing.py
git diff --check
```

设备仍需检查：LiveContainer 的独立阅读窗口行为、实际边缘取消/快速返回、漫画快速滚动/反向跨话、视频全屏/画中画/锁屏、启动衔接，以及 Instruments 帧时。没有证据证明全部真实远端书源均恢复，也没有给出超过屏幕刷新率的承诺。

## 影响与回滚

未迁移 JSON 书源或书架数据结构。新阅读页脚修复覆盖所有复用分页页脚的模式；新开合可在设置中切回「系统平移」，新翻页可切回原模式。源码回滚只针对独立功能提交逐个 `git revert`，不对共享分支 reset 或覆盖 Gemini 的提交；例如撤销页脚修复为 `git revert 72da14a1`。
