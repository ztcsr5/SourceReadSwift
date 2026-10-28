# 988 条书源全量体检（1.0.98）

日期：2026-10-29　执行方式：LAN `/api/source/debug`（真机引擎，step=search，关键词「剑来」，并发 6）

- 参与：988 条（enabled 且 searchUrl 非空）
- 通过：660 条（66.8%）
- 失败：328 条

| 分类 | 数量 | 说明 |
|---|---|---|
| PASS | 660 | 通过 |
| E | 128 | 列表规则 0 节点 |
| A | 66 | 上游异常（badURL -1000，实测这些域名返回 502） |
| B | 40 | 列表命中但书名/链接为空 |
| I | 31 | 其它 |
| D | 24 | 连接中断 |
| H | 14 | HTTP 状态错误 |
| C | 12 | 超时 |
| F | 9 | 规则 JS 异常 |
| G | 4 | DNS/连接失败 |

## 失败域名 Top 20（同一域名的多条源合并计数）

| 域名 | 失败源数 |
|---|---|
| www.missevan.com | 8 |
| www.azycjd.com | 7 |
| www.biqusk.com | 7 |
| www.bsxiaoshuo.com | 6 |
| www.23hh.la | 6 |
| www.xiangtxsw.com | 5 |
| m.zhizihuan.com | 5 |
| www.mhtxs.la | 5 |
| www.linovel.net | 5 |
| www.00shu.la | 5 |
| (空) | 4 |
| www.shubang.net | 4 |
| www.8kana.com | 4 |
| www.wtzw.com | 4 |
| www.xxsy.net | 4 |
| www.tcmaoxin.org | 4 |
| www.mayiwsk.com | 4 |
| m.bgnovel.com | 4 |
| www.gdbzkz.org | 4 |
| m.xiaxs.la | 3 |

## A 类（badURL -1000）抽查

对 `wsskw.com`、`biqusk.com`、`m.yunxs.cc`、`sjwx.la` 四个域名在 PC 侧直接请求，全部返回 **502 Bad Gateway**（中间层），说明该组 -1000 是上游/CDN 异常，不是 URL 解析缺陷。iOS 侧把这类连接直接映射成 -1000，错误文案偏误导，下一轮可细化。

## B 类（列表命中但字段为空）Top 域名

| 域名 | 数量 |
|---|---|
| www.bsxiaoshuo.com | 6 |
| www.wxscs.com | 3 |
| m.zhonghuashici.com | 3 |
| www.95shubao.info | 3 |
| www.jwdushu.com | 3 |
| www.sjks88.com | 3 |
| www.dbxsd.com | 3 |
| m.bgnovel.com | 3 |
| www.95shubao.cc | 2 |
| www.ishubao.org | 2 |

这类是下一轮最值得逐条修的：列表选择器命中了行，但 name/bookUrl 子规则在新版页面里取不到值。

## F 类（规则 JS 异常）样本

- `猫耳听书（优）` — 搜索失败: 搜索规则 JS 异常：SyntaxError: JSON Parse error: Unrecognized token '<'
- `猫耳听书（优）` — 搜索失败: 搜索规则 JS 异常：SyntaxError: JSON Parse error: Unrecognized token '<'
- `猫耳听书（优）` — 搜索失败: 搜索规则 JS 异常：SyntaxError: JSON Parse error: Unrecognized token '<'
- `猫耳听书（优）` — 搜索失败: 搜索规则 JS 异常：SyntaxError: JSON Parse error: Unrecognized token '<'
- `猫耳听书（优）` — 搜索失败: 搜索规则 JS 异常：SyntaxError: JSON Parse error: Unrecognized token '<'
- `猫耳有声` — 搜索失败: 搜索规则 JS 异常：SyntaxError: JSON Parse error: Unrecognized token '<'

集中在「猫耳」系列：上游返回 HTML（拦截页/首页），源内 JS 仍执行 `JSON.parse`。属源规则与站点变更，不改引擎。

## 结论

1. 66.8% 的源在单关键词下即可返回结果，引擎主体链路（URL 模板、Header、规则解析、GBK、JSON、JS）可用。
2. 失败集中在：上游 502/TLS、站点改版、以及 13% 的选择器不匹配；未发现新的引擎级通用缺陷。
3. 下一轮建议按 B 类清单逐站点重建规则（每站点 1 条源修复即消除 2–6 条重复失败）。
