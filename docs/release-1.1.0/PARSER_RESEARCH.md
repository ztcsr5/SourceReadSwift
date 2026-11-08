# 解析能力：本轮提升与边界

已有规则解释器有分层，不宜再堆某站专用替代解析器。SourceEngine.swift也不是把所有网络串在MainActor上的单个串行actor；“慢全因主线程请求”未被证实。要分开网络/站点状态、规则兼容、DOM提取、渲染提交四层。

## 本轮实际改动

- SmartWebArticleExtractor候选评分，不直接取第一个content容器；综合正文长度/链接密度减少导航误选。
- BR/块元素保留换行，短句与有意重复对白不能被全局去重删除，有固定HTML测试。
- 净化正则有有界编译缓存，无效表达式保留原文；预设偏整行推广，不删除任意引号包围文字。
- 当前已登录WKWebView取DOM，不另发无登录请求；导航代次与提取ID检查防旧章覆盖。
- 首批目录/详情独立发布、正文转换编码后台、版本化提交。这是加载与显示优化，不冒充全部规则方言兼容。

## 已有能力与研究依据

RuleOperatorSplitter已有带引号/括号语境的&&、||、%%处理；RuleTransformParser已集中处理替换。官方实现也区分合并、优先非空、交错语义，应补共享解释器测试而非每站写split。依据：[Legado官方AnalyzeByJSoup.kt](https://github.com/LegadoTeam/legado/blob/master/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt)。

下一阶段应按CSS/XPath/JSONPath/JS与组合运算符建立固定输入/精确预期，并与官方实现差分；覆盖转义/空值/嵌套/相对URL/分页/Cookie/编码。分别量测请求、解码、求值、净化、分页、首帧，记录网络不可达/验证码/规则错误/正文缺失，不能混为“源失败”。

本轮没有完成所有书源的差分跑批，也没有“991个源全部可用”的结论。失效页面、反爬和动态JS仍需实际样本。

广告使用[Apple原生WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)，不大规模盲删DOM；保守规则不是完整订阅库。UI参考[Apple Tab bars指南](https://developer.apple.com/design/human-interface-guidelines/tab-bars)的层级、选择态与减少动态效果，不复制第三方整套视觉代码。

原生测试发现普通正则能匹配不代表WebKit规则可编译：本轮把域名合并表达式拆成独立规则，保留原生规则编译测试而不是绕过它。WebKit说明其规则语法仅是JavaScript正则的严格子集：[官方规则格式说明](https://webkit.org/blog/3476/content-blockers-first-look/)。
