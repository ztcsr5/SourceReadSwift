# 第四批：阅读开合、翻页和无打扰阅读

## 产品边界

- 沿用唯一开发线 `codex/next-from-build150` 和私有仓库。保留现有系统平移作为默认，新增「书封开合」「跟手收书」供用户选择；旧 `coverZoom` 偏好仍回退系统平移，不重新启用 Apple `.preferredTransition = .zoom`。
- 书封开合：点击封面展开，左缘轻扫达到意图阈值后一次性收回；阈值前窗口不移动。跟手收书：同一开卷效果，返回拖动的是快照，可撤回原阅读位置。书籍详情自身的系统侧滑保持原样。
- 新路径在当前 UIWindowScene 内增加独立阅读窗口，主页、详情与 Tab 栈留在原窗口。保持前台视图存活不等于承诺系统不会终止后台进程，也不等于模拟器已经证明真机 120 Hz。

## 实现与回退

- `Navigation/ReaderSnapshotPresentation.swift` 管理独立窗口、公开边缘识别器、快照动画完成/取消及 key window 归还；`ReaderSnapshotFlightView.swift` 只移动临时副本。开卷是纸色底板与封面副本，退场捕获当前画面；从不缩放活体 WKWebView、不隐藏原封面。封面缺失、明显裁切或开启减少动态效果时降级；旋转中恢复正文并撤销旧几何动画。
- `ReaderNavigationRouter` 复用既有会话与停放策略。`BookshelfView` 在阅读器打开期间只标记待刷新，动画完成后再刷新投影，避免「主页仍挂载」反而触发退出期间整架重排。
- `ReaderPageRevealSurface` 复用现有三页载体，增加叠化、层叠、圆形涟漪揭页。涟漪是圆形揭页，不声称实现水面折射。位置映射、章节边界、自动翻页与旧设置兼容一并接线；相邻页不接收点击和 VoiceOver 焦点。
- 选字从右上角 `… → 选择文字` 进入，提供「完成选择」返回原阅读菜单；开始选字时暂停自动翻页。移除阅读进度回调里的每日目标提示及震动，统计与阅读记录继续保存。
- `LaunchSurface` 给 LaunchScreen、根宿主和导航/窗口提供日夜一致的基础底色。Apple 默认空 LaunchScreen 已使用 systemBackground，不能将空字典认定为黑闪根因；强制主题与系统不同、真实启动耗时仍需设备录屏对照。
- 没有增加依赖、没有迁移 JSON 书源、没有重做寻书或主题。旧系统平移与独立快照选项互不替换，改动可按提交 revert。

## 验证门禁

- `ReaderSnapshotPresentationTests`：真实 UIKit 场景、原主页生命周期、原封面状态、真实 WebView 的取消/完成/重开，以及原弹层返回。
- `ReaderPageHostingTests`：三种效果短拖取消、反向单页提交、可见页与相邻页复用、段落映射和设置编解码。
- `ReaderPageRevealInteractionTests`：真实窗口中推进 UIViewPropertyAnimator 到中间帧，验证双向位移/透明度/涟漪遮罩、速度反转、手势打断，以及首尾页复用后遮罩与触控状态。
- `ReaderLaunchContinuityTests`：编译后的 plist 指向真实颜色资源，日夜承底色及实际挂载窗口。
- 新增真实 UI 流程覆盖两种快照返回、选字入口、新翻页效果前进和返回同一正文。原系统侧滑、目录、漫画和媒体断言保留。
- 专项入口 `.github/workflows/reader-interaction.yml`；以上新增实现尚待该 SHA 的 macOS 编译与专项结果。四批完成后再统一执行完整 `ios.yml`（含旧 iOS）与最终 IPA 构建，不借旧 SHA 的通过结果宣称本批完成。

## 第一轮原生证据与实屏收尾

- `49023b66` 的 [43858647000](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43858647000) 编译及 63 项原生测试通过；4 项 UI 中 3 项通过、1 项失败。两种返回与选字通过；三种翻页动作和正文返回断言完成后，测试提前终止 App 导致统一截图失败。`1d6a2478` 仅修正该测试生命周期，未删减断言。
- 逐图检查 11 张原生截图，确认原封面/主页/底栏完整、取消后原段落仍可见。发现真实问题：翻页页脚中央仍是预热时的页码，右侧已更新；修复让中央与右侧使用同一个页面快照的章/页信息，保留槽位设置。新增格式单测及实际截图 OCR 校验，要求三种效果前进显示第 2 页、返回显示第 1 页且中央/右侧一致。选字按钮去掉多余顶部 8 pt 偏移，避免贴住长章标题。
- [完整回归 43859847018](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43859847018) 在 `1d6a2478` 开始，不含上述页脚和间距收尾；最终仍须检查收尾提交对应的原生结果。该轮已有 iOS 16.4 10 项宿主测试和 4 项 UI 通过，不能借此替代新提交的全部验证。
- 收尾 `72da14a1` 的 [专项 43861831532](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43861831532) 已通过 67 项原生测试 + 4 项 UI，三种翻页的实际页脚 OCR 校验通过；[同 SHA IPA 43861831582](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43861831582) 已成功。最终完整回归因 Actions 账户额度未能启动；已知旧全量中另有 44 pt 几何时机断言，测试等待修正待原生复验，详见 [四批交付总账](FOUR-BATCHES-DELIVERY-20261116.md)。

## 公开 API 依据与真机项目

- [Apple snapshotView(afterScreenUpdates:)](https://developer.apple.com/documentation/uikit/uiview/snapshotview(afterscreenupdates:))：快照只反映已经渲染的内容，不能保证未显示内容可被捕获。因此失败时使用纸色承底并保留退出能力。
- [Apple UIWindow(windowScene:)](https://developer.apple.com/documentation/uikit/uiwindow/init(windowscene:))：阅读窗口归属于既有场景。
- 真机需验：慢拖撤回、快速轻扫、旋转、背景恢复、源封面处于屏幕边缘、VoiceOver、减少动态效果、LiveContainer 窗口行为，以及 Instruments 的动画帧时。不得把 CI 截图或刷新率请求值写成 120 Hz 实测。
