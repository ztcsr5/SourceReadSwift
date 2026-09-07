# Stage 31 验收清单：书源能力快照与阅读器收口

## 范围

- 数据源：`D:\QQ游戏\已测试.json`
- 样本数：13 个 Legado / 安卓开源阅读 JS 书源
- 当前阶段目标：把用户实测书源从一次性 JSON 导入样本，固化成可复跑的能力表、fixture bank 和 XCTest 回归入口；同时收口阅读器翻页、自动滚动、设置面板、数字输入、App 图标和关于页。

## 已落地产物

| 产物 | 路径 | 验收点 |
|---|---|---|
| 能力表生成器 | `ci-log/generate-source-capability-table.js` | 从 `已测试.json` 同时生成 Markdown 能力表和 XCTest fixture bank |
| 能力表 | `docs/legado-source-capability-table-20260908.md` | 输出主链覆盖、复杂能力覆盖和 A/B/C 源分层 |
| fixture bank | `SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json` | 保留 13 个源的关键规则字段、labels、complexity |
| XCTest 快照 | `SourceReadSwiftTests/LegadoCapabilityBankTests.swift` | 在 CI 中断言 Search/Detail/TOC/Content 主链与复杂能力计数不回退 |
| 阅读器策略测试 | `SourceReadSwiftTests/ReaderAutomationPolicyTests.swift` | 覆盖自动滚动起点、cover/page 起点、朗读队列和 chrome 状态 |
| 阅读器实现 | `SourceReadSwift/Features/Reader/ReaderView.swift` | 自动滚动从当前可见位置起步，cover 模式支持前后跟手拖拽预览 |
| 设置/关于页 | `SourceReadSwift/Features/Settings/SettingsView.swift` | 关于页明确当前能力，图标和产品线说明收口 |
| App 图标 | `SourceReadSwift/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | 替换为当前产品图标资产 |

## 当前数据能力表

| 能力 | 覆盖 |
|---|---:|
| Search | 13/13 |
| Detail | 13/13 |
| TOC | 13/13 |
| Content | 13/13 |
| Explore | 10/13 |
| CookieJar | 10/13 |
| JS-heavy | 8/13 |
| POST-search | 7/13 |
| GBK | 4/13 |
| Login/CF-check | 3/13 |
| Crypto/AES/Base64 | 3/13 |
| Font-obf/Image-text | 3/13 |
| Paging | 13/13 |

## 已覆盖用户反馈

- 阅读器设置面板：保持可关闭、返回阅读菜单，不再卡在外观/排版/高级界面。
- 滑动与数值：滑动条末端保留手动数字输入，减少盲调。
- 自动阅读：启动时快照当前可见段落/当前页，避免从旧目标或章节开头跳读。
- 朗读：队列从当前可见段落起步，只有章节开头启动才读标题。
- 翻页：cover 模式加入前后页拖拽预览，不再只靠结束阈值硬切。
- 字体：Native TextKit 路径继续使用 `UIFont.systemFont`，避免章节字体漂移。
- 图标/关于：补齐产品图标和关于阅读页的当前能力说明。

## 仍需真机确认

- 120Hz ProMotion 持续帧率、跟手阻尼是否接近系统阅读类 App。
- Web 写源在用户同网 PC 的实际访问；Windows/CI 只能验证地址选择逻辑，不能替代局域网环境。
- 复杂站点的登录/CF、人机验证、字体反爬、图文混排真实链路；当前已固定为 C 级能力继续巩固。

## 本地可运行检查

- `git diff --check`
- `node ci-log/extract-prelude.js`
- `node --check ci-log/js-prelude-check.js`

## 本轮 Actions 修正

- `LegadoCapabilityBankTests` 的 fixture 读取增加 bundle 根目录兜底，兼容 XcodeGen / test bundle 资源展开路径差异。
- `java.getFile(path)` 的 `isDirectory()` 语义改为读取文件系统资源值，和 `mkdirs()` / `listFiles()` 的目录对象预期对齐。

## GitHub Actions 门禁

本阶段提交后触发：

- `.github/workflows/ios.yml`：XcodeGen → simulator build → XCTest
- `.github/workflows/unsigned-ipa.yml`：Release iphoneos unsigned app → IPA artifact

如果任一失败，按首个编译/测试错误修复；不把 Windows 静态检查冒充 iOS 通过。

## 当前结论

- `f89910a` 已通过 `unsigned-ipa.yml`；`ios.yml` 同轮为 success。
- Stage 31 已收口，下一阶段入口转入 Stage 32。
