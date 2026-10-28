# 书源探针分类器修正（1.0.86）

## 现象

1.0.85 的探针把 Legado 的 `,{...}` 请求选项当成 URL 的一部分，产生了三类误判：

| 源 | 探针输出 | 实际 |
|---|---|---|
| 七猫 `api-bc.wtzw.com` | `braceResidue` | URL 后的 `{"headers":{...}}` 是请求选项，`}}` 合法 |
| 书城网 `http://www.shucw.net` | `unparseable` | `,{"method":"post","body":...}` 是 POST 选项，不是 URL |
| 永恒小说 `http://wap.4pan.org#/s.php` | `fragmentSwallowsPath` | 基址带 `#`，请求层会先剥掉 fragment 再拼相对路径 |

相对 `searchUrl` 本身也不是缺陷：Legado 会按 `bookSourceUrl` 解析，`/search?...` 与 `search.php?...` 都合法。

## 修正

- `SearchURLResolver.splitURLAndDirectiveSuffix` 先拆出 URL 与选项；
- `SourceRequestBuilder.resolveURL(address, relativeTo: bookSourceUrl)` 解析相对地址，和真实请求层共用同一实现；
- 只对 URL 部分检查 `{{}}`、`<js>`、尖括号；选项 JSON 里的 `}}` 不再参与判断；
- `RuleEditorValidator` 同步改为同一口径，不再要求 `searchUrl` 必须是绝对 `http(s)`。

## 新增回归

| 测试 | 覆盖 |
|---|---|
| `SourceSearchURLProbeTests.testClassifierAcceptsRelativeURLAndLegadoOptions` | 相对 URL、七猫头选项、POST 选项、带 `#` 基址 |
| `SourceSearchURLProbeTests.testClassifierStillFlagsUnresolvedTemplates` | `{{key}}` 与 `<js>` 残留仍要报 |
| `BookSourceTests.testRequestBuilderResolvesRelativeSearchURLWithLegadoOptions` | 相对路径 + POST 选项真正拼成请求 |
| `RuleEditorValidatorTests.testAcceptsRelativeSearchURLAndLegadoOptions` | 书源编辑器不再误报相对 searchUrl |

## 实测结果（run `40653736576`，commit `b6e9e56`）

997 条语料、994 条带 `searchUrl`，page1/page2 双页解析：

| 指标 | 1.0.85（run `40649445341`） | 1.0.86（run `40653736576`） |
|---|---|---|
| URL 层缺陷源 | 19 | 2 |
| `braceResidue` | 28（page 计数） | 0 |
| `unparseable` | 3 | 0 |
| `fragmentSwallowsPath` | 2 | 0 |
| `encodedAngle` | 2 | 2 |
| 新增回归 | — | 0 |

修复 17 条：阅读助手（37）、七猫系列（41/195/532/580/658/659/670/713/714）、立方体儿（59）、书城网（307）、永恒小说（323）、玄幻文学（457）、就爱文学（490）、饭角有声（747）、乐乎文章（765）。

剩余 2 条都不是 URL 解析缺陷：

| id | 源 | 现象 | 定性 |
|---|---|---|---|
| 413 | 笔趣小说 | `search.html?name={{key}},<"charset":"utf-8">` 被编码成 `%3C...%3E` | 源自身把请求选项写成尖括号；Legado 同样得到垃圾 URL |
| 655 | 云中书库 | `searchUrl` 为 `@js:`，用 `java.webView` 打开首页再取表单 action，无头探针返回空串 | 探针环境没有 WebView；真机走 WebView fallback，不在 URL 层判定 |

另有 10 条 `page1Error`（七猫 `default_pm`、番茄 `r.match` 签名、哔哩哔哩 `getWbiEnc`、零点看书 `action=` 解析等），属于源 JS 依赖 App 私有 API 或上一次网络返回，不在 URL 分类范围。

## 复现

```powershell
python E:/codex-temp/sourceread/scripts/dispatch_rows_probe.py
python E:/codex-temp/sourceread/scripts/compare_1086.py 40653736576
```