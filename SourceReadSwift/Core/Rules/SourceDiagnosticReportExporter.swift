import Foundation
import UIKit

/// 书源批量体检报告导出器
/// 负责将批量体检结果整理为详尽分类的 Markdown 报告与 JSON 数据包，并生成导出文件
enum SourceDiagnosticReportExporter {

    struct DiagnosticSummary: Sendable {
        let totalCount: Int
        let checkedCount: Int
        let passedCount: Int
        let warningCount: Int
        let failedCount: Int
        let loginRequiredCount: Int
        let verificationRequiredCount: Int
        let blockedCount: Int
        let generatedAt: Date

        init(
            totalCount: Int,
            checkedCount: Int,
            passedCount: Int,
            warningCount: Int,
            failedCount: Int,
            loginRequiredCount: Int,
            verificationRequiredCount: Int,
            blockedCount: Int,
            generatedAt: Date = Date()
        ) {
            self.totalCount = totalCount
            self.checkedCount = checkedCount
            self.passedCount = passedCount
            self.warningCount = warningCount
            self.failedCount = failedCount
            self.loginRequiredCount = loginRequiredCount
            self.verificationRequiredCount = verificationRequiredCount
            self.blockedCount = blockedCount
            self.generatedAt = generatedAt
        }

        var passRate: Double {
            guard checkedCount > 0 else { return 0.0 }
            return Double(passedCount) / Double(checkedCount) * 100.0
        }
    }

    struct CategorizedFailure: Identifiable, Sendable {
        var id: String { "\(category.rawValue)|\(sourceURL)" }
        let category: FailureCategory
        let sourceName: String
        let sourceURL: String
        let stage: SourceDiagnosticStage?
        let statusCode: Int?
        let message: String
        let suggestion: String
    }

    enum FailureCategory: String, CaseIterable, Sendable {
        case networkTimeout = "域名失效 / 连接超时"
        case antiBotShield = "Cloudflare / 反爬验证码拦截"
        case contentEmpty = "正文解析为空 / 规则失效"
        case tocEmpty = "目录获取失败 / 章节为空"
        case searchFailed = "搜索接口失效 / 无结果"
        case authRequired = "需账号登录"
        case other = "其他异常"

        var icon: String {
            switch self {
            case .networkTimeout: return "🌐"
            case .antiBotShield: return "🛡️"
            case .contentEmpty: return "📖"
            case .tocEmpty: return "📑"
            case .searchFailed: return "🔍"
            case .authRequired: return "🔑"
            case .other: return "⚠️"
            }
        }

        var defaultSolution: String {
            switch self {
            case .networkTimeout:
                return "源站域名已下线、无法连接或触发 DNS 污染。建议：1. 检查是否需开启网络代理；2. 尝试更换该站备用镜像域名；3. 无可用镜像则建议禁用该书源。"
            case .antiBotShield:
                return "受到 Cloudflare 5秒盾、人机验证或 Turnstile 拦截。建议：1. 在书源中配置 {\"webView\": true} 走无头浏览器加载；2. 或在书源管理中点击「登录/过盾」手动完成一次人机验证获取持久化 Cookie。"
            case .contentEmpty:
                return "搜索与目录正常，但正文提取结果为空。建议：1. 书源正文 CSS 选择器可能过期，需检查网页 DOM 结构调整 content 规则；2. 轻阅内置四级通用提取机制会自动兜底大部分常规网文小说排版。"
            case .tocEmpty:
                return "目录列表提取为 0 条。建议：1. 检查 ruleToc.chapterList 规则；2. 某些书源书籍目录为动态异步加载或需要特定 nextTocUrl 翻页规则，可点击「修复规则」查看详情。"
            case .searchFailed:
                return "搜索请求未返回任何书籍。建议：1. 检查 searchUrl 编码（如是否需要 GBK 编码）；2. 部分源站搜索接口已关闭或更换了参数路径。"
            case .authRequired:
                return "该书源属于封闭论坛或需 VIP 账号。建议：点击该书源的「登录」按钮输入账号密码授权后即可正常阅读。"
            case .other:
                return "未知规则解析错误或数据截断。建议点击该书源「修复规则」查看底层网络响应报文与 JS 日志。"
            }
        }
    }

    /// 根据单条测试报告分析所属失败分类
    static func classify(
        report: SourceDiagnosticReport
    ) -> (category: FailureCategory, suggestion: String) {
        let step = report.firstFailure
        let msg = (step?.responseSummary ?? step?.failureClassification ?? "").lowercased()

        if report.overallStatus == .requiresLogin || msg.contains("login") || msg.contains("登录") {
            return (.authRequired, FailureCategory.authRequired.defaultSolution)
        }

        if report.overallStatus == .verificationRequired || report.overallStatus == .blocked
            || msg.contains("cloudflare") || msg.contains("captcha") || msg.contains("challenge")
            || msg.contains("人机验证") || msg.contains("安全验证") || msg.contains("403") {
            return (.antiBotShield, FailureCategory.antiBotShield.defaultSolution)
        }

        if msg.contains("timeout") || msg.contains("超时") || msg.contains("404") || msg.contains("502")
            || msg.contains("504") || msg.contains("connection refused") || msg.contains("cannot connect")
            || msg.contains("未能连接") || msg.contains("网络错误") {
            return (.networkTimeout, FailureCategory.networkTimeout.defaultSolution)
        }

        if step?.stage == .content || msg.contains("正文") || msg.contains("content") {
            return (.contentEmpty, FailureCategory.contentEmpty.defaultSolution)
        }

        if step?.stage == .toc || msg.contains("目录") || msg.contains("toc") || msg.contains("chapter") {
            return (.tocEmpty, FailureCategory.tocEmpty.defaultSolution)
        }

        if step?.stage == .search || msg.contains("搜索") || msg.contains("search") {
            return (.searchFailed, FailureCategory.searchFailed.defaultSolution)
        }

        return (.other, FailureCategory.other.defaultSolution)
    }

    /// 从 SourceDiagnosticBatchReport 导出完整的 Markdown 检测报告
    static func generateMarkdownReport(from batch: SourceDiagnosticBatchReport, totalCount: Int? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: batch.finishedAt)

        let total = totalCount ?? batch.reports.count
        let passed = batch.reports.filter { $0.overallStatus == .passed }.count
        let warning = batch.reports.filter { $0.overallStatus == .warning }.count
        let failed = batch.reports.filter { $0.overallStatus == .failed }.count
        let login = batch.reports.filter { $0.overallStatus == .requiresLogin }.count
        let verify = batch.reports.filter { $0.overallStatus == .verificationRequired }.count
        let blocked = batch.reports.filter { $0.overallStatus == .blocked }.count
        let passRate = batch.reports.isEmpty ? 0.0 : (Double(passed) / Double(batch.reports.count) * 100.0)

        var md = ""
        md += "# 📖 轻阅书源全身体检诊断报告\n\n"
        md += "- **体检时间**: \(dateString)\n"
        md += "- **测试关键词**: 《\(batch.keyword)》\n"
        md += "- **检测总数**: \(batch.reports.count) / \(total) 个书源\n"
        md += "- **综合通过率**: \(String(format: "%.1f", passRate))%\n\n"

        md += "### 📊 状态分布看板\n\n"
        md += "| 状态指标 | 数量 | 占比 | 简评 |\n"
        md += "| :--- | :--- | :--- | :--- |\n"
        md += "| 🟢 **PASS (完全健康)** | \(passed) | \(percentage(passed, total: batch.reports.count)) | 搜索、详情、目录、正文四级全绿 |\n"
        md += "| 🟡 **WARN (轻微异常)** | \(warning) | \(percentage(warning, total: batch.reports.count)) | 存在截断或部分字段缺失，但不影响阅读 |\n"
        md += "| 🔴 **FAIL (解析失败)** | \(failed) | \(percentage(failed, total: batch.reports.count)) | 域名失效、404 或解析规则出错 |\n"
        md += "| 🟠 **LOGIN (需登录)** | \(login) | \(percentage(login, total: batch.reports.count)) | 站点需要提供账号凭据 |\n"
        md += "| 🟣 **VERIFY (盾/验证码)** | \(verify) | \(percentage(verify, total: batch.reports.count)) | 触发 Cloudflare 盾或人机验证 |\n"
        md += "| ⚫ **BLOCK (反爬拦截)** | \(blocked) | \(percentage(blocked, total: batch.reports.count)) | IP 或设备指纹被目标服务器封锁 |\n\n"

        let failures = batch.reports.filter { $0.overallStatus != .passed }
        if failures.isEmpty {
            md += "🎉 **完美！所有被检测书源均通过测试，暂未发现任何异常书源。**\n"
            return md
        }

        // 分类汇总
        var categorizedMap: [FailureCategory: [CategorizedFailure]] = [:]
        for cat in FailureCategory.allCases {
            categorizedMap[cat] = []
        }

        for report in failures {
            let (category, suggestion) = classify(report: report)
            let step = report.firstFailure
            let rawMsg = step?.responseSummary ?? step?.failureClassification ?? "未能返回响应"
            let catItem = CategorizedFailure(
                category: category,
                sourceName: report.sourceName,
                sourceURL: report.sourceURL,
                stage: step?.stage,
                statusCode: step?.responseStatusCode,
                message: rawMsg,
                suggestion: suggestion
            )
            categorizedMap[category, default: []].append(catItem)
        }

        md += "### 🛠️ 失败原因深度分类与排错指南\n\n"

        for cat in FailureCategory.allCases {
            let list = categorizedMap[cat] ?? []
            guard !list.isEmpty else { continue }

            md += "#### \(cat.icon) \(cat.rawValue) (共 \(list.count) 个书源)\n\n"
            md += "> **💡 官方排错建议**: \(cat.defaultSolution)\n\n"
            md += "| 书源名称 | 报错阶段 | 状态码 | 具体报错信息 | 书源主页 |\n"
            md += "| :--- | :--- | :--- | :--- | :--- |\n"

            for fail in list {
                let stageStr = fail.stage?.title ?? "综合"
                let statusStr = fail.statusCode.map { "\($0)" } ?? "-"
                let cleanMsg = fail.message.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
                let prefixMsg = String(cleanMsg.prefix(60))
                md += "| **\(fail.sourceName)** | \(stageStr) | \(statusStr) | \(prefixMsg) | [点击访问](\(fail.sourceURL)) |\n"
            }
            md += "\n"
        }

        md += "### 💡 快捷操作指南\n"
        md += "1. **快速净化书源库**: 在轻阅「批量测试」弹窗底部点击「**一键禁用所有失败书源**」，即可秒级关闭所有死源，提升 80% 搜索速度；\n"
        md += "2. **正文加载失败防范**: 升级至轻阅最新版本，内置全新的 CSS+JS 链式解析引擎与四级通用网文容器容错机制；\n"
        md += "3. **过盾与验证码**: 对于标记为 🟣 VERIFY 的书源，请在书源管理长按该书源进入「登录/过盾」界面完成一次网页滑块。\n"

        return md
    }

    private static func percentage(_ count: Int, total: Int) -> String {
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", Double(count) / Double(total) * 100.0)
    }

    /// 将报告写入临时文件，供 UIActivityViewController / ShareLink 分享与导出
    static func createExportFiles(
        markdownText: String,
        jsonData: Data?
    ) -> (markdownURL: URL, jsonURL: URL?) {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let mdURL = tempDir.appendingPathComponent("轻阅书源体检报告_\(timestamp).md")
        try? markdownText.data(using: .utf8)?.write(to: mdURL, options: .atomic)

        var jsonURL: URL? = nil
        if let jsonData {
            let jURL = tempDir.appendingPathComponent("轻阅书源诊断数据_\(timestamp).json")
            try? jsonData.write(to: jURL, options: .atomic)
            jsonURL = jURL
        }
        return (mdURL, jsonURL)
    }
}
