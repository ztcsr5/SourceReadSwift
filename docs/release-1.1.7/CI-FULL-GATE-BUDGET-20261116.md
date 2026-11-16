# 全量 CI：注册与 UI 步骤预算修复

## 证据与结论

审查对象是 `b88fe0356d658e8c5b097d2d0e767601cc0ad957` 的 [iOS run 43832253240](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43832253240)。普通 build 与 iOS 17.5 通过；iOS 16.4 和 iOS 26 的下列步骤超时，整个 run 仍是 failure，不能把局部测试成功当作全量绿灯。

| 步骤 | 日志中的实际结果 | 原预算问题 |
| --- | --- | --- |
| iOS 16.4 注册；job `133180141115` | 08:47:07 UTC 开始；08:52:11 打印 App 已注册，08:52:16 打印 UI runner 已注册 | 约 309 秒才完成，两项成功后立即报 `The action 'Register the legacy test bundles' has timed out after 5 minutes.`；产品测试因此未执行 |
| iOS 26 设置与漫画 UI；job `133180141083` | 08:55:38 UTC 开始；15 项测试、0 failures，执行耗时 847.309 秒；09:10:21 全部测试结束 | 09:10:51 步骤报 15 分钟超时；保存的日志仍记录 09:10:54 的结果收集完成和 `TEST EXECUTE SUCCEEDED`。测试启动与结果收集也消耗步骤时间 |

iOS 17.5 对照 job `133180141215` 的同一注册步骤约 47 秒完成。iOS 16.4 日志没有逐条 install/get_app_container 耗时，不能进一步认定是哪条 CoreSimulator 命令慢，也没有证据要求重置模拟器或延长产品等待断言。

原合并 UI 步骤中，漫画 3 项耗时 267.749 秒，恢复正文 1 项耗时 48.904 秒，阅读设置 11 项耗时 530.648 秒。后续新增用例使合并步骤更拥挤；用独立步骤分摊总预算，保留每用例的原有截止时间。

## 实际修改

- `.github/workflows/ios.yml`：注册步骤从 5 分钟改为有界 8 分钟，保留两次安装、两个 bundle 的目录核实和失败退出。
- 同一工作流：`ReaderSettingsFlowUITests` 和恢复正文用例仍留在原 15 分钟步骤；整个 `ComicReaderFlowUITests` 类移入独立 12 分钟步骤，自动包含该类新增用例。两步均保留单用例 180 秒、destination 120 秒、串行执行与 `test-without-building`。
- 新漫画步骤沿用 `!cancelled() && steps.native-build.outcome == 'success'`，此前设置步骤失败时仍执行；后面的连续阅读、手势与往返步骤条件不变。未使用 `continue-on-error` 或 skip 放行失败。
- 新增 `NativeComicUIResults.xcresult`、`native-comic-ui-test.log` 和 `native-ui-snapshots/comic`。漫画日志在后续 UI 前以 always 条件独立上传；结果包、日志及导出的截图也纳入最终证据和紧凑截图 artifact。
- `scripts/test_reader_controls_workflow.py`：增加完整测试选择保留、分步预算、失败后继续运行、独立证据保存检查；原阅读设置 15 分钟、手势 11 分钟与单用例期限检查全部保留。

## 验证与证据位置

先加入检查再修改工作流：`test_reader_controls_workflow.py` 为 16 项、4 failures，分别暴露缺少漫画独立执行/日志步骤及旧 5 分钟注册预算；修改工作流后同一命令为 16 项、0 failures。

```powershell
python -B -X utf8 -m unittest discover -s scripts -p test_reader_controls_workflow.py -q
git diff --check
```

另用已安装的 PyYAML 解析工作流：3 个 job、步骤名称唯一、设置/漫画/注册预算为 15/12/8 分钟，设置与漫画执行条件一致。用 Counter 对比修改前后全部 `-only-testing:` 选择器，集合及出现次数完全相同；没有新增 `-skip-testing:`。这些是工作流结构检查，未执行新的 GitHub Actions 原生回归，也没有 dispatch。

原始证据保存在 `F:/SourceReadSwift/batches-20261116/full-gate-review/`：

| 文件或 artifact | 字节数 | SHA-256 |
| --- | ---: | --- |
| `job-133180141083.log` | 2,843,353 | `1889129c6b4866d2569774f6fef98dcd6846cda37708d43dd3b76d0ed108bdee` |
| `job-133180141115.log` | 2,472,875 | `0da7413e407856309517b647be77ac5b8945992e176c5703a647551a43dcd57c` |
| `job-133180141215.log` | 2,065,685 | `358616f49a7d7689316024b7319cbbcc0ae669c124cfbb481ce359c1dc27a372` |
| 设置日志 artifact `14212035700` ZIP | 17,086 | `cd6c29063f5fa1e51a00217d3f2380fca8fcdd7a42f5d35346816bb141acfee2` |
| iOS 16.4 artifact `14210142628` ZIP | 77,252 | `359e1f40e54b10ed5ac07bd6cae7ee3be842d58ef8325d64631f1bce2c5c928d` |

## 影响与回滚

仅调整 CI 步骤组织与基础设施预算，不修改应用、Swift 用例、单用例断言或数据格式。最终需要在同一提交上以默认完整模式运行 `ios.yml`，逐项核对实际测试数、无漏选和 artifact，再确认设备 IPA 构建；本地检查不能替代这轮运行。回滚时对本次独立 CI 提交执行 `git revert <CI_COMMIT>`，不会回滚媒体或阅读器实现。
