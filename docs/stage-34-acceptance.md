# Stage 34 验收清单：EPUB / RSS / 书架批量操作 / Web 写源 PC 端 / 图标与产品收口

## 目标

在完成 Stage 33（阅读器手感、120Hz ProMotion、17 组 TXT 目录正则、8 套原生主题双绿 CI 闭环）的基础上，全面推进整个项目的最终集大成阶段 —— **Stage 34**。
结合用户重点强调的“主要是书源能力”与用户提供的生产级解包资产（`browserSource.json`、`rssSources.json` 等），实现商业级原生 iOS 阅读器的最终功能与体验收口。

## 本阶段范围与实现

1. **书源能力极限深化与容错**：
   - 松散 JSON 容错与尾随逗号清洗（`SourceStore.swift`），支持自动清洗 `rssSources.json` 等源中的尾随逗号并 100% 成功解析。
   - 内置源阅读官方精选 3 套 RSS 源（`使用说明`、`源仓库`、`海阔视界`）。
   - 适配通用智能导航源（`browserSource.json`）所需的全局 `org.jsoup.Jsoup` / `Jsoup` 与 `book.setReverseToc` 扩展。
2. **书架批量操作 (Bookshelf Batch UI)**：
   - 书架增加“批量管理”模式，支持全选、取消全选、反选。
   - 底部浮动工具栏提供：批量删除（带防误触确认）、批量更新与批量导出书籍清单。
3. **EPUB / RSS 深度排版闭环**：
   - 验证并强化 EPUB 多级目录树、图文混合排版与段落精确锚定。
   - 验证 RSS 订阅流文章抓取、富文本排版与夜间模式自适应。
4. **PC 端 Web 写源交互升级**：
   - Web 页面提供一键填入样例书源模板（Legado 3.0 搜索、目录、正文骨架）。
   - 增强错误捕获与即时导入状态通知。
5. **关于页与产品收口**：
   - 关于页展示 `v2.0.0 (Stage 34 Final Release)` 与 34 阶段全量能力矩阵。
   - 达成与原有 Flutter 原型的全面功能超越与闭环。
6. **自动化回归**：
   - 新增 `Stage34ComprehensiveParityTests.swift` 单元测试套件并全量通过。
   - GitHub Actions 双流水线（iOS build/test 与 Unsigned IPA）双绿闭环。

## 验收门槛

1. [ ] `git diff --check` 通过。
2. [ ] 新增 `SourceReadSwiftTests/Stage34ComprehensiveParityTests.swift` 覆盖上述核心能力。
3. [ ] `progress.md` 记录实现、证据与闭环详情。
4. [ ] GitHub Actions 双流水线全绿通过（iOS 测试通过 + 无签名 IPA 生成）。

## 验证证据与流水线闭环

- **Target Commit**: 待提交
- **iOS build & test (Authoritative Gate)**: 待运行
- **Unsigned IPA Package (Release Packaging Gate)**: 待运行

## Stage 34 状态：IN PROGRESS
