# 三个失败点的收敛修复与定向验证

## 改了什么

1. 漫画夹具和真实安全边界分开：OversizedComicImageURLProtocol每条路径明确完成或报错，不再挂起；保留testOversizedComicResponsesStopBeforeTheServerFinishes名称和4秒门限，改用127.0.0.1真实HTTP。声明长度模式只发超大Content-Length、零正文、不发FIN；chunked模式发超限有效chunk、不发终止chunk/FIN。必须返回tooLarge并观测到真实连接由客户端关闭，测试服务只监听回环地址、使用临时端口、结束时清理。
2. 搜索实际点击处理先释放FocusState，再保存明确的selectedEntry，通过列表外navigationDestination进入详情；返回仍保留原查询。键盘提交也释放焦点。原搜索UI用例保留书名断言，并新增进入详情后键盘必须消失；不靠测试点击空白绕开产品路径。
3. 返回路由区分普通与减动效。普通正文保持原生缩放路线，不常驻兜底抢手势（#700普通iOS18回归发生在上轮启用所有正文兜底后）。减动效正文允许兜底；兜底require原生edge先失败，只有原生真正拒绝才接手。仍不替换系统delegate，不等待全内容pop造成依赖环。
4. 减动效不再只检查稳定页面：必须记录到真实native或fallback的began→changed且有触摸，然后取消保留同一书/段落，长拖回真实书架，再重开保位。原native探针保留且普通模式仍严格要求native增量>0；两个计数均0时减动效也必失败。fallback的DEBUG计数不伪装成native，不作帧率证据，直接调用退出回调不会计输入。
5. 定向验证仅运行RemoteComicImageTests、ReaderExitSwipeTests、GlobalSearchIndexTests，以及搜索、普通/减动效长短返回、跨章和漫画分页边界的现有真实UI路径。完整门禁和操作等待不改；新定向成功也不能触发IPA。

## 影响面

- 无新第三方依赖；测试服务用项目已有Network.framework，生产搜索/返回仍用既有SwiftUI/UIKit。视频、AI网关和凭据不变。
- 减动效参数是应用内偏好，不等于把模拟器的系统辅助功能开关改了；不能以系统自动忽略触摸解释0输入。
- #700已结束失败：除漫画declared和减动效输入外，iOS18有一次跨章AX snapshot失败、iOS26有一次漫画RTL落页失败。定向选择保留这两条，不仅看旧的三行日志。搜索10秒在#700未报失败，但不因此证明所有点击都可靠。
- #700中自定义protocol确实拦截；显式配置/任务预期长度/取消重入用例已通过，但declared仍超时，配置丢失不是该轮已证实根因。新真实HTTP测试用于把协议桩语义与真实取消分开验证。

## 怎么验证

```powershell
Set-Location -LiteralPath 'D:\Gemini反重力\SourceReadSwift2'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
python -B -X utf8 scripts/audit_current_swift_syntax.py 8f191946
python -B -X utf8 scripts/verify_reader_diagnostics.py status
git diff --check
```

实际本地137项通过、7个Swift差异无新增parser诊断、diff检查通过。新Swift/iOS代码尚待定向运行，不冒充原生绿。

定向快照 `2629ce547eb2eafaa95077ff8de16dd897d2d518`，分支 `codex/reader-quality-137-diag-2629ce547eb2`。为避免把新workflow放默认分支，只在临时索引里把已注册ios.yml入口替换为定向模板，工作树完整ios.yml不变；Git索引保持。DIAGNOSTICS-LATEST/STATUS与完整LATEST/STATUS分别记录，防重叠和同树重复派发。

诊断绿不能交付：job名focused-ios26不满足build/native-tabs及其必需步骤，已有回归验证发布守卫会拒绝；工作树完整workflow与诊断提交也不同。之后仍需同SHA完整双系统和人工视觉，所有本轮开放门禁关闭后才能打包。

## 怎么回滚

已生成并git apply --check通过，未应用；退回#700代码而保留此前接手改动：

```powershell
git -C 'D:\Gemini反重力\SourceReadSwift2' apply 'F:/SourceReadSwift/project-audit-20261106/convergence-before-merge/ROLLBACK.patch'
```

API核对：[Apple requiredLocalEndpoint](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint) 明确用于约束连接及监听器本地IP/端口；现有项目SourceWritingView已使用NWListener/receive/send相同基础接口。官方页面的Markdown签名已核对，未按猜测造网络API。

当前定向运行：https://github.com/ztcsr5/SourceReadSwift/actions/runs/42234536674，状态in_progress。
