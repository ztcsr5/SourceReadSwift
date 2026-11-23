import Foundation

struct ReaderReviewComment: Equatable, Sendable {
    let author: String?
    let text: String
    let likes: Int?
}

enum ReaderReviewResponse {
    case comments([ReaderReviewComment]), website, rejected(String)

    static func decode(_ bytes: Data) -> Self {
        guard bytes.count <= 2 * 1024 * 1024 else { return .rejected("评论页过大，请查看书源原网页。") }
        guard let root = try? JSONSerialization.jsonObject(with: bytes) else {
            let prefix = String(decoding: bytes.prefix(1024), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return prefix.hasPrefix("<") ? .website : .rejected("书源没有返回可识别的评论。")
        }
        if let object = root as? [String: Any] {
            let code = object["code"].map { String(describing: $0) }
            if object["success"] as? Bool == false || code.map({ !["0", "1", "200"].contains($0) }) == true {
                return .rejected("书源拒绝了评论请求，请到原网页核对登录状态。")
            }
        }
        guard let rows = list(root, depth: 0) else { return .rejected("当前书源的评论格式需在原网页查看。") }
        let parsed = rows.prefix(200).compactMap { raw -> ReaderReviewComment? in
            guard let row = raw as? [String: Any], let text = string(row, ["content", "text", "commentContent", "reviewContent", "Content", "body"]) else { return nil }
            let user = (row["user"] ?? row["userInfo"] ?? row["user_info"]) as? [String: Any]
            let names = ["nickname", "nickName", "userName", "user_name", "name", "author", "UserName"]
            let likes = (row["likeCount"] ?? row["like_count"] ?? row["likes"]) as? NSNumber
            return .init(author: (user.flatMap { string($0, names) } ?? string(row, names)).map { String($0.prefix(100)) },
                         text: String(text.prefix(6000)), likes: likes.flatMap { $0.intValue >= 0 ? $0.intValue : nil })
        }
        return !rows.isEmpty && parsed.isEmpty ? .rejected("评论条目缺少正文，请查看原网页。") : .comments(parsed)
    }

    private static func string(_ row: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = row[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return nil
    }

    private static func list(_ value: Any, depth: Int) -> [Any]? {
        if let rows = value as? [Any] { return rows }
        guard depth < 4, let object = value as? [String: Any] else { return nil }
        for key in ["comments", "commentList", "reviewList", "paragraphCommentList", "list", "items", "data", "Data", "result"] {
            if let child = object[key], let rows = list(child, depth: depth + 1) { return rows }
        }
        return nil
    }
}
