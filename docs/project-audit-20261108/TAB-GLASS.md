# 底栏玻璃与主页搜索专项

- 基线：`565a44ecd93982f9d6293d6da29729155862b817`，保留已验证的滑动修复。
- 变更：现有唯一自定义底栏和搜索使用系统玻璃；iOS 26+ 使用 Liquid Glass，旧系统使用 ultraThinMaterial；减少透明度与增强对比度使用不透明底色。
- 保留：三个独立导航栈、原控件 ID、搜索行为和 RootTabView 布局。
- 原生门禁：iOS 26 / 18 串行运行 RootTabGlassTests、TabChromeRegressionTests、真实主页明暗截图、搜索本地书→详情。
- 像素门禁：320/390 pt × 明暗窗口，采样避开文字和选中项；旧不透明配方为负对照，UIKit 增强对比度 trait 路径要求不透底。减少透明度的系统全局开关不可由 SwiftUI 测试写入，独立验证它选择同一 opaque 分支；未声称实切系统开关。
- 本地：三生产/测试 Swift 文件语法解析无错误；Windows 不具备 Xcode，不能用本地语法证明材质或 UIKit 行为通过。
- 状态：待导航专项原生运行。仅专项验证，不代表完整项目全量测试，不包含 IPA 打包。

## 快照与回滚

`scripts/verify_tab_glass_quality.py` 从固定基线与允许清单创建临时 index；只在临时树用专项 workflow 替换已注册的 `ios.yml`，不修改原 index、checkout 或本地完整 workflow。回滚采用基线快照，勿对脏工作区整文件 restore。

## 首轮原生快照

- SHA：`302ee15b02ce447e20c5fdad63842130353d9195`。
- Run：`42481019266`，https://github.com/ztcsr5/SourceReadSwift/actions/runs/42481019266 。
- 本地门禁：2 项 workflow/临时 index 测试通过；四个 Swift 文件无新增语法诊断；限定路径 diff check 通过。
- 快照仅 9 个允许路径变化，Reader 源码和滑动测试相对基线无差异，原 index 字节保持不变。
- 启动状态：iOS 26 引导模拟器，iOS 18 排队；不得把启动成功写成测试通过。

## 首轮失败与修正

- iOS 26 编译失败：`RootTabGlassTests.swift:146/147: cannot convert value of type KeyPath... to WritableKeyPath...`。原因是测试尝试写入两个只读的 SwiftUI 可访问性环境值；生产 glassEffect 代码未报错。
- 立即取消仍在编译的 iOS 18 同轮任务，避免重复已知失败。取消 run 返回 HTTP 202。
- 修正夹具：增强对比度由 UIKit trait override 驱动，另断言 trait 真正生效；删除只读 environment 写入。减少透明度通过生产分支选择策略验证，透底阈值不变。
