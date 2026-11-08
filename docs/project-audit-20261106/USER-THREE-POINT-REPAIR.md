# 按用户三点方案落地：待原生验收

## 改了什么

- `ReaderExitSwipeBridge.swift`：needsFallback仅由exitEnabled决定；系统只有began/changed/ended才阻止兜底，failed/cancelled不冒充接管；不替换系统delegate，不对原生返回设置反向失败优先级，完成时再检查系统是否已接管以免重复退出。
- `ReaderView.swift`：正文可系统返回时也启用兜底；否则菜单关闭仍会让exitEnabled=false，单改桥接条件无效。分页、选择和遮罩继续沿原allowsNativeBookReturn/菜单策略限制。
- `ComicImageTransport.swift`：复制配置后显式回填protocolClasses；响应拒绝同时看response.expectedContentLength与dataTask.countOfBytesExpectedToReceive，仍保留Content-Length和逐chunk上限。先提交应用拒绝再取消的前一补丁保留。
- `RemoteImageLoader.swift`：新增可选configuration参数，保持所有既有调用兼容；显式配置也用于没有注入session时的普通会话。漫画测试9处全部传原始configuration。
- `ReaderExitSwipeTests.swift`、`RemoteComicImageTests.swift`：补系统failed/cancelled状态、隐藏导航栏不禁用兜底且保留delegate、任务预期长度及显式配置覆盖另一会话默认值；声明长度/chunked两分支均验证自定义URLProtocol确实拦截，防止把访问真网当测试。原实际4秒拒绝和stopLoading断言未变。
- `FloatingReadingDeskUITests.swift`：只将搜索进入详情的标题等待改为10秒，记录GLOBAL_SEARCH_DETAIL_WAIT_SECONDS，失败时附图；书名必须等于剑来等原断言不变。
- Python契约覆盖启用端、配置传递和元数据；先确认3项失败，再合入转绿。

## 影响面

- 常驻仅限exitEnabled=true的阅读范围，不是全局窗口手势，也不无条件开放分页或文本选择返回。原生gesture delegate保持不变。
- configuration为可选新增参数，无破坏性迁移。应用漫画上限仍24MiB；模型预览仍独立限制1MiB。
- 原先chunked夹具已经通过，不能未验证就断言所有protocolClasses都丢失；显式配置与hasStarted断言将验证配置来源。SecKey -50、WebProcess NearSuspended未作为根因改动。

## 怎么验证

```powershell
Set-Location -LiteralPath 'D:\Gemini反重力\SourceReadSwift2'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
python -B -X utf8 scripts/audit_current_swift_syntax.py bea8d773
git diff --check
```

实跑129项Python通过；7个Swift差异文件无新增parser诊断；diff检查通过。Swift/iOS运行未执行，不把这些结果写成原生通过。自动整轮派发仍保持停止；未推新完整工作流，未打包。

必须保留的定向原生项：RemoteComicImageTests的声明/无声明超限及原协议拦截、ReaderExitSwipeTests、真实减少动态长/短返回和全局搜索UI。后两类必须看原始操作/导航结果，不能只看日志噪声或宽松快照。

## 怎么回滚

只撤回本次用户三点补丁，保留此前漫画取消顺序等原有工作：

```powershell
git -C 'D:\Gemini反重力\SourceReadSwift2' apply 'F:/SourceReadSwift/project-audit-20261106/user-three-point-before-merge/ROLLBACK.patch'
```

已实跑git apply --check通过，未应用补丁；未更改用户索引。

## 尚不能宣布关闭

兜底当前在手势ended时请求退出，只能恢复抬手返回，不等同于系统跟手交互取消。nativeBookGestureEvidence原本只数系统手势，不能为了兜底通过而把计数改成自定义手势。原有运动/取消断言没有删，侧滑门禁仍须原生验收。10秒等待仅是用户要求的转场等待预算调整，不是导航根因证明。
