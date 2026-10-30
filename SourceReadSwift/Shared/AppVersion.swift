import Foundation

/// 版本号单一来源：Info.plist（由 project.yml 注入）。
/// UI 不再维护 1.0.96 这类硬编码副本，避免安装包版本与「关于」页漂移。
public enum AppVersion {
    private static var versionComponents: (epic: Int, major: Int, minor: Int) {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let parts = (raw ?? "1.0.118").split(separator: ".").compactMap { Int($0) }
        return (
            parts.indices.contains(0) ? parts[0] : 1,
            parts.indices.contains(1) ? parts[1] : 0,
            parts.indices.contains(2) ? parts[2] : 118
        )
    }

    public static var epic: Int { versionComponents.epic }
    public static var major: Int { versionComponents.major }
    public static var minor: Int { versionComponents.minor }
    public static var build: Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Int(raw ?? "") ?? 118
    }

    public static var versionString: String {
        "\(epic).\(major).\(minor)"
    }

    public static var displayString: String {
        "版本 \(versionString)"
    }

    public static var fullDisplayString: String {
        "版本 \(versionString) (Build \(build))"
    }
}