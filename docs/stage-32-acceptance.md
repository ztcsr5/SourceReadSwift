# Stage 32 验收清单：C 级书源兼容闭环

## 目标

把 `D:\QQ游戏\已测试.json` 里已经确认的高复杂 Legado / 安卓开源阅读 JS 书源，从“能力表可见”推进到“fixture 可测、回归可守、失败可诊断”的工程闭环。

## 当前范围

- 数据源：`D:\QQ游戏\已测试.json`
- 样本数：13
- 本阶段聚焦：
  - GBK / GB2312 / GB18030
  - 登录 / Cloudflare / 人机验证
  - AES / Base64 / 乱序恢复
  - 字体反爬 / 图文混排 / queryTTF

## 当前事实

- 主链 `Search → Detail → TOC → Content` 已经在这 13 个源上固定为 `13/13`。
- 复杂能力里最需要继续巩固的是：
  - GBK：`4/13`
  - Login/CF-check：`3/13`
  - Crypto/AES/Base64：`3/13`
  - Font-obf/Image-text：`3/13`
- 相关能力表已经落在：
  - `docs/legado-source-capability-table-20260908.md`
  - `SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json`
  - `SourceReadSwiftTests/LegadoCapabilityBankTests.swift`

## 必须完成的事

1. [x] 把 C 级源的 fixture 继续补齐到 XCTest（已在 `SourceEngineCLevelFixtureTests.swift` 落地 GBK POST 搜索、AES/Base64 解密、乱序恢复、拼音/字体字符映射与 WebJS 净化）。
2. [x] 固化 GBK / 登录验证 / AES/Base64 / 字体反爬 的失败分类（已在 `SourceDiagnosticClassifier.swift` 与 `SourceDiagnosticClassifierTests.swift` 补全断言）。
3. [x] 保证能力表、fixture bank、测试断言三者一致（`LegadoCapabilityBankTests.swift` 锁定 5 个 C 级源及其完整 label 集合）。
4. [x] 本地静态检查通过后，推 GitHub Actions 验证 iOS / unsigned IPA（双流水线全绿闭环通过）。

## 验收门槛

阶段完成必须同时满足：

1. [x] `git diff --check` 通过。
2. [x] 新增或更新的 XCTest 覆盖本阶段 C 级能力（`SourceEngineCLevelFixtureTests.swift`、`SourceDiagnosticClassifierTests.swift`、`LegadoCapabilityBankTests.swift`）。
3. [x] `docs/legado-source-capability-table-20260908.md` 与 fixture bank 一致。
4. [x] `progress.md` 更新本阶段范围、证据、未验证项和回滚点。
5. [x] GitHub Actions 的 iOS build/test 与 unsigned IPA 结果核对（双绿全过）：
   - 最终验证提交：`8f7b9d5`
   - iOS 测试流水线：[Run 34348482825](https://github.com/ztcsr5/SourceReadSwift/actions/runs/34348482825) (Status: completed, Conclusion: success)
   - Unsigned IPA 流水线：[Run 34348482839](https://github.com/ztcsr5/SourceReadSwift/actions/runs/34348482839) (Status: completed, Conclusion: success)

## 不在本阶段展开的内容

- 阅读器手感 / 120Hz / 自动翻页 / 朗读体验
- EPUB / RSS / 书架批量管理
- Web 写源 PC 访问
- App 图标 / 关于页 / 产品收尾

这些属于后续阶段。

## 后续入口

完成本阶段后，顺序进入：

1. Stage 33：阅读器体验与性能收口
2. Stage 34：产品功能补齐与 Flutter parity 收尾
