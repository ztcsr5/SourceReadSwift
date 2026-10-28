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

## 预期结果

997 条语料中，994 条有 `searchUrl`。修正后按真实请求 URL 分类，预期只剩：

| id | 源 | 问题 | 性质 |
|---|---|---|---|
| 413 | 笔趣小说 | `search.html?name={{key}},<"charset":"utf-8">` 被编码成 `%3C...%3E` | 源自身写法异常，Legado 同样得到垃圾 URL |

## 复现

```powershell
python E:/codex-temp/sourceread/scripts/dispatch_rows_probe.py
python E:/codex-temp/sourceread/scripts/compare_probe.py
```