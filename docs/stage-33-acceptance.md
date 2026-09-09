# Stage 33 验收清单：阅读器手感、性能与排版体验收口

## 目标

把 Native Swift / SwiftUI 阅读器的核心交互手感、120Hz ProMotion 流畅度、换章边界滑动平滑度、源阅读官方核心资源（主题、TXT 目录正则、在线 TTS、智能导航源）全面收口到位，达到商业级 iOS 阅读器体验。

## 本阶段范围

1. **源阅读官方核心资源深度对齐**：
   - `txtTocRule.json` 17 组标准工业级目录正则提取。
   - `readConfig.json` 6 大经典昼夜排版调色板。
   - `httpTTS.json` 在线朗读引擎规则与 URL 参数求值。
   - `browserSource.json` 通用智能导航源解析支持。
2. **120Hz ProMotion 与手势翻页**：
   - 纵向连续滑动换章边界无缝拼接（消除 offset 抖动/白屏）。
   - 平移/覆盖翻页动态阻尼与 120Hz 帧率策略。
   - 九宫格触控命中优化。
3. **朗读（TTS）与自动翻页**：
   - 跨章连续播放与后台播控。
   - 自动翻页速度调节与手势打断。
4. **自动化回归**：
   - 新增 `Stage33ReaderExperienceTests.swift` 并全量通过。
   - GitHub Actions 双流水线（iOS build/test 与 Unsigned IPA）双绿闭环。

## 验收门槛

1. [x] `git diff --check` 通过。
2. [x] 新增 `SourceReadSwiftTests/Stage33ReaderExperienceTests.swift` 覆盖上述核心能力。
3. [x] `progress.md` 记录实现、证据与闭环详情。
4. [x] GitHub Actions 双流水线全绿通过（iOS 测试通过 + 无签名 IPA 生成）。

## 验证证据与流水线闭环

- **Target Commit**: [`72ca891`](https://github.com/ztcsr5/SourceReadSwift/commit/72ca891)
- **iOS build & test (Authoritative Gate)**:
  - Run ID: [34350499824](https://github.com/ztcsr5/SourceReadSwift/actions/runs/34350499824)
  - Result: **SUCCESS** (全量测试套件 100% 通过)
- **Unsigned IPA Package (Release Packaging Gate)**:
  - Run ID: [34350499831](https://github.com/ztcsr5/SourceReadSwift/actions/runs/34350499831)
  - Result: **SUCCESS** (无签名 IPA 产物构建成功)

## Stage 33 状态：CLOSED & ACCEPTED

本阶段所有交互手感、排版调色板、目录正则和双 CI 流水线门禁均已 100% 达成，Stage 33 正式收口关闭。

## 后续入口

进入最终收尾阶段：
- **Stage 34**：EPUB / RSS / 书架批量 / Web 写源 PC 端 / 图标与产品收口。
