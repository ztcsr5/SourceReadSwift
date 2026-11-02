# build 3 当前素材

- 仅使用七张明确选定版本的真实书籍封面：三体、沙丘、小王子、霍比特人、哈利·波特与魔法石、1984、银河系漫游指南。原图未改动，来源/ISBN/尺寸/SHA256 见 BOOK-COVERS.json。
- 来源为 Open Library Covers API（文档 https://openlibrary.org/dev/docs/api/covers ），只下载七个指定封面 ID 用于私人离线 UI 研究，不爬取封面库，不在 App 启动时联网下载。
- 这些封面存在不同语言与出版版本，不是“纸间原创海报”；不据此宣称取得正式再分发许可。
- build 2 电影素材和此前六张虚构书封移动到 ReferenceArchive/Assets，不再属于应用资源目标。没有删除历史审查证据。
- 书籍简介与交互样段为本实验编写；样段明确不是原书正文，图表明确是引导示意。
- App 源码/资源不含 MP4/MOV/M4V、AVPlayer 或 `--lab-tour` 自动推进逻辑；CI 录制的是独立 XCTest 发出的真实手势，而不是 App 的播放素材。

---

## 历史素材记录（已归档，不代表当前打包内容）

# Artwork provenance · video-reference revision

- 用户于 2026-11-02 明确否决生成海报及自由创作方向。`CoverTide` 已从 app 资源删除，原图只在 Codex 生成图片历史保留，不再打包或展示。
- 当前界面图片来自用户提供 `D:/QQ游戏/Rex.1.0.2(b4).ipa` 中的 `RexDesign_RexDesign.bundle`：24 部影片的海报、背景与标题图，共 72 个未经改动的图片文件。原路径、字节数、SHA256 及 TMDB attribution 见 `REFERENCE-ASSETS.json`。
- 只用于用户明确授权的私人静态 UI 研究/视频对照。本地使用与正式发布的素材许可不是同一件事；这些参考图片不随正式纸间发布。
- 没有复制主程序、私有 Swift 代码、shader、字体、签名、补丁、账号或播放器。所有界面和动画用 SwiftUI 重新编写。
- 原先用户提供 MotionLab 的六张演示封面及图标仍在仓库，既有试读组件保留；不出现在当前对照版的首页及引导。
- 视频最后的“德里镇”等联网影片不在安装包样本库，未通过截图冒充可交互原生界面。当前首页使用同包内真实影视图片，对照构图/排版/横向片单/胶囊栏。
