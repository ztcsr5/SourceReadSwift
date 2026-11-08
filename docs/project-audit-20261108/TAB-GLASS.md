# 底栏玻璃与主页搜索专项

- 基线：`565a44ecd93982f9d6293d6da29729155862b817`，保留已验证的滑动修复。
- 变更：现有唯一自定义底栏和搜索使用系统玻璃；iOS 26+ 使用 Liquid Glass，旧系统使用 ultraThinMaterial；减少透明度与增强对比度使用不透明底色。
- 保留：三个独立导航栈、原控件 ID、搜索行为和 RootTabView 布局。
- 原生门禁：iOS 26 / 18 串行运行 RootTabGlassTests、TabChromeRegressionTests、真实主页明暗截图、搜索本地书→详情。
- 像素门禁：320/390 pt × 明暗窗口，采样避开文字和选中项；旧不透明配方为负对照，可访问性路径要求不透底。
- 本地：三生产/测试 Swift 文件语法解析无错误；Windows 不具备 Xcode，不能用本地语法证明材质或 UIKit 行为通过。
- 状态：待导航专项原生运行。仅专项验证，不代表完整项目全量测试，不包含 IPA 打包。

## 快照与回滚

`scripts/verify_tab_glass_quality.py` 从固定基线与允许清单创建临时 index；只在临时树用专项 workflow 替换已注册的 `ios.yml`，不修改原 index、checkout 或本地完整 workflow。回滚采用基线快照，勿对脏工作区整文件 restore。
