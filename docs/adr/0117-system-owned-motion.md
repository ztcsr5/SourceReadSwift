# 0117 · 系统持有导航，阅读状态不参与装饰动效

## 背景
1.1.7 要统一视觉连续性，同时保留系统交互式返回、阅读锚点、多主题和减少动态效果。启动实验暂停，不能将演示定时器或场景状态机搬进正式阅读器。

## 选项
- 跨 NavigationStack 强行使用 matchedGeometryEffect 并自行实现返回手势：可定制曲线，但需要自行处理取消、遮罩和原导航状态，风险高。
- 使用系统 zoom/navigation push，叶节点负责颜色和轻量反馈：系统负责导航生命周期，较少与阅读状态耦合。

## 决定
- 选择第二种。iOS 18+ 配对 matchedTransitionSource/navigationTransition(.zoom)，按入口位置构造源 ID；旧系统保留原生 push。不隐藏系统返回、不接管边缘手势，不声称系统 zoom 可精确固定为 440 ms。
- AppMotion 提供按压、导航、展开、背景、书笺的语义节奏与系统/App 双重减弱设置。禁止在整个阅读文本树上挂装饰动画。
- 读页手势由 UIKit 持有，位移只改 transform；hosting 几何仅在安装/尺寸变化时更新。分页、章节提交与取消规则不随美术调参更改。
- 封面取色复用已降采样图片，24 px 后台取样并缓存；背景无循环 Timeline、无实时模糊。

## 后果
- 减少旧系统兼容风险，但旧系统不提供新 zoom。系统回退和中途取消仍须实际交互验收；原生单测/截图不能替代真机 FPS。
- 首批接入书架、详情、阅读菜单与导航。其它页面和“真实选中文字保存→书笺票根”单独接入，不把统一参数定义当作全 App 已迁移。

## 官方依据
- [ZoomNavigationTransition](https://developer.apple.com/documentation/swiftui/zoomnavigationtransition)
- [Enhance your UI animations and transitions](https://developer.apple.com/videos/play/wwdc2024/10145/)
- [UIViewPropertyAnimator](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator)
- CI 本分支使用标准 Intel runner 避开已记录的 arm64 容量取消，其它分支不变：[官方 runner 标签](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[macOS 15 工具链清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)、[macOS 26 工具链清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)。
