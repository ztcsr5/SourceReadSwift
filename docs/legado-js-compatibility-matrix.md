# Legado JS 兼容矩阵（Swift 原生运行时）

本矩阵记录 SourceReadSwift 与 Flutter `LegadoJsEngine` 的高频交集，避免把“函数存在”误当作“行为已验证”。

## 已覆盖并有 XCTest

| 类别 | API/行为 | 验证 |
|---|---|---|
| 网络 | `java.ajax/get/post/fetch/connect/ajaxAll/head`、`URLConnection` 属性/流/状态 | `LegadoNativeBridgeTests`、`LegadoStage10CompatibilityTests` mock response |
| 解析 | `java.getString/getStringList/getElements`，CSS/XPath/JSONPath | `LegadoNativeBridgeTests`、规则解析测试 |
| DOM | `org.jsoup.Jsoup`、JXNode、元素/属性/兄弟节点链 | `LegadoNativeBridgeTests` |
| 存储 | `java.put/get/remove/getStr/putJson/getJson` | `LegadoNativeBridgeTests` |
| 编码 | Base64、字节数组、Hex、MD5/SHA/RIPEMD160/HMAC、AES、charset-aware String bytes、RSA facade | `LegadoNativeBridgeTests`、`LegadoStage10CompatibilityTests` |
| Java facade | `StringBuilder`、`HashMap`、`ArrayList`、`Pattern/Matcher`、`URL/URI` | `LegadoNativeBridgeTests`、`LegadoStage10CompatibilityTests` |
| Android facade | `Build`、`TextUtils`、`Base64` | JS prelude + runtime surface test |
| 模型 | source/book/chapter getter、variable map、VIP（布尔 `isVip` 不被标题启发式覆盖）、`chapter.isPay` 布尔 | model bridge tests、`JSCoreRuntimeTests.testChapterBooleanIsVipSurvivesFallbackInjection`、`testChapterBridgeExposesIsPayAsBoolean` |
| 付费动作 | `payAction` 的 `isTrue` 语义、`@js:` / `<js>`、纯 URL 短路 | `PayActionTests` |

## 设计约束

- JavaScriptCore 回调是同步的；外部网络只能通过 `RuleExecutionContext` 的 handler 注入。
- 文件/ZIP 访问保持在 `Documents/LegadoSandbox` 内，不读取或导出系统凭据。
- `java.net.URL.openConnection()` 返回现有连接链 facade，不绕过网络层。
- 未实现的 Android 专有能力应保持空值/可观测失败，不伪造真实登录、验证码或付费访问。

## Stage 10 兼容闭环（本轮）

- 增强 `java.net.URL.openConnection()`：请求头、超时、请求方法、输入/输出流、响应状态与响应头均通过 `RuleExecutionContext` fixture 走同步桥接。
- 补齐 Java 集合/字符串/正则高频方法：`StringBuilder` 变更、`HashMap` entry `setValue` 与批量操作、`ArrayList` 索引/集合操作、`Matcher` 查找/替换/region 元数据。
- 修复 CryptoJS binary `WordArray` 的 `sigBytes` 截断与 Hex/Base64 stringify；新增 RIPEMD-160 与 RSA（Security.framework，PEM/DER/base64 key）桥接。
- 增加 Stage 10 离线 XCTest，覆盖 URL/URI、URLConnection、ByteArrayInputStream、集合、正则、缓存/window/document/source 元数据、Flutter 工具别名与二进制 WordArray。

## 下一批兼容项

1. 更完整的 `java.util.regex.Matcher`（`start/end/groupCount`）。
2. Jsoup `Document` 的 `location`, `head`, `body`, `title` 与资源绝对 URL 回归。
3. 真实书源样本脱敏后的 search/detail/toc/content 端到端 fixture。

## Stage 25：跨阶段与字体/加密兼容性

本阶段把安卓开源阅读高频但容易在 JavaScriptCore 上断链的能力接到同一条
Swift 原生桥：

| 类别 | API/行为 | 当前范围与证据 |
|---|---|---|
| RSA 工厂 | `java.createAsymmetricCrypto` 的 `setPublicKey/setPrivateKey/encryptBase64/decryptBase64` | Security.framework；PKCS#1/PKCS#8、PEM/DER/base64；离线 Stage 25 XCTest |
| RSA 签名 | `java.createSign` 的 `initSign/initVerify/update/signBase64/signHex/verify*` | PKCS#1 v1.5 与 PSS 常用 SHA-1/224/256/384/512；离线 Stage 25 XCTest |
| 反爬字体 | `java.queryTTF`、cmap 0/4/6、loca/glyf、复合 glyph、Unicode 反查 | `QueryTTF.swift`；坐标保持 Legado 的 delta 指纹格式；离线 fixture |
| 验证码 | `java.getVerificationCode` | Stage 35 UI 人工闭环：同步桥弹出 SwiftUI Sheet，携带书源 Cookie 拉取图片，支持刷新/取消/超时；结果写入 `captcha:<absoluteUrl>` 缓存；无 OCR 猜测，缺失时记录 `verification-required` |
| 压缩包 | `java.unArchiveFile`、`un7zFile`、`unrarFile` | ZIP 继续走 ZIPFoundation；7z/RAR 显式返回空值并记录 unsupported，避免伪造成功 |
| 多阶段状态 | Search → Detail → TOC → Content 的 `bodyJs`、header/token、混合响应 | `LegadoStage25CompatibilityTests` 离线网络 fixture |
| HTTP/DOM | `ajaxAll`、Fetch POST、响应 bytes/status/final URL/header、JSONPath + Jsoup 链 | `LegadoStage25CompatibilityTests` 离线网络 fixture |

### 运行与发布边界

- JavaScriptCore 回调仍是同步桥；字体 HTTP 获取复用现有 `RuleExecutionContext`
  response/network handler，不在 JS 中直接打开网络。
- 7z/RAR 不在当前 iOS 依赖中实现；书源应改用 ZIP、预解压资源或导入本地 fixture。
- 验证码识别已接入阅读器 UI 人工闭环（Stage 35）：图片 URL 统一解析为绝对地址后作为缓存键，超时或取消返回空值并记录 `verification-required`；OCR 自动识别仍不在范围内。
- Windows 无法运行 Xcode/UIKit/XCTest；Stage 25 的 iOS 编译、XCTest 与 unsigned IPA
  以 GitHub Actions 为准，真机 120 Hz 仍需 ProMotion 设备验收。

## Stage 36：`imageDecode` 内联图像负载（v1.0.26）

`ruleContent.imageDecode` 的返回值不再只按 URL 处理。`InlineImageDecoder` 覆盖：

| 负载形态 | 示例 | 处理 |
|---|---|---|
| data URI | `data:image/png;base64,...` | 解码、魔数校验、入库 |
| 裸 base64 | `iVBORw0...` | 同上 |
| JS 字节数组 | `[137,80,78,71,...]` | JSON 解析为 `Data` 后同上 |
| 数字键对象 | `{"0":137,"1":80,...}` | 同上 |

- 只接受魔数可识别的 png/jpg/gif/webp/bmp/tiff/heic/avif；单图上限 32 MB。
- 段落写 `srdata://inline/<sha256>.<ext>`，由 `InlineImageStore` 去重落盘、`RemoteImageLoader` 解码渲染。
- 普通 URL 仍走原有绝对化路径；非法负载保留原 URL 并记日志。
- 回归：`InlineImagePipelineTests` 7 个用例（含 `java.ajaxBytes` 经 `RemoteImageLoader` 的真实解码）。
