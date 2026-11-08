# Build 137 集中验收

终版交付 SHA：`e2f4c7ff5f8ec170e9f81dd71bde5c2f6c528fb4`；原生回归 Run `42305125218`（100% 成功，iOS 18 + iOS 26 双平台通过）；未签名打包 Run `42310971743`（100% 成功，桌面 IPA 已生成并校验）。

## 要求与验证对应

| 项目 | 本轮实现和回归范围 | 验证入口 |
|---|---|---|
| F01 开书与续读 | 冷目录后台读取；WebKit navigation token/迟到 ready；真实长段落与重启游标 | ReaderModePositionRegressionTests、FloatingReadingDeskUITests |
| F02 正式扉页 | 首次扉页、所属详情、之后直达正文 | FloatingReadingDeskUITests/testFirstReadingHasARealTitlePageAndLaterResumesDirectly |
| F03 顶部菜单 | 菜单身份缓存、生命周期触摸保护、设置退场释放点击 | ReaderSettingsFlowUITests、ReaderControlsMaterialTests |
| F04 章节衔接 | 增量 DOM、过时 revision 拒绝、前插锚点、实际正反跨章与重开 | WebReaderDocumentTests、真实 Chromium 检查、FloatingReadingDeskUITests |
| F05 外观 | 保留森林首页和白紫方案；10 主题明暗共 20 张、设置窄屏大字 | Release116VisualTests、Release117AppearanceTests、FloatingReadingDeskUITests |
| F06 全局流畅度 | 缓存/历史局部通知、书源索引、热图片首帧、2 路解码、阻塞规则移出协作线程 | AppFrameProfilerTests、SourceOrganizationTests、RemoteComicImageTests、BlockingRuleExecutorTests |
| F07 操作连续 | 设置二级返回、仿真三进三退、交互返回取消/完成、底栏恢复 | ReaderSettingsFlowUITests、FloatingReadingDeskUITests、ReaderTabChromeExitTests |
| F08 试读退出 | 小说/漫画退出提醒、取消/加入、等真实写盘后可重启续读 | ReaderSettingsFlowUITests、ComicReaderFlowUITests |
| C01–C04 漫画显示 | 独立原生条漫、复用、迟到尺寸补偿、LTR/RTL、双击/双指/平移与恢复翻页 | ComicStripLayoutTests、ComicZoomInteractionTests、ComicPagingBoundaryUITests |
| C05–C07 图片与解析 | 请求上下文隔离、4 路传输/2 路解码、取消、明确错误、完整分页标记、HTML/JSON/懒图解析 | RemoteComicImageTests、ComicContentParserTests、SourceEngineStage18FixtureTests |
| C08–C09 连续与位置 | 首末页跨话、上一话末页、页内比例、来源/章节/图片身份、实际重启 | ComicReadingPositionTests、ComicReaderFlowUITests、ComicPagingBoundaryUITests |
| C10 离线与 CBZ | 逐页验证后原子提交、独立存储、断源和清普通缓存后仍可读、CBZ 自然排序与受控删除 | ComicOfflineArchiveTests、LocalComicBookParserTests、真实 CBZ UI |
| C11 控件 | 明图可读控件、菜单/目录/缩放互斥、试读入架返回 | ReaderControlsMaterialTests、ComicReaderFlowUITests |
| C12 综合 | 240 页真实图片复用与取消、两套 SDK、全单测与原生 UI、IPA 与 dSYM 同 SHA | ios.yml、unsigned-ipa.yml、IPA_VERIFICATION.json |

## 检测口径

- iOS 18 执行全量 XCTest 与全部 UI；iOS 26 执行选定原生/兼容单测与阅读器 UI、章节连续 UI。iOS 18 中两项 Requires Xcode26 SDK 条件跳过，在 iOS 26 执行。
- 本地 90 项结构/浏览器检查不能代替 iOS SDK 类型检查或真机验收。
- 31 配置真实源探测：只覆盖每源首本/首章及首中末图片抽样。验证页、拒绝访问、空结果、失效接口与串流内容分别记录，不能推导全站所有书可用。
- 240 页复用/取消测试验证资源释放边界，不是长时间真机 RSS 曲线。

## 已知边界

- 无连接 iPhone 的 Instruments：真实呈现 FPS、长时间 RSS、触摸延迟、温升未测。
- 用户原 QQ→Files 12 MB TTF 未取得；合成/本地副本用例通过也不等于该原文件通过。
- CBZ 文件保存在应用私有目录，旧 JSON 备份仅元数据，未实现跨设备搬运图片；删除应用前需保留原 CBZ。
- IPA 为未签名设备包，须 LiveContainer 或用户现有签名方式安装；此处不代签、不声称真机已安装。

## 复核与回滚

仓库根运行：

```powershell
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
git diff --check
$env:READER_CI_RESOLVED_ROUTE='1'
python -B -X utf8 scripts/verify_reader_quality.py status
```

IPA 完成后用 `Get-FileHash -Algorithm SHA256 <IPA绝对路径>` 与 IPA_VERIFICATION.json 比对。
用户 HEAD/index 与旧 IPA 保留；安装测试版前导出当前书架和保留原导入文件，回退时用原安装器导入上一版 IPA。不执行 git reset --hard 覆盖用户原有改动。
