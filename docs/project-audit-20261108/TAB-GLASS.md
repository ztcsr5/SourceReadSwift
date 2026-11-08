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

## 第二轮原生与真实主页证据

- SHA `a178d91266fae25c1d6472a77e4effab7a3164ed`，run `42482328243`。
- iOS 18 专项全部成功；iOS 26 材质与底栏 ownership 7 项单元测试成功，全网搜索本地书→详情 UI 成功。
- 唯一失败：iOS 26 `RootTabGlassUITests.swift:19`，`tabs.legacy.home` 存在且唯一，但 `isHittable == false`。不是搜索消失，也不是启动超时。
- 已提取录像 21 s 帧并检查：首页与整条底栏完整在屏内，没有弹窗/键盘遮挡；iOS 18 明暗主页截图留存。书架卡片延伸至底栏下方，没有看到单色安全区将材质与内容隔开。
- 证据目录：`F:/SourceReadSwift/reader-quality-137/verification/a178d91266fae25c1d6472a77e4effab7a3164ed/tab-glass-visuals/`。原视频 986356 字节，SHA256 `1586cc0c87414db68788bd0345115439b4e487a15136b894cedac730f5f66702`。
- 可证伪假设：公共 Capsule 的 interactive glass 层影响内部三个按钮 hit testing；单独搜索本身可点。下一轮只将公共底材改为非 interactive 原生玻璃，搜索保留 interactive，不改布局/等待时长。
- 保留原 hittability 断言，并新增寻书→设置→主页真实点击与页面断言、失败断言前截图。未将该假设提前记为已修根因。

## 第三轮点击区域

- SHA `557a108eb78bb4a763c1f9b7a5908df2309ebd38`，run `42488313783`。
- iOS 26 材质/ownership 7 项与原搜索→详情再次通过；三个 Tab 的 `isHittable` 均通过，公共玻璃去掉 interactive 后原失败不再出现。
- 新断言发现搜索的 AX frame 仅 `21.6667 pt`（glyph 宽度）而不是视觉圆形的 `52 pt`，失败 `RootTabGlassUITests.swift:23`。保留 `>=44 pt` 断言，不降低标准。
- 单变量修正：在搜索的 52 pt 玻璃 label 上显式声明 `contentShape(Circle())`。保持 regular interactive 玻璃与布局不变。停止第三轮尚未完成的 iOS 18，重新验证同一新版。


## 最终原生验证（2026-11-09 核对）

- 提交 `9334c75b6ab067f86ceee5070a867daee820b95b`，[run42490012715](https://github.com/ztcsr5/SourceReadSwift/actions/runs/42490012715) 双系统 success。
- iOS 26：7 项单元、2 项 UI，0 失败；iOS 18：5 项单元通过、2 项既有 SDK26 专用测试跳过，2 项 UI 通过、0 失败。没有为了通过新增跳过或放宽断言。
- 搜索显式圆形 contentShape 后保留 >=44 pt 断言通过；三个导航标签真实点击、页状态、全网搜索本地书→详情均通过。320/390 pt 明暗像素差分、旧实色负对照、增强对比度不透明路径通过。
- 新旧系统都保留透明材质，不再让 atelier 主题用实色胶囊。iOS 26+ 为 regular Liquid Glass，旧系统 ultraThinMaterial；系统减少透明度/增强对比度仍有明确的不透明辅助功能回退。
- Reader 源码对已绿 `565a44e` 无差异。此轮没有重新跑全部滑动专项，不用父提交结果冒称新 SHA 全量测试。
- iOS 27 无可用 runner，未实测。真实设备 FPS 未测，返回侧滑两项仍按用户指示暂停。
- 已派发相同提交 Release 打包 [run42498691251](https://github.com/ztcsr5/SourceReadSwift/actions/runs/42498691251)，只打一个包；最终交付收据保存到上述提交证据目录。


## 主页截图说明

用户询问截图为何与日常主页不同。已比较上一交付92c919b与本包9334c75：整个Bookshelf目录、RootTabView、AppVisualTheme/AppAtelierTheme/AppTheme、AppearanceSettingsView、测试书库入口均无变化。截图来自UI测试显式选择的pineMist（松雾）和临时书库，不代表正式版默认外观；正式默认仍forest，已有用户选择不会被本修复覆盖。后续展示必须标明主题/测试夹具，不再将其当作用户日常主页截图。核对收据HOMEPAGE_PRESERVATION.json。
