# 阅读器接管修复：Build 119

## 输入与基线

- 当前任务是修复，不是继续只读审计。已读取 Antigravity `2a8bc56d-a010-4246-b869-51077d557ea9` 至 step 5178，以及两条 Codex 历史。历史中的命令和方案仅作证据。
- 基线：`5686485045b78cfb17c654a2acf8c30c387a73e8`，Build118。
- 独立修复分支：`codex/reader-recovery-119`。未合并/重置原分支，原有 `.bak*` 未动。
- 原件：`F:/SourceReadSwift/recovery-119/BASELINE`，362 个源/测试/配置文件及工作流原始 Git blob。

## 已实施（同提交原生测试与打包已通过）

1. 全章节内容 revision，消除只看首尾与段数的失效漏洞。
2. 富文本缓存绑定实际分片、几何和渲染设置；邻页就绪可更新宿主，不必先离开再回来。
3. 纯文字章使用共享 TextKit attributed document 分页，移除固定16pt兜底留白；最终 UITextView 实测仍是发布门禁。
4. UTF16 段内锚点、段首跳转规则，避免目录跳到长段最后一个续页。
5. 覆盖/平移改为 UIKit pan + property animator；完整已结束手势 FIFO 与当前手指隔离，异步模型回写和取消 generation 隔离。
6. 覆盖与平移使用不同物理位移；仿真接回 UIPageViewController `.pageCurl`，保留已有正确的 `animated:false` 同步。
7. 删除自定义黑色更多菜单，使用 UIButton/UIMenu；无可用回调的功能明确 disabled。
8. 保留118设置面板层级修复；非当前冷章节从同步分页改成后台占位预热；退出取消遗留任务。

## 实际验证进展

| 提交 | 结果 |
|---|---|
| 586a5bd | 模拟器/设备 build 成功，IPA工作流成功；1366 XCTest 中1失败：内置书末章实际 UITextView page0 usedRect=756.9453125，而正文高度702。**不能交付为已修复。** |
| 2cdeb63 | 三手势 FIFO 已实现；原生 build 抓到参数遮蔽导致的 optional chaining 编译错误，下一提交已改为显式 self + 异步回调。未执行测试，不计通过。 |
| eda34a5 | 生产/测试共享 text surface 工厂，新增独立排版/UITextView参数和glyph诊断、三手势/取消回调/长标题/RTL/换行/空段守恒测试；原生验证进行中。 |
| eda34a5 后续结果 | 1373测试、3条失败断言：实际surface仍裁字；RTL混排丢尾及后面的最后一段。相同glyph断行下691.203125/756.9453125差异，CJK纯中文行低估3.8671875pt。队列、三手势和取消测试通过。 |
| 8051cac | 正文/标题分别以对应UIFont.lineHeight明确minimumLineHeight，不限maximum，允许emoji高字形；分页改为源UTF16字符覆盖完成，不冻结layout前glyph数量。设备编译通过；新增矩阵测试因CGFloat常量类型歧义未执行。 |
| 70bf49b | 仅补显式CGFloat类型，保留全部原断言，重新运行同提交原生测试/IPA。 |
| 70bf49b 实际结果 | 1374测试中仅1失败：旧测试要求minimumLineHeight为0。全部18项新增回归通过，包括实际UITextView内置书、独立/实际字体矩阵、长标题RTL守恒及翻页队列。旧断言与真实UITextView行高契约冲突，不是继续放宽裁字断言。 |
| 71156be | 旧行高测试改为分别校验正文/标题对应UIFont.lineHeight，maximumLineHeight仍为0，不限制更高回退字形；实际surface高度、文本守恒和手势断言不变。iOS41174151682、IPA41174151739验证中。 |

本地 tree-sitter 只证明语法树可解析，不代替 Swift 类型检查。字节回滚演练已验证 patch 重建、canonical rollback、再应用及恢复原始工作区字节；不是原生行为回滚证明。

## 尚不能宣称

- 未做用户手机真机视觉/触控/性能验收，没有120Hz、全系统无Bug或所有内容都不裁切的结论。
- 新文字分页没有替换图片混排章的旧引擎；图片/漫画须单列设备验收。
- 最终同一提交的 XCTest+IPA 已通过并交付；设备体验仍按单独清单验收。
- `.pushOut` 在旧注释中被误解为CJK标点悬挂；Apple实际定义为段尾孤词优化。但本次原生glyph逐行范围完全相同，已经排除它作为内置书这次溢出的原因，没有贸然改它。

Apple参考：https://developer.apple.com/documentation/uikit/nsparagraphstyle/linebreakstrategy-swift.struct/pushout

## 最终交付验证

- 最终提交：`71156be1ac148d6328dccc2844ed2555a41313b0`；分支 `codex/reader-recovery-119`。
- [iOS全量测试](https://github.com/ztcsr5/SourceReadSwift/actions/runs/41174151682)：1374 tests，0 failures；18项新增回归全部通过。
- [设备编译/IPA](https://github.com/ztcsr5/SourceReadSwift/actions/runs/41174151739)：同一SHA成功。
- 已检查ZIP与Info.plist：1.0.119/119；桌面包 `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.119-unsigned.ipa`。
- SHA256：`a9108d084724cef59aaba8b4311e19b60aaa9967cbdc4971cad80fa6ba84d455`。
- 修改/差分/验证/回滚四件套：`F:\SourceReadSwift\recovery-119`；16文件字节重建/回滚/再应用演练通过。
- 用户原始业务数据未删除；原分支未合并/重置。设备实测未执行，不能将模拟器测试等同于全部体验验收。
