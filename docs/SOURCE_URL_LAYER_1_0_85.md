# 书源 URL 层对齐（1.0.85）

探针：`SourceReadSwiftTests/SourceSearchURLProbeTests`，997 条 searchUrl，真实 `SearchURLResolver` 解析 page 1 / page 2。

## 结果

| 轮次 | 提交 | 真缺陷 | 备注 |
|---|---|---|---|
| 1.0.84 | `5f89ed8` | 16 | 首轮基线 |
| 1.0.85 | `7bc6034` | 2 | 修复 14 条 |

剩余 2 条：

| id | 源 | 现象 | 性质 |
|---|---|---|---|
| 163 | 抖音小说 | `{{...}}` 多行块未消掉 | `600ebe8` 改成平衡扫描，待探针确认 |
| 413 | 笔趣小说 | `<"charset": "utf-8">` 被编码 | 源本身写法异常，Legado 同样得到垃圾 URL |

## 修复项

### 1. 尾部 `@js:`

猫耳 / 随心看吧系列把 URL 写在第一行，第二行开始是 `@js:`。Legado 的 `analyzeJs()` 全串查找 `@js:`，把前面的文本绑定到 `result` 再执行。

修复：`SearchURLResolver.resolve` 在 URL 切分前处理非开头的 `@js:`，`result` = 前缀，执行结果再过 `postProcess`。

### 2. JS 结果里的 `{{...}}`

曼哈漫画的 `@js:` 返回模板串，里面还有 `{{key}}` 和 `{{buildQueryParams()}}`。Legado 会对返回值再跑一次 `replaceKeyPageJs()`。

修复：`postProcess` 在 `interpolate` 前对 `urlPart` 再跑 `resolveEmbeddedBracesScripts`。

### 3. 多行 `{{...}}` 块

旧实现用正则 `\{\{((?:[^{}]|(?!\}\}))+)\}\}`。`(?!\}\})` 是零宽断言，在 `{` 处不消耗字符，导致含 `{}` 的多行块无法匹配（163 抖音只匹配到末尾的 `{{key}}`）。

修复：改成平衡光标扫描，与 Legado 的 `RuleAnalyzer.innerRule` 一致。

### 4. 多行块返回值

旧实现只要表达式里出现 `;` 或 `=` 就把替换值清空。多行 JS 一定含 `;`，于是抖音的 `posturl` 被丢掉。

修复：按 JS 返回值判断，`undefined` / `null` / 空 / `true` / `false` 才清空。

## 七猫签名对拍

`QimaoSignatureTests` 固定了文档算法：

```
sign = MD5(sorted "k=v" concatenation + "d3dGiJc651gSQ8w1")
```

| 项 | 期望 | 引擎输出 |
|---|---|---|
| page1 paramSign | `0c85373002b897710cae9b8aff9a60a5` | 一致 |
| page2 paramSign | `5e2dd3b0eeb9b5a00333455858002d44` | 一致 |
| headerSign | `fc697243ab534ebaf51d2fa80f251cb4` | 一致 |

## 探针口径

`classify` 不再把无 scheme 的相对路径（`/search?...`）判为缺陷：Legado 的 searchUrl 本来就相对 `bookSourceUrl`，由请求层拼接。

## 复现

```powershell
python E:/codex-temp/sourceread/scripts/dispatch_rows_probe.py
python E:/codex-temp/sourceread/scripts/compare_probe.py
```