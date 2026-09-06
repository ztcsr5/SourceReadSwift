import Foundation

/// Actionable, stage-aware guidance for turning a diagnostic failure into a
/// local rule-editor task.  The advice intentionally contains no live
/// response body or credential material; previews are deterministic,
/// redacted samples that users can replace with their own fixture.
struct SourceDiagnosticRepairAdvice: Hashable, Sendable {
    let stage: SourceDiagnosticStage
    let fieldName: String
    let title: String
    let summary: String
    let actions: [String]
    let suggestedSample: String

    var compactSummary: String {
        "\(stage.title)：\(summary)"
    }
}

enum SourceDiagnosticRepairAdvisor {
    static func advice(for step: SourceDiagnosticStep) -> SourceDiagnosticRepairAdvice {
        let summary = step.responseSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? step.failureClassification?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "该阶段没有返回可解析结果"
        let kind = step.failureCode
        switch step.stage {
        case .search:
            return SourceDiagnosticRepairAdvice(
                stage: .search,
                fieldName: "ruleSearch",
                title: "修复搜索规则",
                summary: summary,
                actions: searchActions(kind: kind),
                suggestedSample: searchSample)
        case .detail:
            return SourceDiagnosticRepairAdvice(
                stage: .detail,
                fieldName: "ruleBookInfo",
                title: "修复详情规则",
                summary: summary,
                actions: detailActions(kind: kind),
                suggestedSample: detailSample)
        case .toc:
            return SourceDiagnosticRepairAdvice(
                stage: .toc,
                fieldName: "ruleToc",
                title: "修复目录规则",
                summary: summary,
                actions: tocActions(kind: kind),
                suggestedSample: tocSample)
        case .content:
            return SourceDiagnosticRepairAdvice(
                stage: .content,
                fieldName: "ruleContent",
                title: "修复正文规则",
                summary: summary,
                actions: contentActions(kind: kind),
                suggestedSample: contentSample)
        }
    }

    static func suggestedSample(for step: SourceDiagnosticStep) -> String {
        advice(for: step).suggestedSample
    }

    private static func searchActions(kind: SourceDiagnosticFailureKind?) -> [String] {
        if kind == .javascript { return ["检查 @js:/<js> 返回值是否为数组或 JSON。", "确认脚本中的请求字段与搜索响应字段一致。"] }
        if kind == .network || kind == .timeout { return ["先确认搜索 URL、请求方法和必需 headers。", "用本地响应样本验证选择器，避免把网络问题误当成规则问题。"] }
        return ["确认搜索结果节点能提取书名、作者和详情链接。", "网页源优先 CSS/XPath，JSON 源优先 JSONPath；预览至少应命中 1 条。"]
    }

    private static func detailActions(kind: SourceDiagnosticFailureKind?) -> [String] {
        if kind == .authentication { return ["先在源详情中完成登录，再重试详情请求。", "不要把 Cookie 或 token 写入规则草稿。"] }
        return ["确认详情规则的书名、作者、简介和目录链接字段。", "检查详情链接是否需要绝对 URL 或 source URL 前缀。"]
    }

    private static func tocActions(kind: SourceDiagnosticFailureKind?) -> [String] {
        if kind == .emptyResult { return ["检查章节节点选择器和分页 nextUrl 字段。", "确认分页规则不会重复返回上一页 canonical URL。"] }
        return ["确认章节标题与章节链接来自同一节点。", "分页目录按页面顺序拼接，并为相对链接补齐基准 URL。"]
    }

    private static func contentActions(kind: SourceDiagnosticFailureKind?) -> [String] {
        if kind == .javascript { return ["检查正文 bodyJs 解码后的字段名称和返回值。", "把解密/净化脚本拆成可单步验证的小段。"] }
        return ["确认正文选择器命中正文容器而不是广告或空壳节点。", "检查 HTML 实体、换行和脚本净化规则是否误删正文。"]
    }

    private static let searchSample = """
    <html><body><article class="book">
      <a class="result" href="/book/1"><h3>示例书名</h3><span class="author">示例作者</span></a>
    </article></body></html>
    """

    private static let detailSample = """
    <html><body><main class="book-detail">
      <h1>示例书名</h1><p class="author">示例作者</p>
      <p class="intro">这是脱敏简介。</p><a class="toc" href="/book/1/catalog">目录</a>
    </main></body></html>
    """

    private static let tocSample = """
    <html><body><ul class="chapters">
      <li><a href="/book/1/1">第一章 开始</a></li>
      <li><a href="/book/1/2">第二章 继续</a></li>
    </ul></body></html>
    """

    private static let contentSample = """
    <html><body><article class="content"><h1>第一章 开始</h1>
      <p>这是脱敏正文段落。</p><p>第二个正文段落。</p>
    </article></body></html>
    """
}
