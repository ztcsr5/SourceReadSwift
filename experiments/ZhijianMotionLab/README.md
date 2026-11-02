# 纸间 · 阅读动效实验 · 0.1.0 / build 3

独立 bundle `com.edc21.ZhijianMotionLab`，iOS 16+，不覆盖正式纸间。build 3 把影视对照改成书籍产品，并补上用户指出缺失的真实滑动。六幕是：景深书海、可纵向浏览的书架、可翻面的藏书票、可点击更新的阅读进度、TXT/EPUB/PDF/有声/书源轨道、可滚动阅读看板。全程可左右滑动、返回、跳过，不强制等 1.8 秒。首两幕是同组封面节点按手指进度插值，不是逐页视频。

## 安装 / 运行
macOS 安装 Xcode 与 XcodeGen，在本目录运行 `xcodegen generate`，打开生成的同名 xcodeproj/scheme。测试 IPA 需要自行签名侧载。七本书封来自 Open Library 指定版本，清单见 `docs/BOOK-COVERS.json`；只用于私人视觉实验。首页可左右切书、查看简介、进入真实样段阅读器、保存位置和书笺。样段由本实验编写，明确不是原书正文。新引导使用独立版本标记，升级后会展示，不清空正式或旧实验数据。

## 测试
`xcodebuild -project ZhijianMotionLab.xcodeproj -scheme ZhijianMotionLab -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO test`。CI 先跑单测与左右滑动回归，再单独执行完整交互用例并录下真实模拟器手势；两部分都是强制验收，不用 App 自动翻页录屏。验证短拖/边界/速度预测、320/390/半程拖动形态、票根翻面、章节变化、图表切换、书笺持久化、搜索关闭、重播和跳过。没有实测 FPS 或物理设备流畅度声明。

## 回滚 / 边界
卸载“纸间·动效实验”即可。正式 App 与配置无改动；未接入真实书源/付费正文/漫画引擎。build 2 影视材料归档在 `ReferenceArchive/`，不打入新 App；被否决的 CoverTide 依旧不打包。当前 checkpoint 和真实验证状态见 `docs/STATUS.md`。没有新增 App 运行时依赖。
