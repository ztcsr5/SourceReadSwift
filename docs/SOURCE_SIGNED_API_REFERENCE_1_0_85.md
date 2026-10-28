# 带签名书源参考（1.0.85）

外部资料位置：`D:\QQ游戏`。本节只记录“能不能用于本项目的书源引擎”，不复制原文。

## 结论表

| 资料 | 与书源引擎的关系 | 处理 |
|---|---|---|
| `七猫纯小说_接口算法与鉴权分析.md` | 直接可用。参数签名、请求头签名、AES 正文解密都落在现有 JS 桥能力内 | 已落成 `QimaoSignatureTests` 三条固定向量；语料含 10 条 `api-bc.wtzw.com` 源 |
| `番茄纯小说_接口算法与鉴权分析.md` | 算法完整，但 `all_book_sources.json` 997 条里没有 `fqnovel.com` 源 | 暂不硬编码；等源 JSON 到位后按本文对拍 |
| `README.md` / `接口总览*.md` / `接口鉴权逻辑.md` / `踩坑清单.md` / `成果验收总表.md` / `风险评估报告.md` / `限免权益实录.md` | 起点读书 App 逆向，不是 Legado 书源；方法可借鉴，协议不能直接套 | 作为签名/设备头/密文解密的工程模板，不进书源运行时 |

## 七猫：已对齐的部分

签名算法（文档 §3）：

```
paramSign  = MD5(sorted("k=v" concatenation) + "d3dGiJc651gSQ8w1")
headerSign = MD5(fixed-order "k=v" concatenation + same salt)
```

`QimaoSignatureTests` 固定值：

| 项 | 期望 |
|---|---|
| page1 paramSign | `0c85373002b897710cae9b8aff9a60a5` |
| page2 paramSign | `5e2dd3b0eeb9b5a00333455858002d44` |
| headerSign | `fc697243ab534ebaf51d2fa80f251cb4` |

正文链路（文档 §6）：base64 → 前 16 字节 IV → `AES/CBC/PKCS5Padding`，key `242ccb8230d709e1` → 若 `PK` 开头再解 EPUB。现有桥已覆盖：

- `JavaImporter` + `javax.crypto` + `SecretKeySpec` + `IvParameterSpec`（`CloudCollectionRuleTests.testJavaImporterAndCipherPipeline`）
- `java.aesDecodeToString` / `java.aesDecodeToByteArray` / `java.base64DecodeToByteArray`
- `java.gunzip` / `java.unzipFile`
- `java.md5Encode`

因此七猫不是“只通了搜索 URL”，正文解密路径也有单元测试托底；真机仍受站点风控与网络影响。

## 番茄：资料价值与接入条件

文档给出的签名头不是单个 MD5，而是 `X-Gorgon`、`X-Helios`、`X-Medusa` 多层组合，内部含 SM3、自定义 AES、protobuf 打包和按时间搜索 khronos。它是纯 JS 实现，理论上可放进 Legado `jsLib` 由 JavaScriptCore 执行，不需要新增原生代码。

当前不接入的原因只有一个：语料里没有番茄源。接入步骤：

1. 放入 `番茄小说v2.0.json`，确认 `bookSourceUrl` 与 `jsLib` 完整；
2. 用文档 §5 的固定查询构造一组 `X-Gorgon` / `X-Medusa` 期望值；
3. 新增 `TomatoSignatureTests`，先固定头签名，再测 `registerkey` 与正文解密；
4. 通过后再进 997 条全量探针，避免把站点风控失败误判成解析缺陷。

## 起点系列：不要误接

起点文档描述的是 App 网关 `druidv6.if.qidian.com` 的 `QDSign` / `QDInfo` 和 `.qd` 容器，不是 Legado JSON 源。它对本项目的价值是工程方法：

- 签名输入顺序必须逐字节对齐；
- 设备头与登录态分离，元数据请求和正文请求的鉴权要求不同；
- 密文容器要按魔数分支，不能假定单一格式；
- 验收表必须写“命令 + 期望 + 实测”，否则无法回归。

这些原则已经体现在 `QimaoSignatureTests`、书源探针和 IPA 校验流程里。