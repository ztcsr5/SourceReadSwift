# WEBTOON、启动与寻书调整

## 实际改动

- WEBTOON 导出里的登录配置实际是漫画/CANVAS 切换，搜索地址还包含 `undefined` 语言段。配置表单现在可打开真正的网站浏览器并沿用 Cookie 保存；修复脚本纠正语言段及正文页图提取。原始导出和如漫画规则不改。
- 生产冷启动先从本地恢复真实书架、分组和阅读位置，完整书源的解码及迁移在后台进行。源相关页面、阅读器、外部导入、下拉更新和 WebDAV/备份入口均等待恢复完成；SourceStore 加载中禁止写回。初始短暂本地读取延续静态纸面，不再显示“正在打开书架”进度文案。
- 设置页章节/RSS 缓存由后台 factory 读取；正文检查、字节统计与预取修剪也在后台进行。并发准备合并，读取期间如果阅读器已创建 Store，不覆盖其状态。
- 设置内容只接收稳定 AppState 引用和源恢复状态，减少无关诊断广播重画列表。搜书的全部书源不再每次页面构建时展开成菜单，改成按需打开、可搜索的惰性列表。
- 寻书按类型、当前书源、账号/管理、分类索引、常逛和书单组织；全局搜书、用户手动类型和已有主题保留。不新增持续模糊、定时动画或依赖，不更改 120 Hz 配置。

## WEBTOON 规则与证据

用户修复包已放到桌面 `WEBTOON与如漫画_修复版_20261126.json`，在书源管理重新导入即可。它保留用户导出的原始私有 header，不加入仓库。生成同等修复包的命令（输出须是尚不存在的新文件）：

```powershell
python -B -X utf8 scripts/repair_webtoon_source.py <原始导出.json> <新修复包.json>
```

使用源自带移动 User-Agent、不带 Cookie 实测：搜索找到《純情大作戰》，目录返回 144 章，公开序章 HTTP 200；真实正文 JS 提取 43 张页图，首图 HTTP 200、image/png 且魔数匹配。证据位于本机 `output/webtoon-20261126/ANONYMOUS-PROBE.json`。这证明该公开样章不要求登录，不代表会员/受限章节或真实账号已验证。

## 检查与限制

```powershell
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
python -B -X utf8 scripts/audit_current_swift_syntax.py 00c86be5170f571e8a67fde4edeaa0978cc91e8c --output output/WEBTOON-LAUNCH-DISCOVER-SYNTAX.json
git diff --check
```

当前本地共 330 项 Python 检查，329 项通过、1 项跳过；变更 Swift 语法相对基线无新增诊断。新增原生测试涵盖缓存后台读取与保留、源库阻塞时真实书架先出、并发缓存准备、加载期禁写和损坏源保留；启动、缓存、选源和登录地址测试已纳入原生 CI 选择。原生 XCTest、iOS 16/17/26 页面渲染及 LiveContainer 帧时间仍需当前提交的 iOS 构建/设备验证，Windows 检查不能代替。

冷启动仍需真实书架文件读取，不能承诺任意体量书库零毫秒进入；未宣称达到固定帧率、全量书源 90% 或账号登录成功。

## 回滚

对包含本记录的提交使用 `git revert`；无需迁移用户书架格式。修复后的两源 JSON 独立可导入，回滚规则可重新导入用户原始导出。
