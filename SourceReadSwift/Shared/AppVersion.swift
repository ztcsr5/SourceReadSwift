import Foundation

/// 统一版本号管理规范
/// 格式：[巨大版本].[大版本].[小版本]
/// - 最前面为巨大版本 (Epic / Generation)
/// - 中间为大版本 (Feature / Major Architecture)
/// - 最后面为小版本 (Fix / Patch / Detail Optimization)
public enum AppVersion {
    /// 巨大版本
    public static let epic: Int = 1
    /// 大版本
    public static let major: Int = 0
    /// 小版本
    public static let minor: Int = 0
    /// 内部构建号
    public static let build: Int = 1

    /// 标准语义化版本号：1.0.0
    public static var versionString: String {
        "\(epic).\(major).\(minor)"
    }

    /// 用户界面展示文本：版本 1.0.0
    public static var displayString: String {
        "版本 \(versionString)"
    }

    /// 完整诊断与关于展示文本：版本 1.0.0 (Build 1)
    public static var fullDisplayString: String {
        "版本 \(versionString) (Build \(build))"
    }
}
