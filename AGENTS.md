# 图片输入与验收

- 送入模型或图片查看工具的每张图片必须不超过 1 MiB（1,048,576 字节）。
- 查看图片前运行 `python -B -X utf8 scripts/prepare_model_image.py <IMAGE>`，只打开返回的 `path`，并核对 `bytes`。
- 原始截图、视频和验收证据保持原样；压缩仅用于模型预览，不改变应用内图片画质或资源限制。
- `scripts/collect_reader_visuals.py` 的 `model_preview` 字段提供已检查的查看路径。
- 接手进度与未关闭事项保存在 `docs/release-1.1.7/QUALITY-137-STATUS.md`；禁止用旧 SHA 的测试结果证明新改动通过。
