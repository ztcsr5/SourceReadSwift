# 76 源接管核验与修复 · 1.0.104 / Build 105

日期：2026-10-29。输入仍是原始 `D:/QQ游戏/shareBookSource11.json`，不修改私人书源，不把新规则包与旧输入混合统计。

## 已核对的事实

- 76 个输入与旧测试记录按「名称 + 原始 URL」一一匹配，而非按异步结果数组下标匹配。
- 旧基线仍是 8 PASS4、20 无规则条目、48 条其它结果。本次修复尚无新的真机统计，不能修改 PASS 数。
- #31 七猫听书、#55 有听网的 `bookSourceType` 都是 1（音频）。115/208 字符不能作为小说正文完整性的证据；需要验证音频资源和播放。
- 原始文件中 30 条有 loginUrl、27 条有 loginUi，其中 14 条 loginUi 是 JS。
- 项目原已存在登录 UI、Cookie 存储、DES 和 encryptHex。缺口是兼容细节及链路，不是完全没有实现。
- 超时、403、404、500、TLS 断开只能描述当次请求；未分层复测前，不应标记永久死亡或给出所谓可修数量天花板。

## 本次修复

1. **JS 规则作用域**：规则通过原始间接 eval 执行；保持完成值、strict mode、共享 var/函数，隔离每次规则的 let/const。jsLib 仍在共享全局执行一次。
2. **库初始化时序**：全部 source/book/key/baseUrl 等参数绑定后才执行 jsLib，避免固定空地址/空配置。库异常直接报告，不能缓存成成功，也不能重复初始化副作用。
3. **动态登录表单**：loginUi JS 与 loginUrl 模块定义在同一运行时求值；按钮脚本通过引擎执行，菜单操作后重新求值；保留选项和默认值。
4. **登录上下文**：新表单/动作路径使用与搜索相同的注入网络、源级变量和 Cookie。支持使用库内地址恢复的名称型书源。输入仅供用户实际登录，不伪造上游认证。
5. **登录地址识别**：JS 的 `//` 配置注释不能误识别为网址；脚本模块不能作为站点相对路径打开。登录中心、源列表和阅读器入口采用同一源级地址解析。
6. **版本一致性**：project.yml 设为 1.0.104 / Build 105；Info.plist 使用构建变量，避免遗留 1.0.96/97。

## 已执行验证与边界

- Node/ECMAScript 最小实验复现两种旧故障，并验证间接 eval 的重复执行、共享声明、完成值及 strict mode。
- 原始 #13 书山聚合、#19 STV、#45 UAA 的 bookUrl 脚本，使用模拟宿主方法连续执行各 3 次通过。旧方式分别重现 source、_saved、type 声明冲突。
- 这些是脚本兼容实验，不是 Swift/iPhone 全链路验收，更不是上游可用性证明。
- 新增 `JSCoreRuntimeLifecycleTests.swift` 与 `SourceDynamicLoginTests.swift`，覆盖重复行、库加载、错误传播、动态菜单、登录动作与后续搜索的请求头/Cookie 连续性。
- iOS 构建、XCTest、IPA 状态以 CI 实际结果为准；真机局域网当前连接超时，76 源新一轮全链路：**NOT RUN**。
- iOS 16 设备/模拟器显示验证：**NOT RUN**。本次不改阅读器排版、首行缩进或翻页动画。

## 验证材料

- `E:/codex-temp/sourceread/artifacts/takeover/sources76-evidence.json`：76 条输入与旧基线的匹配账本。
- `E:/codex-temp/sourceread/artifacts/takeover/runtime-baseline.json`：ECMAScript 最小实验。
- `E:/codex-temp/sourceread/artifacts/takeover/real-script-regression.json`：三个真实书源脚本的宿主模拟实验。
- `E:/codex-temp/sourceread/artifacts/takeover/baseline/`：本次修改前副本，原书源文件未改。

## 后续验收顺序

先检验本次运行时/动态登录链路，再复测 76 源。每条记录搜索/详情/目录/正文或媒体分阶段结果；网络失败、需要用户登录、无规则、规则异常、空结果分别记录。相同关键词/输入包/并发/超时/重试口径下对账，不用旧 PASS 与新 PASS 直接相减来推断退化。

登录凭据跨 App 重启的安全持久化、表单高级布局/任意控件、登录检查响应语义、音频实际播放及 iOS 16 显示矩阵仍需后续验证，不在本次宣称完成。
