# 1.0.90 · 76 条整理版书源兼容审计

- 基线：`shareBookSource11.json`（76 条，76 个唯一 `bookSourceUrl`）
- 目标：整理版全部可跑；番茄源在 App 内可用
- 版本：1.0.90 / Build 91

## 1. 书源结构分布

| 项 | 数量 |
|---|---|
| 总条数 | 76 |
| 唯一 URL | 76 |
| `searchUrl` 为 JS（`@js:` / `{{...}}`） | 28 |
| `searchUrl` 为普通模板 | 28 |
| 无 `searchUrl`（仅发现页 / 失效） | 20 |
| 带 `jsLib` | 32（最大 587 KB） |

## 2. Node 桩求值（key=斗破苍穹, page=1）

`E:\codex-temp\sourceread\sources76-eval2.json` 为逐条明细。

| 结果 | 数量 | 说明 |
|---|---|---|
| URL 产出 | 46 | 拼接后为合法 http(s) |
| 抛错 | 10 | 逐条归因见下表 |
| 空结果 | 20 | 24 条无 `searchUrl` 中扣除有 `{{}}` 模板的 4 条 |

### 10 条抛错归因

| # | 书源 | 错误 | 归因 |
|---|---|---|---|
| 10 | 魔丸小说 | `cookie.getCookie is not a function` | App 已有；Node 桩缺 |
| 11 | 七猫四合一本地版（同人） | `Packages is not defined` | App 内缺 Inflater / DigestUtil（本轮已补） |
| 20 | ✿番茄四合一（知秋段评）✿ | `source.get is not a function` | 1.0.89 已修 |
| 27 | 本地番茄红果·mini | `Packages is not defined` | App 内缺 SecureRandom / 反射（本轮已补） |
| 30 | ⭐七猫听书[官方]v0.2✨ | `s.get is not a function` | `s = source` 别名，1.0.89 已生效 |
| 37 | 塔读小说app v0.12 | `java.createSymmetricCrypto is not a function` | App 已有；Node 桩缺 |
| 39 | ✿爱丽丝书屋（知秋）✿ | `template:source.get is not a function` | 1.0.89 已补 `source.get`；模板阶段走 JS 运行时并加载 jsLib |
| 44 | ✿UAA四合一（知秋）✿ | `source.get is not a function` | 1.0.89 已修 |
| 71 | 八叉书库(二合一)☆夜明空☆ | `cookie.removeCookie is not a function` | App 已有；Node 桩缺 |
| 74 | 紙間·阅读 | `当前阅读版本不支持本源所需的 Java 环境` | 源内自检拦截；需完整 Java 环境，属已知边界 |

App 内真实缺口集中在 6 类，本轮全部补齐：

1. `java.util.zip.Inflater(nowrap)` + 分块 `inflate(buf, off, len)`
2. `java.security.SecureRandom`
3. `java.lang.reflect.Array.newInstance` / `java.lang.Byte.TYPE`
4. `java.nio.ByteBuffer`（`allocate` / `wrap` / `putInt` / `putShort` / `array`）
5. `cn.hutool` 三件套（`DigestUtil` / `StrUtil` / `Base64`）
6. `javax.crypto.spec.GCMParameterSpec` + 原生 AES/GCM

## 3. HTTP 实测（上一轮，`sources76-live.tsv`）

22 条关键字命中：番茄TS 4、反代番茄 24、七猫 29、七猫本地接口 29、百度 23、木里番茄 11、沐凡番茄 11、日落 11、书旗 15、QQ浏览器 43、无错 42、错层 7、Icu 56、爱书音 23、含遇見 33、番茄APP 5、顶点 19、免费追书 1、52书库 3、集书阁 5、圣灵聚合 8。

其余失败均为站点侧：`no-url 28`（20 条无 searchUrl + 8 条 JS 失败）、速读谷×3 站点 500、小原文学网 403、有听网/爱下电子 404、紙間 503、含遇見 SSL、少年梦/次元姬 401 需登录、🍅蕃茄小说 403。

## 4. 1.0.90 新增能力

### 4.1 JSCoreRuntime（JS 兼容层）

| 能力 | 说明 |
|---|---|
| `Packages.java.lang.String(byte[], offset, length, charset)` | 四参重载；七猫 ZIP 解包逐条调用 |
| `Packages.java.util.Arrays.copyOf(values, length)` | 补齐（原只有 `copyOfRange`） |
| `cache.deleteMemory(key)` | 番茄四合一知秋调用 |
| `Packages.java.util.zip.Inflater(nowrap)` | `setInput` / `inflate` / `getRemaining` / `getTotalOut` / `finished` / `reset` / `end`；按进度续读，支持 Java 循环语义 |
| `Packages.java.security.SecureRandom` | `nextBytes` / `nextInt` / `nextLong` / `setSeed` / `generateSeed` |
| `Packages.java.lang.reflect.Array.newInstance` + `java.lang.Byte.TYPE` | 本地番茄红果 mini |
| `Packages.java.nio.ByteBuffer` | `allocate` / `wrap` / `putInt`（大端）/ `putShort` / `put` / `getInt` / `array` / `flip` / `position` / `remaining` |
| `Packages.cn.hutool.crypto.digest.DigestUtil` | `md5Hex` / `sha1Hex` / `sha256Hex` / `sha512Hex` |
| `Packages.cn.hutool.core.util.StrUtil` | `reverse` / `isBlank` / `isNotBlank` / `emptyToDefault` |
| `Packages.cn.hutool.core.codec.Base64` | `encode` / `decode` |
| `Packages.javax.crypto.spec.GCMParameterSpec` | `(tagLen, iv)` 与 `(tagLen, iv, off, len)`；`getIV` / `getTLen` |
| `java.*` 兜底 | `qread`→`'0'`、`getSource`→`source`、`deviceID()`→`''`（源内以空串判断 iOS）、`getActivityRef`、`startBrowserDp` / `showReadingBrowser` / `openVideoPlayer`、`getThemeConfig`、`java.open`、`searchBook`、`hexDecodeToByteArray`、`removeCookie` |
| `source.*` | `putLoginInfo`（JSON 字符串重载）、`putLoginHeader`（单参修正，返回原文）、`getLoginHeader`（原始 / 单键）、`getLoginHeaderMap`、`removeLoginHeader`、`getLoginInfo`、`getLoginUi`、`getTag`、`getHeader`、`includes`、`refreshExplore` |
| `book.*` | `durChapterIndex` / `durChapterTitle` 默认值 |

### 4.2 LegadoHostServices（原生桥）

| 变更 | 说明 |
|---|---|
| AES/GCM | `Cipher.getInstance("AES/GCM/NoPadding")` 走 CryptoSwift `GCM(iv:)`；输出 `ciphertext‖tag`，解密消费同布局 |
| raw DEFLATE | `InflaterInputStream` 在 zlib 包装解码失败后，用 `sourceread_zlib_inflate(..., raw_deflate: 1)` 重试；七猫本地接口 ZIP entry 即 raw deflate |

## 5. 验证

### 5.1 Node prelude harness（真实 prelude，非重写实现）

`E:\codex-temp\sourceread\scripts\verify_1_0_90_prelude.js`

| 检查 | 结果 |
|---|---|
| prelude 语法 + 执行 | OK |
| `Arrays.copyOf` | 5 |
| `String(byte[], off, len, charset)` | `BC` |
| `Array.newInstance(Byte.TYPE, 4)` | 4 |
| `ByteBuffer.allocate(4).putInt(0x01020304)` | `1,2,3,4` |
| `DigestUtil.md5Hex('abc')` / `sha256Hex('abc')` | 与标准值一致 |
| `StrUtil.reverse` / `isBlank` | `cba` / `true` |
| `GCMParameterSpec.getIV().length` / `getTLen()` | 3 / 128 |
| `SecureRandom.nextBytes(a)` | 不抛，长度正确 |
| `java.deviceID()` / `java.qread()` / `java.getSource()===source` | `""` / `"0"` / `true` |
| `source.putLoginHeader(json)` → `getLoginHeaderMap().authorization` | `Bearer x` |
| `Inflater(true)` raw deflate，4 字节分块循环 | `hello inflater payload 0123456789`（33 字节） |

### 5.2 XCTest（CI 执行）

`SourceReadSwiftTests/JSCoreRuntimeTests.swift` 新增：

- `testPrivateBankPackagesShims`
- `testInflaterRawDeflateChunkedReads`
- `testAESGCMRoundTripThroughJavaxCipher`（CryptoSwift GCM 往返，5 字节明文 → 21 字节密文）
- `testSourceLoginHeaderAndMetadataShims`

## 6. 语料库

76 条与既有 1100 条语料重叠 69 条，新增 7 条唯一 URL → `search-url-corpus` 合计 1107 条；`SourceSearchURLProbeTests` 断言同步更新。

## 7. 番茄源结论

- `🍅番茄四合一（知秋段评）` 依赖的 `source.get` 于 1.0.89 修复，jsLib 36,889 B 正常加载；
- `🍅番茄纯小说 / 反代番茄 / 木里番茄 / 沐凡番茄 / 番茄APP` 在 HTTP 实测中有内容命中；
- 1.0.90 追加的 `source.putLoginHeader` 单参修正、`getLoginHeaderMap`、`cache.deleteMemory`、hutool 三件套，覆盖番茄系 jsLib 的鉴权头与签名路径；
- 站点侧 403 / SSL / 需登录属外部因素，不计入 App 能力缺口。

## 8. 未验证 / 已知边界

- iOS 16 真机：未测（用户约定次日测试）。
- `紙間·阅读`：源内置 `当前阅读版本不支持本源所需的 Java 环境` 自检，需要完整 Java 运行时；本轮只补齐其 GCM / ByteBuffer 底层，是否放行取决于源自身判断。
- 速读谷×3、小原文学网、有听网、爱下电子、含遇見（SSL）、少年梦/次元姬（401）：站点侧，`NOT RUN`。
- AES/GCM 的 CryptoSwift 实现仅在 CI（macOS）验证；本地 Node 只验证参数装配。
