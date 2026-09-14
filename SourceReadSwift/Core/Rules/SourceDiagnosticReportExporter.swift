import Foundation
import UIKit

/// 书源批量体检报告导出器
/// 负责将批量体检结果整理为详尽分类的 Markdown 报告、CSV 数据分析表格与 JSON 数据包，并生成导出文件
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
        case sslError = "SSL 证书异常 / 握手失败"
        case badURL = "URL 格式异常 / 非法字符"
        case httpError = "HTTP 状态码异常 (404/400/5xx)"
        case antiBotShield = "Cloudflare / 反爬验证码拦截"
        case searchFailed = "搜索接口失效 / 无结果"
        case tocEmpty = "目录获取失败 / 章节为空"
        case contentEmpty = "正文解析为空 / 规则失效"
        case jsError = "JavaScript 语法 / 执行报错"
        case authRequired = "需账号登录"
        case other = "其他异常"

        var icon: String {
            switch self {
            case .networkTimeout: return "🌐"
            case .sslError: return "🔒"
            case .badURL: return "🔗"
            case .httpError: return "📡"
            case .antiBotShield: return "🛡️"
            case .searchFailed: return "🔍"
            case .tocEmpty: return "📑"
            case .contentEmpty: return "📖"
            case .jsError: return "⚙️"
            case .authRequired: return "🔑"
            case .other: return "⚠️"
            }
        }

        var defaultSolution: String {
            switch self {
            case .networkTimeout:
                return "源站域名已下线、无法连接或触发 DNS 污染。建议：1. 检查是否需开启网络代理；2. 尝试更换该站备用镜像域名；3. 无可用镜像则建议禁用该书源。"
            case .sslError:
                return "目标源站 SSL 证书过期或为自签名证书。轻阅最新版已内建对齐 Android Legado 的证书自适应信任机制，如仍失败可能是 TLS 握手被拦截。"
            case .badURL:
                return "书源 URL 中含有 Emoji、未转义中文或行内指令。轻阅已增强 URL 智能清洗与容错，建议检查书源主页与 searchUrl。"
            case .httpError:
                return "服务器返回 404 (页面不存在)、400 (请求错误) 或 5xx 服务端故障。建议检查接口路径是否变动或需要特定 Referer。"
            case .antiBotShield:
                return "受到 Cloudflare 5秒盾、人机验证或 Turnstile 拦截。建议：1. 在书源中配置 {\"webView\": true} 走无头浏览器加载；2. 或在书源管理中长按书源进入「登录/过盾」手动完成一次人机验证。"
            case .contentEmpty:
                return "搜索与目录正常，但正文提取结果为空。建议：1. 书源正文 CSS 选择器可能过期，需检查网页 DOM 结构调整 content 规则；2. 轻阅内置四级通用提取机制会自动兜底大部分常规网文小说排版。"
            case .tocEmpty:
                return "目录列表提取为 0 条。建议：1. 检查 ruleToc.chapterList 规则；2. 某些书源书籍目录为动态异步加载或需要特定 nextTocUrl 翻页规则，可点击「修复规则」查看详情。"
            case .searchFailed:
                return "搜索请求未返回任何书籍。建议：1. 检查 searchUrl 编码（如是否需要 GBK 编码）；2. 部分源站搜索接口已关闭或更换了参数路径。"
            case .jsError:
                return "书源规则中的 JavaScript 脚本执行失败。轻阅已升级 ES6 变量兼容器，建议检查具体脚本的语法与对象调用。"
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
        let code = step?.responseStatusCode ?? 0

        if report.overallStatus == .requiresLogin || msg.contains("login") || msg.contains("登录") {
            return (.authRequired, FailureCategory.authRequired.defaultSolution)
        }

        if report.overallStatus == .verificationRequired || report.overallStatus == .blocked
            || msg.contains("cloudflare") || msg.contains("captcha") || msg.contains("challenge")
            || msg.contains("人机验证") || msg.contains("安全验证") || code == 403 {
            return (.antiBotShield, FailureCategory.antiBotShield.defaultSolution)
        }

        if msg.contains("certificate") || msg.contains("ssl") || msg.contains("不受信任") || msg.contains("证书") || msg.contains("handshake") {
            return (.sslError, FailureCategory.sslError.defaultSolution)
        }

        if msg.contains("bad url") || msg.contains("invalid url") || msg.contains("unsupported url") || msg.contains("url无效") || msg.contains("url 格式") {
            return (.badURL, FailureCategory.badURL.defaultSolution)
        }

        if msg.contains("javascript") || msg.contains("syntaxerror") || msg.contains("referenceerror")
            || msg.contains("typeerror") || msg.contains("can't find variable") || msg.contains("can't create duplicate variable") {
            return (.jsError, FailureCategory.jsError.defaultSolution)
        }

        if code == 404 || code == 400 || (code >= 500 && code < 600) || msg.contains("404") || msg.contains("400 bad request") {
            return (.httpError, FailureCategory.httpError.defaultSolution)
        }

        if msg.contains("timeout") || msg.contains("超时") || msg.contains("connection refused")
            || msg.contains("cannot connect") || msg.contains("未能连接") || msg.contains("网络错误") || msg.contains("timed out") {
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

        // 四阶段漏斗统计
        let searchPassed = batch.reports.filter { r in
            (r.steps.first(where: { $0.stage == .search })?.status == .passed) ||
            (r.steps.first(where: { $0.stage == .search })?.matchCount ?? 0) > 0
        }.count
        let detailPassed = batch.reports.filter { r in
            r.steps.first(where: { $0.stage == .detail })?.status == .passed
        }.count
        let tocPassed = batch.reports.filter { r in
            r.steps.first(where: { $0.stage == .toc })?.status == .passed
        }.count
        let contentPassed = batch.reports.filter { r in
            r.steps.first(where: { $0.stage == .content })?.status == .passed
        }.count

        let passRate = batch.reports.isEmpty ? 0.0 : (Double(passed) / Double(batch.reports.count) * 100.0)

        var md = ""
        md += "# 📖 轻阅书源全身体检诊断报告\n\n"
        md += "- **体检时间**: \(dateString)\n"
        md += "- **测试关键词**: 《\(batch.keyword)》\n"
        md += "- **检测总数**: \(batch.reports.count) / \(total) 个书源\n"
        md += "- **综合通过率**: 四级全绿 \(String(format: \"%.1f\", passRate))% · 搜书可用 \(percentage(searchPassed, total: batch.reports.count))\n\n"

        md += "### 🌪️ 四阶段漏斗流转分析\n\n"
        md += "| 测试阶段 | 通过书源数 | 阶段通过率 | 相比上一阶段留存 | 说明 |\n"
        md += "| :--- | :--- | :--- | :--- | :--- |\n"
        md += "| 1️⃣ **搜索 (Search)** | \(searchPassed) | \(percentage(searchPassed, total: batch.reports.count)) | 100.0% | 成功触发源站搜索并解析出书籍列表 |\n"
        let detailRetention = searchPassed > 0 ? percentage(detailPassed, total: searchPassed) : "0.0%"
        md += "| 2️⃣ **详情 (Detail)** | \(detailPassed) | \(percentage(detailPassed, total: batch.reports.count)) | \(detailRetention) | 成功获取书籍基本信息与目录入口 |\n"
        let tocRetention = detailPassed > 0 ? percentage(tocPassed, total: detailPassed) : "0.0%"
        md += "| 3️⃣ **目录 (TOC)** | \(tocPassed) | \(percentage(tocPassed, total: batch.reports.count)) | \(tocRetention) | 成功抓取有效章节目录列表 (≥1 章) |\n"
        let contentRetention = tocPassed > 0 ? percentage(contentPassed, total: tocPassed) : "0.0%"
        md += "| 4️⃣ **正文 (Content)** | \(contentPassed) | \(percentage(contentPassed, total: batch.reports.count)) | \(contentRetention) | 成功提取第一章正文文字 (≥20 字) |\n"
        md += "| 🟢 **四级全绿** | \(passed) | \(String(format: \"%.1f%%\", passRate)) | - | 全流程无任何报错与异常 |\n\n"

        md += "### 📊 状态分布看板\n\n"
        md += "| 状态指标 | 数量 | 占比 | 简评 |\n"
        md += "| :--- | :--- | :--- | :--- |\n"
        md += "| 🟢 **PASS (四级全绿)** | \(passed) | \(percentage(passed, total: batch.reports.count)) | 搜索、详情、目录、正文四级全绿可正常阅读 |\n"
        if searchPassed > passed {
            md += "| 🔵 **SEARCH (搜书可用)** | \(searchPassed) | \(percentage(searchPassed, total: batch.reports.count)) | 搜索接口能正常检索到书籍列表 |\n"
        }
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

    /// 生成精简统计看板（适合发微信/群聊，不卡死剪贴板与第三方聊天软件）
    static func generateBriefSummaryText(from batch: SourceDiagnosticBatchReport, totalCount: Int? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: batch.finishedAt)

        let total = totalCount ?? batch.reports.count
        let passed = batch.reports.filter { $0.overallStatus == .passed }.count
        let searchPassed = batch.reports.filter { r in
            (r.steps.first(where: { $0.stage == .search })?.status == .passed) ||
            (r.steps.first(where: { $0.stage == .search })?.matchCount ?? 0) > 0
        }.count
        let detailPassed = batch.reports.filter { r in
            r.steps.first(where: { $0.stage == .detail })?.status == .passed
        }.count
        let tocPassed = batch.reports.filter { r in
            r.steps.first(where: { $0.stage == .toc })?.status == .passed
        }.count
        let contentPassed = batch.reports.filter { r in
            r.steps.first(where: { $0.stage == .content })?.status == .passed
        }.count

        let warning = batch.reports.filter { $0.overallStatus == .warning }.count
        let failed = batch.reports.filter { $0.overallStatus == .failed }.count
        let login = batch.reports.filter { $0.overallStatus == .requiresLogin }.count
        let verify = batch.reports.filter { $0.overallStatus == .verificationRequired }.count
        let blocked = batch.reports.filter { $0.overallStatus == .blocked }.count
        let passRate = batch.reports.isEmpty ? 0.0 : (Double(passed) / Double(batch.reports.count) * 100.0)

        var text = ""
        text += "【轻阅】书源体检精简看板\n"
        text += "📅 体检时间：\(dateString)\n"
        text += "🔍 测试关键词：《\(batch.keyword)》\n"
        text += "📊 检测总数：\(batch.reports.count) / \(total) 个书源\n"
        text += "📈 综合通过率：\(String(format: \"%.1f\", passRate))%\n"
        text += "-------------------------\n"
        text += "🌪️ 四阶段漏斗流转：\n"
        text += "• 1. 搜索通过: \(searchPassed) (\(percentage(searchPassed, total: batch.reports.count)))\n"
        text += "• 2. 详情通过: \(detailPassed) (\(percentage(detailPassed, total: batch.reports.count)))\n"
        text += "• 3. 目录通过: \(tocPassed) (\(percentage(tocPassed, total: batch.reports.count)))\n"
        text += "• 4. 正文通过: \(contentPassed) (\(percentage(contentPassed, total: batch.reports.count)))\n"
        text += "-------------------------\n"
        text += "🟢 四级全绿 (PASS): \(passed) (\(percentage(passed, total: batch.reports.count)))\n"
        text += "🟡 轻微异常 (WARN): \(warning) (\(percentage(warning, total: batch.reports.count)))\n"
        text += "🔴 访问失败 (FAIL): \(failed) (\(percentage(failed, total: batch.reports.count)))\n"
        if verify > 0 {
            text += "🟣 验证码/盾 (VERIFY): \(verify) (\(percentage(verify, total: batch.reports.count)))\n"
        }
        if login > 0 {
            text += "🟠 需要登录 (LOGIN): \(login) (\(percentage(login, total: batch.reports.count)))\n"
        }
        if blocked > 0 {
            text += "⚫ 访问受限 (BLOCK): \(blocked) (\(percentage(blocked, total: batch.reports.count)))\n"
        }

        let failures = batch.reports.filter { $0.overallStatus != .passed }
        if failures.isEmpty {
            text += "-------------------------\n"
            text += "🎉 完美！所有被检测书源均通过测试，无异常书源。\n"
        } else {
            var catCounts: [FailureCategory: Int] = [:]
            for r in failures {
                let (cat, _) = classify(report: r)
                catCounts[cat, default: 0] += 1
            }
            let sortedCats = FailureCategory.allCases.compactMap { cat -> (FailureCategory, Int)? in
                guard let c = catCounts[cat], c > 0 else { return nil }
                return (cat, c)
            }.sorted { $0.1 > $1.1 }

            if !sortedCats.isEmpty {
                text += "-------------------------\n"
                text += "⚠️ 主要异常分类：\n"
                for (cat, count) in sortedCats.prefix(5) {
                    text += "• \(cat.icon) \(cat.rawValue): \(count) 个\n"
                }
            }
            text += "-------------------------\n"
            text += "💡 建议：可在轻阅批量测试界面点击「一键禁用所有失败书源」，秒级过滤失效书源提升检索速度。"
        }
        return text
    }

    /// 生成符合 RFC 4180 标准且带 UTF-8 BOM 头（兼容 Windows / macOS Excel 中文）的 CSV 深度分析表格
    static func generateCSVReport(from batch: SourceDiagnosticBatchReport) -> String {
        var csv = "\u{FEFF}" // UTF-8 BOM for Excel Chinese support
        let headers = [
            "书源名称",
            "综合状态",
            "测试关键词",
            "四级全绿",
            "搜索阶段状态",
            "搜索匹配数",
            "搜索耗时(ms)",
            "详情阶段状态",
            "详情耗时(ms)",
            "目录阶段状态",
            "目录章节数",
            "目录耗时(ms)",
            "正文阶段状态",
            "正文字数/匹配",
            "正文耗时(ms)",
            "首个报错阶段",
            "错误分类",
            "报错状态码",
            "报错摘要",
            "书源网址"
        ]
        csv += headers.map { escapeCSV($0) }.joined(separator: ",") + "\r\n"

        for report in batch.reports {
            let searchStep = report.steps.first(where: { $0.stage == .search })
            let detailStep = report.steps.first(where: { $0.stage == .detail })
            let tocStep = report.steps.first(where: { $0.stage == .toc })
            let contentStep = report.steps.first(where: { $0.stage == .content })
            let firstFailure = report.firstFailure
            let (category, _) = classify(report: report)

            let row: [String] = [
                report.sourceName,
                report.overallStatus.localizedLabel,
                report.keyword,
                report.overallStatus == .passed ? "是" : "否",
                searchStep?.status.localizedLabel ?? "未执行",
                "\(searchStep?.matchCount ?? 0)",
                searchStep?.elapsedMilliseconds.map { "\($0)" } ?? "-",
                detailStep?.status.localizedLabel ?? "未执行",
                detailStep?.elapsedMilliseconds.map { "\($0)" } ?? "-",
                tocStep?.status.localizedLabel ?? "未执行",
                "\(tocStep?.matchCount ?? 0)",
                tocStep?.elapsedMilliseconds.map { "\($0)" } ?? "-",
                contentStep?.status.localizedLabel ?? "未执行",
                "\(contentStep?.matchCount ?? 0)",
                contentStep?.elapsedMilliseconds.map { "\($0)" } ?? "-",
                firstFailure?.stage.title ?? "-",
                firstFailure == nil ? "无" : category.rawValue,
                firstFailure?.responseStatusCode.map { "\($0)" } ?? "-",
                firstFailure?.responseSummary ?? firstFailure?.failureClassification ?? "-",
                report.sourceURL
            ]
            csv += row.map { escapeCSV($0) }.joined(separator: ",") + "\r\n"
        }
        return csv
    }

    private static func escapeCSV(_ text: String) -> String {
        var str = text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if str.contains("\"") {
            str = str.replacingOccurrences(of: "\"", with: "\"\"")
        }
        if str.contains(",") || str.contains("\"") || str.contains(";") {
            return "\"\(str)\""
        }
        return str
    }

    private static func percentage(_ count: Int, total: Int) -> String {
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", Double(count) / Double(total) * 100.0)
    }

    /// 将报告直接持久化保存至 App 的 Documents/Reports 目录，用户可在 iOS 自带「文件」App -> 「我的 iPhone/iPad」 -> 「轻阅」 中直接查看
    @discardableResult
    static func saveToDocuments(
        markdownText: String,
        csvText: String? = nil,
        jsonData: Data?,
        reportDate: Date = Date()
    ) throws -> (markdownURL: URL, csvURL: URL?, jsonURL: URL?) {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "SourceDiagnosticReportExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问应用文档目录"])
        }
        let reportsDir = documentsDir.appendingPathComponent("Reports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: reportsDir.path) {
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: reportDate)

        let mdURL = reportsDir.appendingPathComponent("轻阅书源体检报告_\(timestamp).md")
        try markdownText.data(using: .utf8)?.write(to: mdURL, options: .atomic)

        var csvURL: URL? = nil
        if let csvText {
            let cURL = reportsDir.appendingPathComponent("轻阅书源体检数据_\(timestamp).csv")
            try csvText.data(using: .utf8)?.write(to: cURL, options: .atomic)
            csvURL = cURL
        }

        var jsonURL: URL? = nil
        if let jsonData {
            let jURL = reportsDir.appendingPathComponent("轻阅书源诊断数据_\(timestamp).json")
            try jsonData.write(to: jURL, options: .atomic)
            jsonURL = jURL
        }

        return (mdURL, csvURL, jsonURL)
    }

    /// 将报告写入临时文件，供 UIActivityViewController / ShareLink 分享与导出
    static func createExportFiles(
        markdownText: String,
        csvText: String? = nil,
        jsonData: Data?
    ) -> (markdownURL: URL, csvURL: URL?, jsonURL: URL?) {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let mdURL = tempDir.appendingPathComponent("轻阅书源体检报告_\(timestamp).md")
        try? markdownText.data(using: .utf8)?.write(to: mdURL, options: .atomic)

        var csvURL: URL? = nil
        if let csvText {
            let cURL = tempDir.appendingPathComponent("轻阅书源体检数据_\(timestamp).csv")
            try? csvText.data(using: .utf8)?.write(to: cURL, options: .atomic)
            csvURL = cURL
        }

        var jsonURL: URL? = nil
        if let jsonData {
            let jURL = tempDir.appendingPathComponent("轻阅书源诊断数据_\(timestamp).json")
            try? jsonData.write(to: jURL, options: .atomic)
            jsonURL = jURL
        }
        return (mdURL, csvURL, jsonURL)
    }

    /// 兼容旧版调用与单测的二元元组重载
    @discardableResult
    static func saveToDocuments(
        markdownText: String,
        jsonData: Data?,
        reportDate: Date = Date()
    ) throws -> (markdownURL: URL, jsonURL: URL?) {
        let (mdURL, _, jsonURL) = try saveToDocuments(markdownText: markdownText, csvText: nil, jsonData: jsonData, reportDate: reportDate)
        return (mdURL, jsonURL)
    }

    /// 兼容旧版调用与单测的二元元组重载
    static func createExportFiles(
        markdownText: String,
        jsonData: Data?
    ) -> (markdownURL: URL, jsonURL: URL?) {
        let (mdURL, _, jsonURL) = createExportFiles(markdownText: markdownText, csvText: nil, jsonData: jsonData)
        return (mdURL, jsonURL)
    }
}
