# UI 参考图补充（2026-09-07）

本目录保存用户补充的 8 张界面参考图，作为 SwiftUI 视觉验收基线。图片中的真实站点、URL、账号、Cookie、token 仅作视觉示例，不得复制到源码、fixture 或诊断报告。

## 视觉基线

- 诊断日志：浅灰背景、白色圆角卡片；阶段名加粗；HTTP status/method/bytes/contentType 分层展示；Cookie/Set-Cookie 只显示存在性。
- 规则编辑：搜索｜详情｜目录｜正文四段式切换；诊断修复入口、响应摘要、本地样本、复制按钮、失败原因和修复建议必须可见。
- 书源详情：书源名、URL、测试关键词、开始测试、规则覆盖、Search → Detail → TOC → Content 链路、PASS/WARN/FAIL 和可复制报告。
- 底部安全区：内容滚动到末尾时不得被底栏遮挡；卡片和按钮在动态字体下仍保持可读。
- 可用性：长 URL 使用可换行等宽文本；错误信息要区分超时、HTTP 错误、空解析、JS 异常和反爬拦截。

## 文件

- `reference-1.jpg`、`reference-2.jpg`：诊断日志列表
- `reference-3.jpg`、`reference-4.jpg`：规则编辑器
- `reference-5.jpg`、`reference-6.jpg`、`reference-7.jpg`：书源详情诊断

- `reference-8.jpg`: 主页内容卡片、横向推荐列表和底部迷你播放器（补充视觉基线）


